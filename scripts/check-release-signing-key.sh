#!/usr/bin/env bash
# Verify that the release Ed25519 private key is trusted by both updater clients.
# This check runs before expensive native packaging and again before publication.
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
RAW_PUBLIC="$(tail -c 32 "$PUBLIC_DER" | base64 -w0)"
EXPECTED_DER="$(sed -n '/(define update-public-key-b64/{n;s/^[[:space:]]*"\([^"]*\)".*/\1/p;}' "$ROOT/racket/taskly/updater.rkt")"
EXPECTED_RAW="$(sed -n 's/.*public static let publicKeyBase64 = "\([^"]*\)".*/\1/p' "$ROOT/macos-host/Sources/RivetHost/UpdateService.swift")"

[[ -n "$EXPECTED_DER" && "$DER_PUBLIC" == "$EXPECTED_DER" ]] ||
  fail "signing key does not match the Racket updater trust root"
[[ -n "$EXPECTED_RAW" && "$RAW_PUBLIC" == "$EXPECTED_RAW" ]] ||
  fail "signing key does not match the macOS updater trust root"

echo "Release signing key matches both updater trust roots"
