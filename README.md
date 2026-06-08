<div align="center">

# Aura

**Drop anything into your Mac's notch.**

A native macOS menu-bar app that turns the notch into a place to dump everything —
copied text, links, images, files — and browse it all later in a beautiful card grid.
100% local. No account, no cloud, no telemetry.

`macOS 14+` · `Swift` · `SwiftUI + AppKit` · `GRDB / SQLite` · `local-only`

</div>

---

## What it is

Aura lives in the MacBook notch (inspired by [Supaste](https://www.supaste.com)). It has two surfaces:

1. **The notch** — hover to expand a panel. **Drag-and-drop** files, images, or links onto it to save them. When you **copy** something, a small card *nudges* out of the notch — click it to keep, ignore it and it slips away. A strip of recently-saved items lives here for quick access.
2. **The library window** — everything you've saved, in a **bento / masonry** card grid: images show previews, links show host + icon, text shows snippets, colors show swatches, files show their type. Search and category tabs on top.

Everything is stored **on your device only**, in a local SQLite database.

## Features

- **Notch-resident UI** — a borderless panel that floats over every Space and fullscreen app, never steals focus, and merges visually with the physical notch.
- **Nudge-to-save clipboard capture** — nothing is saved unless you act on the nudge. Password-manager and transient clipboard content (`org.nspasteboard.ConcealedType` / `TransientType`) is ignored.
- **Drag-and-drop** — drop files, images, web links, or text straight onto the notch.
- **Bento library** — a column-balancing masonry grid with per-type cards and substring search.
- **Local-first & private** — SQLite + on-disk assets under Application Support; no network calls, no sandbox phone-home, nothing leaves the machine.
- **Vault-only retrieval** — click any item to copy it back to the clipboard, or drag it out. (No paste-injection, so no Accessibility permission needed.)
- **Smooth, flicker-free notch hover** — see [Design notes](#design-notes).

## How it works

```
                 ┌──────────────────────────────────────────────┐
   clipboard ───▶│ ClipboardWatcher ─┐                           │
   (poll 250ms)  │                   │                           │
                 │ drag & drop ──────┼─▶ CaptureCandidate        │
                 │ (DropReceiver)    │        │                  │
                 │                   │        ▼                  │
                 │            DataStore.save() ──▶ AssetStore     │
                 │                   │        │   (originals)    │
                 │                   │        ▼                  │
                 │                   │   GRDB / SQLite + FTS5     │
                 │                   │        │                  │
                 │          ValueObservation (reactive)          │
                 │                   │                           │
                 │       ┌───────────┴───────────┐               │
                 │       ▼                       ▼               │
                 │  Notch panel            Library window        │
                 │  (recent strip)         (bento grid)          │
                 └──────────────────────────────────────────────┘
```

A single `@Observable` **`DataStore`** wraps a GRDB `DatabasePool` and is shared by **both** surfaces, so a save in the notch shows up in the library window instantly (and vice-versa). Both clipboard-nudge "keep" and drag-drop funnel through one `save()` path.

### Design notes

**Flicker-free notch hover.** The hard part of a notch app is making hover-to-expand smooth. The trick (borrowed from [NotchDrop](https://github.com/Lakr233/NotchDrop)):

- The window is a **fixed-size, full-width strip** that **never resizes** — only the SwiftUI content animates inside it. (Resizing the window mid-hover is what causes the classic open/close flicker.)
- Hover is detected by a **global + local `.mouseMoved` monitor** reading `NSEvent.mouseLocation` — **no `NSTrackingArea`**, so there's nothing to rebuild during animation.
- **Asymmetric zones**: it opens when the cursor enters the small notch rect, and only closes when the cursor leaves the *large* expanded-panel rect. That asymmetry (+ a short open dwell and close debounce) is what makes it open instantly and *stay* open.
- Click-through everywhere except the visible panel is handled by a `hitTest` override, so the rest of the menu bar stays usable.

## Tech stack

| Concern | Choice |
|---|---|
| Language / UI | Swift, SwiftUI + AppKit (`NSPanel` + `NSHostingView` for the notch) |
| Storage | [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite) with FTS5 full-text search |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated from `project.yml` |
| Min OS | macOS 14.0 (Sonoma) — for `safeAreaInsets` / `auxiliaryTopLeftArea`, `@Observable`, `MenuBarExtra` |
| Sandbox | **None** (personal/local use — full clipboard, custom window levels, filesystem) |

## Project structure

```
Aura/
├── AuraApp.swift              # @main: MenuBarExtra + Library Window + Settings
├── Info.plist / Aura.entitlements
├── App/                       # AppDelegate, AppEnvironment (DI), MenuBarContent
├── Notch/                     # the notch panel
│   ├── NotchController        # window lifecycle + hover state machine
│   ├── NotchPanel             # borderless non-activating NSPanel
│   ├── NotchContainerView     # hitTest click-through
│   ├── NotchRootView          # SwiftUI content (collapsed / expanded / nudge)
│   ├── NotchGeometry          # fixed window frame + hover zones
│   ├── NudgeCardView / RecentStripView / NotchShape / NotchStateModel
├── Capture/                   # ClipboardWatcher, PasteboardReader, DropReceiver, CaptureCandidate
├── Storage/                   # AppDatabase (schema), DataStore, Item, Collection, AssetStore, ThumbnailService
├── Library/                   # LibraryWindowView, BentoGridView, MasonryColumnizer, CardView, Cards/*
└── Shared/                    # URLClassifier, ColorDetector, Color+Hex
project.yml                    # XcodeGen spec (GRDB dependency, signing, entitlements)
```

## Getting started

### Requirements

- macOS 14.0+ (built and tested on macOS 15, Xcode 26, Apple Silicon)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

### Build & run

```bash
git clone git@github.com:Deveshb15/aura.git
cd aura

# Generate the Xcode project from project.yml (run again after adding/removing files)
xcodegen generate

# Open in Xcode and press ⌘R
open Aura.xcodeproj

# …or build & launch from the command line
xcodebuild -project Aura.xcodeproj -scheme Aura -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Aura.app
```

Because `LSUIElement` is set, **no window opens on launch** — look for the **tray icon** in the menu bar and the panel in the **notch**. Hover the notch to expand it; open the library from the tray icon → **Open Library**.

> The generated `Aura.xcodeproj` is intentionally **git-ignored** — regenerate it with `xcodegen generate` after cloning.

## Data & privacy

Everything lives locally under:

```
~/Library/Application Support/Aura/
├── aura.sqlite          # item metadata, thumbnails, and the FTS5 search index
└── Assets/
    ├── img/             # original images
    └── file/            # saved files
```

No data ever leaves your machine. Aura makes no network requests, has no analytics, and is not sandboxed (so it can monitor the clipboard and position a window over the notch). Delete that folder to reset the app completely.

## Roadmap

- [x] **Phase 1** — notch capture (nudge + drag-drop) → SQLite → notch recent strip + bento library, for text/links/images
- [x] **Notch polish** — flicker-free hover, content positioned below the physical notch
- [ ] **Phase 3** — rich link previews (LinkPresentation + Open Graph meta images & favicons)
- [ ] **Phase 4** — YouTube thumbnails, Quick Look thumbnails for arbitrary files
- [ ] **Phase 5** — color-swatch cards, user collections
- [ ] **Phase 6** — FTS5 search bar, settings (capture toggle, launch-at-login)
- [ ] **Phase 7** — animation choreography, multi-display handling, battery-aware polling

## Development notes

- The project file is generated — **never edit `Aura.xcodeproj` by hand**; change `project.yml` and re-run `xcodegen generate`.
- GRDB is the only third-party dependency, added via Swift Package Manager inside `project.yml`.
- The app ad-hoc signs to run locally; there's no provisioning profile and App Sandbox is off by design.

## License

Personal project — © 2026 Devesh. All rights reserved.
