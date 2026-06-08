# Aura

A native macOS app that lives in the **notch** and is a place to dump *anything* —
text, links, images, files. Copy something and a card **nudges** out of the notch;
click it to keep. Drag files/links/images onto the notch to save them. Everything
is stored **100% locally** on device (SQLite). Open the library window to browse
everything in a **bento / masonry** card grid.

Inspired by Supaste. Personal/local use — no App Sandbox, no cloud, no account.

## Status

**Phase 1 (thin end-to-end slice) — built & running.** ✅
- Menu-bar agent (no Dock icon), notch panel, clipboard nudge, drag-and-drop,
  SQLite storage with FTS5, and the bento library window for text / links / images.

Later phases (rich link previews, YouTube thumbnails, file Quick Look thumbnails,
color cards, collections, search UI, settings, animation polish) are planned in
`~/.claude/plans/i-want-to-build-deep-snail.md`.

## Requirements

- macOS 14.0+ (built/tested on macOS 15, Xcode 26, Apple Silicon)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the
  `.xcodeproj` is generated from `project.yml`.

## Build & run

```bash
# 1. Generate the Xcode project (only needed after editing project.yml or adding files)
xcodegen generate

# 2a. Open in Xcode and press ⌘R
open Aura.xcodeproj

# 2b. …or build & launch from the command line
xcodebuild -project Aura.xcodeproj -scheme Aura -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Aura.app
```

Because `LSUIElement` is set, no window opens on launch — look for the **tray icon
in the menu bar** and the panel in the **notch**. Open the library from the menu-bar
icon → "Open Library".

## How it works

- **Notch panel** — a borderless, non-activating `NSPanel` (`Notch/`) positioned over
  the notch via `NSScreen.safeAreaInsets` / `auxiliaryTop*Area`. Hover expands it;
  the window frame animates between collapsed / expanded / nudge sizes while SwiftUI
  springs the content. Falls back to a top-center pill on Macs without a notch.
- **Capture** (`Capture/`) — `ClipboardWatcher` polls `NSPasteboard.changeCount`
  (~250ms), skips password-manager / transient content, and shows a nudge. Drag-drop
  decodes `NSItemProvider`s. Both feed one `CaptureCandidate` → `DataStore.save()`.
- **Storage** (`Storage/`) — GRDB/SQLite. One `item` table for all types + an `item_fts`
  FTS5 mirror. Originals are copied to `~/Library/Application Support/Aura/Assets/`;
  a small thumbnail blob is stored inline for fast grid rendering. A single
  `@Observable DataStore` (GRDB `ValueObservation`) feeds **both** the notch and the
  library window.
- **Library** (`Library/`) — a column-balancing masonry grid (`MasonryColumnizer`)
  with per-type cards, category tabs, and substring search.

## Data location

```
~/Library/Application Support/Aura/
├── aura.sqlite          # metadata + thumbnails + FTS index
└── Assets/
    ├── img/             # original images
    └── file/            # saved files
```

Delete that folder to reset the app.
