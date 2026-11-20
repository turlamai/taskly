# Third-Party Notices

Taskly builds on third-party software. This file is the maintained
inventory. Releases publish per-asset SHA-256 sidecars, a `SHA256SUMS`
manifest, the Ed25519-signed update manifest and GitHub artifact
attestations; the per-build generated notices/SBOM files retired with the
native release toolchain (issue #141), so this overview is the reviewer's
entry point.

## Racket runtime and catalog packages

The distributed runtime embeds Racket CS (9.3) in the host process
(glaze build / `raco exe`, static engine require). Taskly's declared
package dependencies (`racket/info.rkt`) are `base`, `crypto-lib`,
`db-lib`, `net-lib` and `rivet`.

- The Racket runtime and its main-distribution packages in the
  embedded closure — including `base`, `db-lib`, `net-lib` and
  `cext-lib` — are dual-licensed Apache-2.0 OR MIT per their package
  metadata and the `LICENSE-MIT.txt` / `LICENSE-APACHE.txt` files
  shipped with the Racket distribution.
- `crypto-lib` (Ed25519 / SPKI key handling for the updater) is
  Apache-2.0 per its package metadata.
- `rackunit-lib` (Apache-2.0 OR MIT) is a build/test dependency only;
  it is not part of the shipped runtime.
- [Rivet](https://github.com/turlamai/rivet) — typed RPC contract, RVT1
  transport and release signing machinery — is MIT.
  [Keel](https://github.com/turlamai/keel), part of Rivet's runtime
  dependency closure, is MIT.
- [glaze](https://github.com/turlamai/glaze) — the single first-party
  host runtime (webview window, tray, global hotkey, autostart, typed
  routes, packaging) — is MIT.

## Linux bundles

The Linux host renders through WebKitGTK 4.1 and GLib — system libraries
on deb/rpm/tarball/Flatpak installs, part of the bundled dependency
closure inside the AppImage. These GNOME libraries are licensed
LGPL-2.1 and are used as unmodified shared libraries. The exact bundled
set for an AppImage build is listed in that build's runtime closure.

## Platform frameworks

The single host consumes OS-provided webview engines: WebView2 on
Windows (Microsoft Evergreen runtime), WKWebView on macOS, WebKitGTK on
Linux. These ship with the operating system or its runtime
redistributable; no separate notice inventory is reproduced here.
