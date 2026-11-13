#!/usr/bin/env bash
# Generate the Ed25519 keypair used to sign update manifests (macOS/Linux
# contract: shared/spec/UPDATE.md).
#
#   scripts/update-keys.sh [private-key-path]
#
# Default private key location: ~/.taskly/update-signing-key.pem — OUTSIDE
# the repository. `raco rivet update-keys` prints every embedding form:
# the DER base64 for UPDATE_ED25519_PRIVATE_KEY, the SPKI hex/base64 for
# the Racket verifier, and the raw 32-byte base64 for
# macos-host/Sources/RivetHost/UpdateService.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PATH="${1:-$HOME/.taskly/update-signing-key.pem}"
KEY_ID="$(sed -n 's/^(define update-key-id "\([^"]*\)".*/\1/p' "$ROOT/racket/taskly/updater.rkt")"
[[ "$KEY_ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "error: could not read a valid update-key-id from racket/taskly/updater.rkt" >&2
  exit 1
}

exec raco rivet update-keys --key "$KEY_PATH" --key-id "$KEY_ID"
