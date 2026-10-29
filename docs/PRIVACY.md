# Offline and privacy policy

Local Explorer is designed to work with networking switched off and to keep everything
on your Mac.

## What the app does not do

* No backend, account, sign-in or cloud sync.
* No analytics, telemetry, crash reporting or "phone home" of any kind.
* No update checks. New versions are installed by replacing the app.
* No online AI, remote fonts, icons, images, scripts or style sheets. All assets are bundled.
* No runtime downloads of libraries or codecs.
* No network requests for browsing, previews, thumbnails, search or file operations.
* Text previews have link and data detection turned off, so nothing in a file becomes a
  clickable remote link or is looked up.

The default build carries **no network entitlement**. The sandboxed (App Store) build omits
`com.apple.security.network.client`, so the process cannot open outbound connections at all.

## What the app stores

One JSON file, `~/Library/Application Support/<bundle id>/State.json`, containing:

* preferences (view mode, sort, panel sizes, glass tint and so on)
* favorites, authorized folders (paths and bookmark data) and recent folders
* the paths of open tabs, if "Reopen tabs" is on

It stores **no file contents**. Thumbnails live only in memory, are bounded by a size
limit you set, and can be cleared in Settings › Privacy. Recent folders can be cleared
there too. The filesystem is always the source of truth: stored paths are rechecked and
nothing is treated as an inventory of your disk.

## Verifying it

* `make test-offline` runs the test suite under `sandbox-exec` with all outbound IP
  traffic denied. Any network attempt by the code under test fails and is logged as a
  sandbox violation.
* `scripts/offline-test.sh --app` launches the built app under the same profile. Watch for
  violations with
  `log stream --predicate 'eventMessage CONTAINS "deny(1) network"' --style compact`.
* `OfflineSourceScanTests` fails the test run if any source file (core or app) uses networking APIs (URLSession, Network.framework, WebKit, sockets) or contains a remote URL.

## macOS behaviour outside the app's control

These are system services the app calls but cannot fully control:

* **Quick Look generators** (Office, iWork, RTF, SVG, fonts) run in Apple's or third-party
  generator processes. Apple's generators do not fetch remote content for these types, but a
  third-party generator you have installed could.
* **Opening a file in another app** (Open, Open With) hands it to that app, which follows its
  own network behaviour.
* **Network volumes** you have already mounted are browsed through the system's file
  provider. The app never mounts volumes or connects to servers itself; bookmark resolution
  uses `withoutMounting`.
* **iCloud Drive / File Provider folders** may download a file when its contents are read
  (for a preview or a copy). That download is done by macOS, not the app.
* **Gatekeeper and notarization checks** happen when macOS launches any app.
