#!/usr/bin/env bash
set -euo pipefail
trap 'echo "E2E-TRACE failed at line $LINENO (exit=$?)" >&2' ERR

repo="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo/.rivet/acceptance/macos"
install_record="$output/installed-app.json"
if [[ -f "$install_record" ]]; then
  app="$(plutil -extract executable raw -o - "$install_record")"
  installed_application="$(plutil -extract application raw -o - "$install_record")"
else
  app="$repo/dist/taskly.app/Contents/MacOS/taskly"
  installed_application=""
fi
driver="$output/macos-ax"
home="$output/home-$$"
mkdir -p "$output" "$home/.taskly" "$home/.taskly"
[[ -x "$app" ]]

epoch="$(date +%s)"
# §2a: the interaction flow runs against a recorded database — the welcome
# gate is a dedicated scenario below. The CLI seeds a real v5 database file
# (open-or-create semantics unchanged), then config records it.
seed_db="$home/seed.db"
HOME="$home" bash "$repo/scripts/taskly-cli.sh" --db "$seed_db" list >/dev/null
[[ -f "$seed_db" ]]
cat >"$home/.taskly/config.ini" <<EOF
# Taskly acceptance profile
language = en
close-to-tray = 0
last-selected-list-id = 0
last-update-check = $epoch
last-db-path = $seed_db
last-db-name = Acceptance Home
EOF

swiftc "$repo/scripts/e2e/macos-ax.swift" -o "$driver" \
  -framework AppKit -framework ApplicationServices

HOME="$home" "$app" >"$output/application.log" 2>&1 &
app_pid=$!

stop_bounded() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 200); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL "$pid" 2>/dev/null || true
  return 1
}

cleanup() {
  local status=$?
  trap - EXIT
  if kill -0 "$app_pid" 2>/dev/null; then
    stop_bounded "$app_pid" || true
    wait "$app_pid" 2>/dev/null || true
  fi
  if [[ -n "$installed_application" ]]; then
    data_preserved=false
    [[ -f "$home/.taskly/tasks.db" ]] && data_preserved=true
    rm -rf "$installed_application"
    application_removed=false
    [[ ! -e "$installed_application" ]] && application_removed=true
    printf '{"installer":"dmg","applicationRemoved":%s,"dataPreserved":%s}\n' \
      "$application_removed" "$data_preserved" >"$output/install-lifecycle.json"
    if [[ "$status" -eq 0 && "$data_preserved" != true ]]; then status=1; fi
    if [[ "$application_removed" != true ]]; then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT

"$driver" --pid "$app_pid" --output "$output"
for _ in $(seq 1 200); do
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 0.05
done
if kill -0 "$app_pid" 2>/dev/null; then
  echo "Taskly did not exit after the native termination request" >&2
  exit 1
fi
wait "$app_pid" || true
app_pid=""

HOME="$home" "$app" >"$output/application-restart.log" 2>&1 &
app_pid=$!
"$driver" --pid "$app_pid" --output "$output" --verify-restart
wait "$app_pid"
app_pid=""

# ---- §2a database lifecycle scenarios (dedicated profiles) ----------------

# Welcome gate → exclusive create: fresh profile with no recorded database.
gate_home="$output/gate-home-$$"
mkdir -p "$gate_home/.taskly"
cat >"$gate_home/.taskly/config.ini" <<EOF
# Taskly gate acceptance profile
language = en
close-to-tray = 0
last-update-check = $epoch
EOF
# NSOpenPanel remembers its last directory per app; pin it so the create
# flow's folder panel opens at the profile home without keyboard navigation
# (blind Cmd+Shift+G proved flaky on CI runners).
defaults write app.taskly.Taskly NSNavLastRootDirectory "$gate_home"
HOME="$gate_home" "$app" >"$output/application-gate.log" 2>&1 &
app_pid=$!
"$driver" --pid "$app_pid" --output "$output" --home "$gate_home" --database-gate
wait "$app_pid" || true
app_pid=""

# Recovery → 重试: the recorded database is missing at boot; the harness
# restores the file mid-run while the driver retries.
recovery_home="$output/recovery-home-$$"
mkdir -p "$recovery_home/.taskly" "$recovery_home/data"
recovery_db="$recovery_home/data/vanish.db"
HOME="$recovery_home" bash "$repo/scripts/taskly-cli.sh" --db "$recovery_db" list >/dev/null
mv "$recovery_db" "$recovery_db.stash"
cat >"$recovery_home/.taskly/config.ini" <<EOF
# Taskly recovery acceptance profile
language = en
close-to-tray = 0
last-update-check = $epoch
last-db-path = $recovery_db
EOF
HOME="$recovery_home" "$app" >"$output/application-recovery.log" 2>&1 &
app_pid=$!
"$driver" --pid "$app_pid" --output "$output" --home "$recovery_home" \
  --database-recovery-retry &
driver_pid=$!
sleep 3
mv "$recovery_db.stash" "$recovery_db"
wait "$driver_pid"
stop_bounded "$app_pid" || true
wait "$app_pid" 2>/dev/null || true
app_pid=""

# Settings 数据 group: migrate / export / restore against the seeded home.
defaults write app.taskly.Taskly NSNavLastRootDirectory "$home"
HOME="$home" "$app" >"$output/application-settings.log" 2>&1 &
app_pid=$!
"$driver" --pid "$app_pid" --output "$output" --home "$home" --database-settings
stop_bounded "$app_pid" || true
wait "$app_pid" 2>/dev/null || true
app_pid=""
