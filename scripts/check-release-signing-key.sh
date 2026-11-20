#!/usr/bin/env bash
# Verify that the release Ed25519 private key is trusted by the updater.
# Since the glaze rewrite (issue #141) the engine updater is the single
# verifier; the native macOS trust root retired with its host.
# This check runs before expensive packaging and again before publication.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PEM="${1:-}"

fail() {
  echo "::error::Taskly release signing preflight: $*" >&2
  exit 1
}

[[ -n "$KEY_PEM" && -s "$KEY_PEM" ]] || fail "nonempty signing key file is required"
command -v openssl >/dev/null || fail "openssl is required"
command -v base64 >/dev/null || fail "base64 is required"

PUBLIC_DER="$(mktemp)"
trap 'rm -f "$PUBLIC_DER"' EXIT
if ! openssl pkey -in "$KEY_PEM" -pubout -outform DER > "$PUBLIC_DER" 2>/dev/null; then
  fail "signing key is invalid or unreadable"
fi
# Ed25519 SubjectPublicKeyInfo DER is 44 bytes; reject other key algorithms.
[[ "$(wc -c < "$PUBLIC_DER" | tr -d '[:space:]')" == "44" ]] || fail "signing key must be Ed25519"

DER_PUBLIC="$(base64 -w0 < "$PUBLIC_DER")"
EXPECTED_DER="$(sed -n '/(define update-public-key-b64/{n;s/^[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ROOT/racket/taskly/updater.rkt")"

[[ -n "$EXPECTED_DER" && "$DER_PUBLIC" == "$EXPECTED_DER" ]] ||
  fail "signing key does not match the Racket updater trust root"

echo "Release signing key matches the updater trust root"
