// Service worker: the only context that can talk to Aura's native-messaging
// host. It receives parsed tweets from the content scripts and forwards each
// as a {type:'save'} message to the desktop app. No polling, no cookies, no
// request replay — capture happens only while the user is on x.com.
//
// Talks to the app via Chrome Native Messaging (host name app.captureaura.xhost);
// Aura installs the host manifest into the browser on launch, so install order
// doesn't matter. Media is sent as URLs (tiny payloads) and the app downloads
// the bytes itself.

const HOST = 'app.captureaura.xhost';

// "seen" baseline so forward-sync doesn't flood the library with the user's
// existing archive: the first bookmarks page we ever see is recorded silently;
// only bookmarks made from then on import automatically. The one-time bulk
// import bypasses this (it WANTS the history, capped client-side at 400).
const SEEN_KEY = 'auraXSeen';
const BASELINE_KEY = 'auraXBaseline';
const SEEN_CAP = 8000; // keep storage bounded

async function readSeen() {
  const d = await chrome.storage.local.get([SEEN_KEY, BASELINE_KEY]);
  return {
    seen: new Set(Array.isArray(d[SEEN_KEY]) ? d[SEEN_KEY] : []),
    baseline: !!d[BASELINE_KEY],
  };
}

async function writeSeen(seen, baseline) {
  const arr = Array.from(seen);
  const update = { [SEEN_KEY]: arr.slice(Math.max(0, arr.length - SEEN_CAP)) };
  if (baseline !== undefined) update[BASELINE_KEY] = !!baseline;
  await chrome.storage.local.set(update);
}

// One save → one native message → {ok, duplicate} (or offline on host error).
async function saveTweet(tweet) {
  try {
    const r = await chrome.runtime.sendNativeMessage(HOST, { type: 'save', tweet });
    return { ok: !!(r && r.ok), duplicate: !!(r && r.duplicate) };
  } catch (err) {
    const msg = (err && err.message) ? err.message : String(err);
    const offline =
      msg.includes('host not found') ||
      msg.includes('Specified native messaging host not found') ||
      msg.includes('Native host has exited') ||
      msg.includes('Access to the specified native messaging host is forbidden') ||
      msg.includes('not found');
    return { ok: false, offline, error: msg };
  }
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (!msg || msg.type !== 'aura:tweets') return undefined;
  handleTweets(msg.mode, Array.isArray(msg.tweets) ? msg.tweets : []).then(sendResponse);
  return true; // async sendResponse
});

async function handleTweets(mode, tweets) {
  if (!tweets.length) return { ok: true, imported: 0, duplicates: 0, failed: 0 };
  const { seen, baseline } = await readSeen();

  // Forward-sync, first ever batch: silently baseline the existing archive so
  // passive sync doesn't flood the library with the back-catalogue.
  if (mode === 'forward' && !baseline) {
    for (const t of tweets) if (t && t.tweetId) seen.add(t.tweetId);
    await writeSeen(seen, true);
    return { ok: true, imported: 0, duplicates: 0, failed: 0, baseline: true };
  }

  // Only FORWARD consults `seen` (so passive sync doesn't re-import the same
  // page on every visit). bulk + click send everything and let the APP dedup
  // by tweet id — the Aura vault is the source of truth, not this extension's
  // separate memory. (Consulting `seen` here is what starved bulk import.)
  const toImport = (mode === 'forward')
    ? tweets.filter((t) => t && t.tweetId && !seen.has(t.tweetId))
    : tweets.filter((t) => t && t.tweetUrl);

  if (toImport.length === 0) {
    return { ok: true, imported: 0, duplicates: 0, failed: 0, duplicate: mode === 'click' };
  }

  // First save doubles as the reachability probe so callers can report
  // "open Aura first" immediately instead of after a long loop.
  const first = await saveTweet(toImport[0]);
  if (first.offline) return { ok: false, offline: true };

  let imported = 0, duplicates = 0, failed = 0;
  const tally = (r, t) => {
    if (r.ok && r.duplicate) duplicates += 1;
    else if (r.ok) imported += 1;
    else failed += 1;
    // Record in `seen` ONLY on a confirmed result (success or already-saved),
    // never on failure — so a transient failure can't hide a tweet forever.
    if (r.ok && t && t.tweetId) seen.add(t.tweetId);
  };
  tally(first, toImport[0]);

  for (let i = 1; i < toImport.length; i++) {
    const r = await saveTweet(toImport[i]);
    if (r.offline) { failed += (toImport.length - i); break; }
    tally(r, toImport[i]);
  }

  await writeSeen(seen, true);
  console.debug('[aura] import', mode, { sent: toImport.length, imported, duplicates, failed });
  const ok = (mode === 'click') ? (imported + duplicates > 0) : true;
  return {
    ok, imported, duplicates, failed,
    duplicate: mode === 'click' ? (duplicates > 0) : undefined,
    error: failed > 0 ? 'save failed' : undefined,
  };
}
