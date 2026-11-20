#!/usr/bin/env bash
# Dependency-pin preflight for the glaze-line tree (issue #141 slice 4).
#
# Three pins travel together:
#   RIVET_PIN — engine contract tooling (schema check, sign-manifest) and the
#               engine test suite; the engine itself is unchanged (Keep).
#   KEEL_PIN  — rivet's dependency, pinned below its tests/documentation
#               collision commit (upstream issue filed).
#   GLAZE_PIN — the UI/host framework every build and acceptance leg installs.
# Every workflow that installs one of them must carry the same value in its
# top-level env block, so a bump is one edit per pin, not a grep-replace.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS=(
  "$ROOT/.github/workflows/ci.yml"
  "$ROOT/.github/workflows/acceptance.yml"
  "$ROOT/.github/workflows/release.yml"
)

fail() {
  echo "dependency pin preflight: $*" >&2
  exit 1
}

env_pin() {
  local file="$1"
  local name="$2"
  sed -nE "s/^[[:space:]]*${name}:[[:space:]]*([0-9a-f]{40})[[:space:]]*$/\\1/p" "$file" | head -n1
}

for name in RIVET_PIN KEEL_PIN GLAZE_PIN; do
  base="$(env_pin "${WORKFLOWS[0]}" "$name")"
  [[ -n "$base" ]] || fail "missing $name in ci.yml"
  for workflow in "${WORKFLOWS[@]}"; do
    pin="$(env_pin "$workflow" "$name")"
    [[ -n "$pin" ]] || fail "missing $name in ${workflow#"$ROOT/"}"
    [[ "$pin" == "$base" ]] || \
      fail "$name drift: ${workflow#"$ROOT/"} has $pin, expected $base"
  done
  # Every install reference in the workflows must use the env pin (or the
  # same literal), never a drifting hard-coded commit.
  while IFS= read -r ref; do
    [[ "$ref" == "$base" ]] || \
      fail "$name install ref $ref does not match env pin $base"
  done < <(
    case "$name" in
      RIVET_PIN) grep -h -oE 'turlamai/rivet\.git#[0-9a-f]{40}' "${WORKFLOWS[@]}" | sed -E 's/.*#//' ;;
      KEEL_PIN)  grep -h -oE 'turlamai/keel\.git#[0-9a-f]{40}' "${WORKFLOWS[@]}" | sed -E 's/.*#//' ;;
      GLAZE_PIN) grep -h -oE 'turlamai/glaze\.git#[0-9a-f]{40}' "${WORKFLOWS[@]}" | sed -E 's/.*#//' ;;
    esac
  )
done

# Migration must not hide dependency refs from the checker: reject old remote
# names and verify that the current namespace is explicitly represented.
if grep -qE 'turinglambdaai/(rivet|keel|glaze)' "${WORKFLOWS[@]}"; then
  fail "legacy GitHub namespace in workflow dependency references"
fi

RIVET_PIN="$(env_pin "${WORKFLOWS[0]}" RIVET_PIN)"
KEEL_PIN="$(env_pin "${WORKFLOWS[0]}" KEEL_PIN)"
GLAZE_PIN="$(env_pin "${WORKFLOWS[0]}" GLAZE_PIN)"
echo "dependency pin preflight: aligned (Rivet $RIVET_PIN, Keel $KEEL_PIN, Glaze $GLAZE_PIN)"