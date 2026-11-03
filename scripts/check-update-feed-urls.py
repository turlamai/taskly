#!/usr/bin/env python3
"""Keep Taskly's signed artifact URLs and client update feeds on one canonical owner.

This checks source configuration, not a generated/cryptographically verified
release manifest. Actual release assets, signatures and N→N+1 must be tested
at the exact release candidate before publication.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
CANONICAL = "https://github.com/turlamai/taskly"
LEGACY = "https://github.com/turinglambdaai/taskly"

REQUIRED = {
    "scripts/make-update-manifest.sh":
        'BASE_URL="${RELEASE_ASSET_BASE_URL:-' + CANONICAL
        + '/releases/download/$TAG}"',
    "racket/taskly/updater.rkt":
        '"' + CANONICAL + '/releases/latest/download"',
    "macos-host/Sources/RivetHost/UpdateService.swift":
        '"' + CANONICAL + '/releases/latest/download/update-manifest.json"',
    "shared/spec/UPDATE.md":
        CANONICAL + '/releases/latest/download/update-manifest.json',
}

errors = []
for relative, expected in REQUIRED.items():
    text = (ROOT / relative).read_text(encoding="utf-8")
    if expected not in text:
        errors.append(f"{relative}: expected canonical release URL not found")
    if LEGACY in text:
        errors.append(f"{relative}: legacy owner URL found")

# Repo-wide legacy-owner scan: menu links and release URLs have drifted to
# the old name in files outside REQUIRED before (Windows/Linux/macOS hosts).
# Scan every git-tracked text file so no new occurrence can slip through;
# this script is excluded because it must name the legacy owner to match it.
tracked = subprocess.run(
    ["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True
).stdout.split(b"\0")
for raw in tracked:
    if not raw:
        continue
    relative = Path(raw.decode("utf-8", "surrogateescape"))
    if relative.parts[:1] == ("scripts",) and relative.name == Path(__file__).name:
        continue
    path = ROOT / relative
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if LEGACY in text:
        errors.append(f"{relative}: legacy owner URL found (repo-wide scan)")

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)
print("Taskly signed artifact and update-feed URL contracts match canonical owner")
