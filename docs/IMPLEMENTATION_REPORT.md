# Implementation report

_Last updated: 29 Oct 2026_

## Summary

All five milestones are implemented in code. The platform-independent core (ExplorerCore)
is **built and tested**: 109 tests, 0 failures, 2 skipped (permission tests skip when run as
root). The macOS app layer (SwiftUI/AppKit) is **written but not yet compiled**. The
development environment for this pass was Linux (no macOS SDK), and the linked Mac could not
be reached during the session. Nothing in the app layer should be considered verified until
the "Verification on a Mac" steps below have been run.

## Test results

| Suite | Where | Result |
|---|---|---|
| ExplorerCore unit + integration (`swift test`) | Linux x86_64, Swift 6.0.3 | **109 run, 0 failed, 2 skipped** |
| Offline source scan (part of the above) | Linux | passed: no networking APIs or remote URLs in any source file |
| `make test-offline` (sandbox-exec, network denied) | needs macOS | not run |
| App build (`swift build`, `scripts/build-app.sh`) | needs macOS | **not run** |
| UI tests (`make uitest`, 10 tests) | needs macOS + Xcode | **not run** |
| Format/codec fixtures (docs/FORMATS.md) | needs macOS | **not run** |
| Performance baselines | needs Apple Silicon | **not run** |

Test coverage in ExplorerCore: sorting (including 10,000 items), filtering and search syntax,
hidden files, selection (click/extend/toggle, keyboard movement in all layouts), navigation
history and breadcrumbs, path parsing, command routing and enablement (text-field
forwarding), file-type detection and content sniffing, preview-type selection, text decoding
(UTF-8/16, legacy encodings, binary rejection, truncation), zoom maths, filename validation,
conflict resolution (Replace / Keep Both / Skip / Cancel / apply-to-remaining), copy/move/
rename/duplicate/trash/delete on temporary trees, nested folders, symbolic links (including
broken ones), copy-into-self refusal, read-only folders, cancellation, undo, batch rename,
persistence across relaunch, corrupt-state recovery, thumbnail-key invalidation.

## Status by milestone

| Milestone | Scope | Status |
|---|---|---|
| 1 | App shell, Details view, navigation, metadata, sorting, hidden files | Code complete; core tested; UI unverified |
| 2 | Command router, copy/cut/paste, rename, new folder, Trash, tabs, conflict dialogs | Code complete; core tested; UI unverified |
| 3 | Tiles, Compact List, Gallery, preview pane, thumbnails, image + PDF previews | Code complete (preview engine added in this pass); UI unverified |
| 4 | Audio/video, text previews, search, favorites, recents, volume monitoring | Code complete; text decoding tested; UI unverified |
| 5 | Performance, access, offline, accessibility, errors, packaging, docs | Docs, packaging scripts, offline checks, UI tests written; measurements not taken |

## Added in this pass

* **Preview engine.** `PreviewProvider` protocol and `PreviewRegistry`; the kind is chosen from
  file bytes by `PreviewSelector` (ExplorerCore, unit-tested). Providers: image (ImageIO,
  zoom/fit/1:1/rotate, animated GIF, reduced copy above 12,000 px), PDF (PDFKit: layouts,
  thumbnails, page field, zoom, fit width, search, password unlock), audio/video (AVKit:
  playability check, speed, audio-track and subtitle menus, artwork, resources released on
  dismissal), text (bounded, safe decoding, wrap toggle, no link detection), Quick Look for rich
  documents, folder and fallback cards. Compact style in the preview pane, full style in
  Gallery. The pane hides its preview while Gallery shows the same file.
* Gallery keyboard handling moved to the filmstrip so viewer controls keep their keys.
* Testing hooks `LOCAL_EXPLORER_START_PATH` and `LOCAL_EXPLORER_STATE_FILE`; accessibility
  identifiers for UI tests.
* XcodeGen `project.yml` (app, package unit tests, UI tests), `make uitest`.
* README, privacy policy, formats list, distribution/permissions guide, this report.

## Known gaps and risks

* **App layer never compiled.** Expect a round of compiler fixes on first build, most likely
  around SwiftUI/AppKit API details and Swift concurrency annotations. Target: Xcode 16+.
* **No broader (multi-folder) search.** Search filters the current folder only; the optional
  recursive search with progress, cancellation and excluded directories is not implemented.
* **File grouping** (optional) is not implemented.
* **Thumbnail cache is in-memory only.** No on-disk cache, by design (privacy); cache
  metadata is therefore not persisted across launches.
* **Quick Look failure detection.** QLPreviewView gives no callback when a type has no
  generator; it shows a generic icon rather than our fallback card.
* **Image rotation is display-only.** Files are never modified.
* **PDF search** runs on the main actor. Fine for typical documents; very large PDFs may pause
  briefly.
* **Network-request instrumentation at runtime** relies on `sandbox-exec` (deprecated by Apple
  but still functional). There is no in-process URL protocol hook, because the app has no URL
  loading to hook.
* **Performance targets** (launch under 2 s, cached navigation under 200 ms, key response under
  100 ms) are unmeasured.

## Verification on a Mac (next steps)

1. `make test`, then `make test-offline`. Expect 109 tests with 0 failures; the 2 root-only skips should now run.
2. `make app`, then fix any compiler errors and record them here.
3. `make run`. Check every view mode, preview pane resize, tabs, context menus, drag-and-drop to
   Finder and back, conflict sheet, Trash + undo, permission error on a `chmod 000` folder,
   ejecting a USB drive while browsing it, light/dark appearance and all glass tints.
4. `brew install xcodegen` (one-time), then `make uitest`.
5. Fill in docs/FORMATS.md with a fixture folder (one file per format).
6. Record baselines with Instruments (Time Profiler, Allocations) on a 10,000-file folder:
   launch time, navigation time, memory, thumbnail throughput. Note the Mac model and macOS
   version.
