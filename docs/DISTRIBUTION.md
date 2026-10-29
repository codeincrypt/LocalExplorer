# Permissions and distribution

Access to files on macOS depends on your consent, system policy, the sandbox configuration
and your account's own permissions. Local Explorer never implies that every path is
accessible and never tries to work around these controls.

## The two build configurations

| | Direct distribution (default) | Mac App Store (sandboxed) |
|---|---|---|
| Entitlements | `Support/LocalExplorer.entitlements` (empty; hardened runtime) | `Support/LocalExplorer.sandboxed.entitlements` |
| What it can browse | Anything your user account can read, minus TCC-protected locations | Only folders you choose with *Grant Folder Access…*, plus Downloads, Pictures, Music, Movies |
| Remembering access | Plain bookmarks (for moved folders) | Security-scoped bookmarks, started at launch, released on removal or quit |
| Full Disk Access | Can be granted by you in System Settings | Has no effect on the sandbox boundary |
| Network | No entitlement needed (it makes no connections) | No `network.client` entitlement, so connections are impossible |
| Signing | Ad-hoc locally; Developer ID + notarization to share | App Store signing |

To build the sandboxed variant, sign with the sandboxed entitlements:

```sh
codesign --force --options runtime --entitlements Support/LocalExplorer.sandboxed.entitlements \
  --sign "Apple Distribution: …" "build/Local Explorer.app"
```

The access layer (`Sources/LocalExplorer/Access/AccessManager.swift`) works for both: it tries
security-scoped bookmarks first and falls back to plain bookmarks, and
`AccessManager.isSandboxed` reports which mode is running (shown in Settings › Access).

**Trade-off.** The direct build behaves like a real file manager: it can browse your whole
home folder and every mounted volume. It can't go through the Mac App Store, and protected
locations still need Full Disk Access. The sandboxed build is App Store-compatible and safer
by construction, but you must grant each location outside the standard folders once. It
also can't reach other volumes until you pick them.

## macOS permissions the app may trigger

| Permission | When | Where to change |
|---|---|---|
| Desktop, Documents, Downloads folder access | First time you open those folders (direct build) | System Settings › Privacy & Security › Files and Folders |
| Removable volumes | First time you browse a USB drive or SD card | same |
| Network volumes | First time you browse an already-mounted server share | same |
| Full Disk Access | Optional, for Mail, Messages, Safari data, Time Machine, other users | System Settings › Privacy & Security › Full Disk Access (the app's *Open Full Disk Access Settings* button goes there) |
| Accessibility | Only for running the UI tests (granted to Xcode/xcodebuild, not the app) | System Settings › Privacy & Security › Accessibility |

## Limits that apply regardless of build

* **System Integrity Protection** blocks changes to `/System`, `/usr` (except `/usr/local`) and
  other protected paths even with Full Disk Access. The app shows the permission error and
  does not attempt to bypass it.
* **POSIX permissions and ACLs** are respected. Read-only folders show a "Read only" badge,
  and operations that need write access fail with an explanation.
* **The app cannot grant itself Full Disk Access.** Only you can, in System Settings.
* **Disconnected volumes and stale bookmarks** are detected at launch and when navigating.
  Unavailable favorites and authorized folders get a warning badge instead of an error loop.
* **Symbolic links** are shown with an alias badge. Broken links are flagged and never
  followed for operations, and copying a folder into itself or a descendant is refused.
* **Trash** uses the system Trash (`FileManager.trashItem`). On volumes without a Trash, Move
  to Trash fails with an explanation (“can’t be moved to the Trash on this volume”); the files
  are left untouched and Delete Immediately remains available from the File menu.
