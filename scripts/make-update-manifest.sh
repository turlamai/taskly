#!/usr/bin/env bash
# Build update-manifest.json for a release and sign it (shared/spec/UPDATE.md).
#
#   scripts/make-update-manifest.sh <tag> <dist-dir> [key-path]
#
#   <tag>       release tag, e.g. v1.2.0 (must match the VERSION file)
#   <dist-dir>  directory containing the release artifacts, i.e. the names
#               the release pipeline produces:
#                 taskly-<ver>-macos-arm64.zip   taskly-<ver>-macos-x64.zip
#                 taskly-<ver>-windows-x64.zip   taskly-<ver>-windows-x64.msi
#                 taskly-<ver>-linux-x64.tar.gz   taskly-<ver>-linux-arm64.tar.gz
#                 taskly-<ver>-linux-x86_64.AppImage
#                 taskly-<ver>-linux-aarch64.AppImage
#   <key-path>  Ed25519 private key PEM (default: $UPDATE_KEY_PATH, then
#               ~/.taskly/update-signing-key.pem)
#
# The signing, artifact hashing, manifest validation, and feed format live
# in `raco rivet sign-manifest`; this wrapper owns only Taskly's artifact
# matrix and release identity. The feed is the family format every
# rivet/distribution client verifies, hosts included.
set -euo pipefail

TAG="${1:?usage: make-update-manifest.sh <tag> <dist-dir> [key-path]}"
DIST="${2:?usage: make-update-manifest.sh <tag> <dist-dir> [key-path]}"
KEY="${3:-${UPDATE_KEY_PATH:-$HOME/.taskly/update-signing-key.pem}}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$(cd "$DIST" && pwd)"
cd "$ROOT"

VERSION="${TAG#v}"
[[ "$VERSION" == "$(tr -d '[:space:]' < "$ROOT/VERSION")" ]] || {
  echo "error: tag $TAG does not match VERSION '$(cat "$ROOT/VERSION")'" >&2
  exit 1
}

APPLICATION_ID="$(sed -nE 's/.*\(identifier \. "([^"]+)"\).*/\1/p' "$ROOT/rivet.rktd" | head -n1)"
BUILD="$(sed -nE 's/.*\(build \. ([0-9]+)\).*/\1/p' "$ROOT/rivet.rktd" | head -n1)"
KEY_ID="$(sed -n 's/^(define update-key-id "\([^"]*\)".*/\1/p' "$ROOT/racket/taskly/updater.rkt")"
[[ -n "$APPLICATION_ID" && -n "$BUILD" && "$KEY_ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "error: could not read the release identity or update-key-id" >&2
  exit 1
}

BASE_URL="${RELEASE_ASSET_BASE_URL:-https://github.com/turlamai/taskly/releases/download/$TAG}"

# Ed25519 needs OpenSSL 3+ (macOS ships LibreSSL, which cannot do it).
OPENSSL_BIN="${OPENSSL_BIN:-}"
if [[ -z "$OPENSSL_BIN" ]]; then
  for candidate in /opt/homebrew/opt/openssl@3/bin/openssl \
                   /usr/local/opt/openssl@3/bin/openssl openssl; do
    if command -v "$candidate" >/dev/null 2>&1 \
       && "$candidate" version 2>/dev/null | grep -q "OpenSSL 3"; then
      OPENSSL_BIN="$candidate"
      break
    fi
  done
fi
[[ -n "$OPENSSL_BIN" ]] || {
  echo "error: OpenSSL 3.x required for Ed25519 (brew install openssl@3," >&2
  echo "       or set OPENSSL_BIN=/path/to/openssl)" >&2
  exit 1
}
[[ -f "$KEY" ]] || {
  echo "error: missing signing key $KEY (see scripts/update-keys.sh)" >&2
  exit 1
}

# rivet's signer reads DER (OneAsymmetricKey); convert the PEM once here.
KEY_DER="$(mktemp /tmp/taskly-key-XXXXXX.der)"
trap 'rm -f "$KEY_DER"' EXIT
"$OPENSSL_BIN" pkey -in "$KEY" -outform DER -out "$KEY_DER"

raco rivet sign-manifest \
  --application-id "$APPLICATION_ID" \
  --version "$VERSION" \
  --build "$BUILD" \
  --channel stable \
  --base-url "$BASE_URL" \
  --key-id "$KEY_ID" \
  --private-key "$KEY_DER" \
  --output "$DIST/update-manifest.json" \
  --artifact "macos:arm64:zip:$DIST/taskly-$VERSION-macos-arm64.zip" \
  --artifact "macos:x64:zip:$DIST/taskly-$VERSION-macos-x64.zip" \
  --artifact "windows:x64:zip:$DIST/taskly-$VERSION-windows-x64.zip" \
  --artifact "windows:x64:msi:$DIST/taskly-$VERSION-windows-x64.msi" \
  --artifact "linux:x64:targz:$DIST/taskly-$VERSION-linux-x64.tar.gz" \
  --artifact "linux:x64:appimage:$DIST/taskly-$VERSION-linux-x86_64.AppImage" \
  --artifact "linux:arm64:targz:$DIST/taskly-$VERSION-linux-arm64.tar.gz" \
  --artifact "linux:arm64:appimage:$DIST/taskly-$VERSION-linux-aarch64.AppImage" \
  --rollback-allowed

echo "manifest: $DIST/update-manifest.json (8 artifacts, key-id $KEY_ID)"
