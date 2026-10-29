# Local Explorer

A native, fully offline file manager for macOS on Apple Silicon. Its layout follows
Windows File Explorer (sidebar, toolbar, breadcrumb path, Details view, preview pane,
status bar), and the interface uses a glassmorphism style: frosted, translucent panels
that float over a blurred, tinted backdrop.

* Swift + SwiftUI, with AppKit where file managers need it (tables, drag-and-drop,
  menus, PDFKit, AVKit, Quick Look).
* No Electron, web views, backend, accounts, analytics or network requests. See
  [docs/PRIVACY.md](docs/PRIVACY.md).
* The product name is configurable at build time (`APP_NAME=…`).

## Requirements

| | |
|---|---|
| Mac | Apple Silicon (arm64) |
| macOS | 14 Sonoma or later (Liquid Glass is used automatically on macOS 26 when built with Xcode 26) |
| Tools | Xcode 16 or later (or matching Command Line Tools). XcodeGen only for UI tests |

The package has **no third-party dependencies**, so building never needs the network.

## Build and run

```sh
make app      # builds "build/Local Explorer.app" (release, arm64, ad-hoc signed)
make run      # build and open it
make test     # ExplorerCore unit + integration tests (swift test)
make test-offline   # the same tests with outbound networking denied by sandbox-exec
make uitest   # UI tests via an XcodeGen-generated Xcode project
```

Options for `scripts/build-app.sh`: `APP_NAME`, `BUNDLE_ID`, `VERSION`, `CONFIGURATION=debug`,
`SIGN_IDENTITY="Developer ID Application: …"`.

To work in Xcode, either open `Package.swift` directly (app + core + unit tests) or run
`make xcodeproj` and open `LocalExplorer.xcodeproj` (adds the UI test target).

## Project layout

```
Sources/ExplorerCore/      Foundation-only logic. Builds and tests on macOS and Linux.
  Model/                   FileItem, FileCategory
  Filesystem/              enumeration, metadata, content sniffing, type detection
  Explorer/                sorting, filtering/search, selection
  Navigation/              history, breadcrumbs, path parsing
  Commands/                command table: titles, shortcuts, routing, enablement
  FileOperations/          copy/move/rename/duplicate/trash/delete, conflicts, batch rename, undo records
  Preview/                 preview-type selection, safe text decoding, zoom maths
  Persistence/             preferences, favorites, recents, bookmarks (JSON in Application Support)
Sources/LocalExplorer/     macOS app (SwiftUI + AppKit)
  App/  Explorer/  Navigation/  FileBrowser/  Inspector/  Preview/  FileOperations/
  Filesystem/  Access/  Settings/  UI/Glass/
Tests/ExplorerCoreTests/   unit + integration tests on temporary directories
UITests/                   XCUITest suite (fixture folders in the temp directory)
Support/                   Info.plist template, entitlements (direct + sandboxed), icon
```

## Features

**Browsing.** Details (sortable, resizable, hideable columns, persisted), Tiles (adjustable
thumbnail size), Compact List and Gallery views. Folders on top, ascending/descending
sort by name, date modified, date created, size and type. Tabs, back/forward history,
breadcrumbs that turn into an editable path field (`~`, relative paths). Sidebar with
Favorites (drag folders in), standard folders, Recent, mounted volumes (eject) and
authorized locations; every folder has an arrow that expands its subfolders in place
(state is remembered, and the current folder is revealed as you navigate). Status bar with item/selection counts, selection size and free space.
Large folders are listed off the main thread; the UI is virtualized.

**Search.** Incremental filtering of the current folder: plain text, wildcards (`*.jpg`),
`kind:image`, `ext:pdf`. Hidden files toggle with ⇧⌘.

**File operations.** Copy, cut, paste (Finder-compatible pasteboard), move, rename with
validation, duplicate, new folder, Move to Trash, Delete Immediately (menu only, confirmed),
batch rename with live preview, drag-and-drop (move on the same volume, copy across volumes,
⌥ forces copy). Conflicts offer Replace / Keep Both / Skip / Cancel with "apply to remaining".
Progress and cancellation for long operations. Undo for create, rename, move, copy,
duplicate and Trash; permanent deletion is never undoable.

**Previews.** The preview type is chosen from the file's bytes first, then its type:

| Kind | Renderer | Pane (compact) | Gallery (full) |
|---|---|---|---|
| Images | ImageIO, NSImage for animated GIF | fitted image | zoom, fit, 1:1, rotate (display only), percent readout, pinch zoom |
| PDF | PDFKit | first pages, page count | single/continuous/two-page, thumbnails, page field, zoom, fit width, text search, password unlock |
| Video / audio | AVKit / AVFoundation | inline player | floating controls, full screen, speed, audio-track and subtitle menus |
| Text and code | own decoder (UTF-8/16, Windows-1252) | first 64 KB | first 512 KB, encoding, line count, wrap toggle |
| Office, iWork, RTF, SVG, fonts | Quick Look (QLPreviewView) | yes | yes |
| Everything else | icon + properties + Open | yes | yes |

