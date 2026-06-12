# Aura — X bookmark sync extension

A small companion extension that saves your **X (Twitter) bookmarks** into your
local Aura library. It is **passive**: it never logs in for you and never calls
X's API — it only reads the bookmarks page's *own* responses while you browse,
exactly the way the page already loaded them, and forwards each bookmarked tweet
to the Aura desktop app over Chrome Native Messaging.

## What it does

- **Forward sync** — while you're on x.com, anything you bookmark is saved to
  Aura automatically (author, handle, avatar, text, and the first image / video
  poster). Your existing bookmarks are silently baselined the first time, so the
  library isn't flooded.
- **Instant capture** — clicking the bookmark button anywhere on X saves that
  tweet immediately, with an in-page "Saved to Aura" confirmation.
- **One-time history import** — *Settings → X bookmarks → Import my bookmarks*
  in Aura opens your bookmarks and pulls in up to **400** existing ones as it
  gently scrolls.

No background polling, no cookies, no request replay — capture only happens
while you're actually on x.com. Everything stays on your Mac.

## Install (Chrome / Brave / Edge / Arc / Chromium)

1. Open the extensions page (`chrome://extensions`, `brave://extensions`,
   `edge://extensions`, …).
2. Turn on **Developer mode** (top-right).
3. Click **Load unpacked** and choose this `extension` folder.
4. Launch **Aura** at least once — it installs the native-messaging host the
   extension talks to. (Install order doesn't matter; just open Aura once.)
5. Open **x.com** and bookmark something. You should see "Saved to Aura".

The extension's ID is pinned (`gmombdkcjjnlgcbfanhcfgabpjkajdbn`) via the `key`
in `manifest.json`, so Aura's native-messaging host can whitelist it even when
loaded unpacked.

## How it's wired

```
x.com page  ──fetch/XHR hook──►  content scripts  ──chrome.runtime──►  background.js
 (Bookmarks GraphQL)              (parse tweets)                        (native messaging)
                                                                              │
                                                  app.captureaura.xhost  ◄────┘
                                                  (aura-x-host helper, bundled in Aura.app)
                                                          │ loopback + token
                                                          ▼
                                                       Aura.app  → downloads media → saves Item
```

- `content/x-graphql-interceptor.js` (MAIN world) wraps `fetch`/`XMLHttpRequest`
  and extracts bookmarked tweets from `/graphql/…/Bookmarks` responses.
- `content/x-bookmark-watcher.js` (isolated world) relays batches, drives the
  capped bulk import (`?aura_import=1`), and captures bookmark clicks.
- `background.js` forwards each tweet to the desktop app and keeps the "seen"
  baseline so forward-sync never re-imports your back-catalog.

## Note on X's Terms

This reads *your own* bookmarks from *your own* session, locally — but it does
automate X's private web data, which is a gray area under X's Terms, and it can
break when X changes its site. It degrades quietly when that happens.
