#!/usr/bin/env bash
# Offline negative tests: bad keys must fail before platform packaging.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

reject() {
  if bash "$ROOT/scripts/check-release-signing-key.sh" "$1" > "$TMP/result.log" 2>&1; then
    echo "Expected release signing preflight to reject $2" >&2
    exit 1
  fi
}

reject "$TMP/missing.pem" "missing key"
printf 'not a PEM key\n' > "$TMP/invalid.pem"
reject "$TMP/invalid.pem" "malformed key"
openssl genpkey -algorithm ED25519 -out "$TMP/untrusted.pem" >/dev/null 2>&1
reject "$TMP/untrusted.pem" "untrusted Ed25519 key"
echo "Release signing preflight rejects missing, malformed, and untrusted keys"