Space opens the system Quick Look panel for the selection. Thumbnails come from
QuickLookThumbnailing, are generated asynchronously, cancelled when cells scroll away, and
cached in memory with keys that include size and modification date.

**Appearance.** Light, dark or system; five glass tints, a custom glass color, three frost
intensities and a transparency slider in Settings › Appearance. On macOS 26 the panels use
the system Liquid Glass material.

## Keyboard shortcuts

| Action | Keys | Notes |
|---|---|---|
| Copy / Cut / Paste | ⌘C / ⌘X / ⌘V | Text fields keep their own copy/paste |
| Rename | ↩ | File list only |
| Open | ⌘O, ⌘↓, double-click | |
| Move to Trash | ⌘⌫ | |
| Get Info (preview pane) | ⌘I | |
| Select All | ⌘A | |
| New Folder | ⇧⌘N | |
| Show/Hide Hidden Files | ⇧⌘. | |
| Tiles / Compact List / Gallery / Details | ⌘1 / ⌘2 / ⌘3 / ⌘4 | |
| Quick Look | Space | File list only; a focused player keeps Space for play/pause |
| Cancel / close preview | ⎋ | |
| Search | ⌘F | |
| Edit path | ⌘L | |
| Enclosing folder | ⌘↑ | |
| Back / Forward | ⌘[ / ⌘] | |
| New Tab / Close Tab | ⌘T / ⌘W | ⇧⌘W closes the window |
| Next / Previous Tab | ⇧⌘] / ⇧⌘[ | |
| Refresh | ⌘R | |
| Context menu for selection | ⌃↩ | |
| Duplicate | ⌘D | |
| Copy Path | ⌥⌘C | |
| Preview pane | ⌥⌘P | |
| Sidebar | ⌃⌘S | Same as Finder |
| Home / Desktop / Documents / Applications | ⇧⌘H / ⇧⌘D / ⇧⌘O / ⇧⌘A | Same as Finder |
| Downloads | ⌥⌘L | Same as Finder |
| Image zoom in / out / actual size / fit | ⌘= / ⌘− / ⌘0 / ⌘9 | Gallery view |
| Arrow keys, ⇧-arrows, ⌘-click, ⇧-click | | Move, extend and toggle selection; type letters to jump |

Differences from the original shortcut proposal: Return, Space, Escape and ⌃↩ are handled
by the focused file list instead of the menu bar, so they never steal keys from text fields
or media players. System window tabbing is disabled so ⌘T/⌘W always mean in-window tabs.
**Delete Immediately has no shortcut on purpose** (File › Delete Immediately…, then confirm).

## Permissions

See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). In short: the default build is not
sandboxed and can browse whatever your user account can read, subject to macOS privacy
prompts (Desktop, Documents, Downloads, removable and network volumes). Protected locations
need Full Disk Access, which only you can grant in System Settings; the app links there but
cannot grant it to itself. "Grant Folder Access…" stores a bookmark so access survives
relaunch (required in the sandboxed build).

## Troubleshooting

* **"You don't have permission to view this folder."** Use *Grant Access…* in the error view,
  or add the app to System Settings › Privacy & Security › Full Disk Access and relaunch.
  System Integrity Protection still blocks system locations; that is expected.
* **A video shows "macOS can't play this file".** AVFoundation has no decoder for that codec
  or container (for example MKV, WebM/VP9, AVI with old codecs). Use *Open with Default App*.
* **Preview is blank for an Office/iWork file.** Quick Look has no generator for it on this
  Mac; the file icon and properties are still shown.
* **Favorites show a warning triangle.** The folder was moved, deleted or is on a disconnected
  volume. Reconnect the drive or remove the favorite.
* **UI tests can't control the app.** Allow Xcode (or `xcodebuild`) in System Settings ›
  Privacy & Security › Accessibility.
* **Reset settings.** Quit, then delete
  `~/Library/Application Support/app.localexplorer.LocalExplorer/State.json`. A damaged file
  is moved aside automatically and defaults are used.

## Further documentation

* [docs/PRIVACY.md](docs/PRIVACY.md): offline and privacy policy
* [docs/FORMATS.md](docs/FORMATS.md): image formats and media codecs, and their test status
* [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md): permissions, sandboxing, distribution limits
* [docs/IMPLEMENTATION_REPORT.md](docs/IMPLEMENTATION_REPORT.md): what works, what's incomplete, test results
