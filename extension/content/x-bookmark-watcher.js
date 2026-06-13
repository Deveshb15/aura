// Isolated-world content script. Receives parsed tweets from the MAIN-world
// interceptor (via window.postMessage), relays them to the background service
// worker, drives the one-time bulk import, and captures instant bookmark
// clicks. Passive by design: it never fetches from X itself — it only reacts
// to data the page already loaded (plus user-driven auto-scroll during an
// explicit import).

const BULK_CAP = 400;            // hard ceiling on a one-time history import
const BOOKMARK_TESTID = 'bookmark';

// id -> parsed tweet, fed by the interceptor's tweet-cache messages.
const tweetCache = new Map();

// Bulk-import session state (only active when the user explicitly imports).
let bulk = null; // { tweets: Map<id, tweet>, lastGrowthAt, timer, done }

// ── MAIN→isolated bridge ─────────────────────────────────────────────
window.addEventListener('message', (event) => {
  if (event.source !== window) return;
  const d = event.data;
  if (!d || d.source !== 'aura-x') return;

  if (d.type === 'tweet-cache' && Array.isArray(d.tweets)) {
    for (const t of d.tweets) if (t && t.tweetId) tweetCache.set(t.tweetId, t);
    return;
  }

  if (d.type === 'bookmarks' && Array.isArray(d.tweets)) {
    for (const t of d.tweets) if (t && t.tweetId) tweetCache.set(t.tweetId, t);
    if (bulk && !bulk.done) {
      // Bulk session: ingest every page (top + paginated) up to the cap.
      let grew = false;
      for (const t of d.tweets) {
        if (bulk.tweets.size >= BULK_CAP) break;
        if (t && t.tweetId && !bulk.tweets.has(t.tweetId)) { bulk.tweets.set(t.tweetId, t); grew = true; }
      }
      if (grew) { bulk.lastGrowthAt = Date.now(); updateBulkControl(bulk.tweets.size); }
      if (bulk.tweets.size >= BULK_CAP) finishBulk();
    } else if (d.top) {
      // Forward-sync: only the top-of-list page is trusted, so deep manual
      // scrolling never floods. The background owns the silent baseline.
      chrome.runtime.sendMessage({ type: 'aura:tweets', mode: 'forward', tweets: d.tweets });
    }
  }
});

// ── One-time bulk import (triggered by Aura opening /i/bookmarks?aura_import=1) ──
function maybeStartBulk() {
  try {
    const u = new URL(location.href);
    if (!/\/i\/bookmarks/.test(u.pathname)) return;
    if (u.searchParams.get('aura_import') !== '1') return;
    // Strip the trigger so a refresh doesn't re-run it.
    u.searchParams.delete('aura_import');
    history.replaceState(null, '', u.toString());
    startBulk();
  } catch {}
}

function startBulk() {
  if (bulk) return;
  bulk = { tweets: new Map(), lastGrowthAt: Date.now(), startedAt: Date.now(), done: false, timer: null };
  // Interactive control: live count + a Stop button (and Esc) so the user can
  // stop whenever they have enough — the scroll is newest-first, so stopping
  // early keeps the most-recent bookmarks.
  showBulkControl();
  // Gentle auto-scroll so X's own client paginates; the interceptor harvests
  // each page. ~1.6s cadence keeps it human-ish and under rate limits.
  bulk.timer = setInterval(() => {
    if (!bulk || bulk.done) return;
    window.scrollTo(0, document.documentElement.scrollHeight);
    const idleMs = Date.now() - bulk.lastGrowthAt;
    const ranMs = Date.now() - bulk.startedAt;
    // Stop when no new bookmarks for ~8s (reached the end) or after 2 min.
    if (idleMs > 8000 || ranMs > 120000) finishBulk();
  }, 1600);
}

function finishBulk() {
  if (!bulk || bulk.done) return;
  bulk.done = true;
  if (bulk.timer) clearInterval(bulk.timer);
  hideBulkControl();
  // The bookmarks feed is newest-first; send oldest-first so the most
  // recently bookmarked tweet is inserted last and lands on top in Aura.
  const tweets = Array.from(bulk.tweets.values()).reverse();
  const count = tweets.length;
  bulk = null;
  console.debug('[aura] bulk finished — harvested', count);
  if (count === 0) {
    showToast('No bookmarks found to import.', { tone: 'error' });
    return;
  }
  chrome.runtime.sendMessage({ type: 'aura:tweets', mode: 'bulk', tweets }, (resp) => {
    if (!resp) { showToast('Import failed — is Aura running?', { tone: 'error' }); return; }
    if (resp.offline) { showToast('Open Aura first, then import again.', { tone: 'error' }); return; }
    const imp = resp.imported || 0, dup = resp.duplicates || 0, fail = resp.failed || 0;
    let msg;
    if (imp > 0) {
      msg = `Imported ${imp} bookmark${imp === 1 ? '' : 's'} to Aura`;
      if (dup > 0) msg += ` · ${dup} already saved`;
    } else if (dup > 0) {
      msg = `All ${dup} already in Aura`;
    } else {
      msg = fail > 0 ? `Couldn't save ${fail} bookmark${fail === 1 ? '' : 's'}` : 'Nothing imported';
    }
    showToast(msg, { tone: (imp === 0 && fail > 0) ? 'error' : 'ok' });
  });
}

// ── Bulk-import control: live count + Stop button (and Esc) ──────────
let bulkControlEl = null;
let bulkEscHandler = null;
function showBulkControl() {
  if (bulkControlEl) return;
  const el = document.createElement('div');
  el.style.cssText = [
    'position:fixed', 'right:24px', 'bottom:24px', 'z-index:2147483647',
    'display:flex', 'align-items:center', 'gap:12px', 'padding:9px 9px 9px 16px',
    'font:500 13px/1.2 -apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif',
    'color:rgba(255,255,255,0.96)', 'background:rgba(20,20,22,0.88)',
    'backdrop-filter:blur(20px) saturate(1.6)', '-webkit-backdrop-filter:blur(20px) saturate(1.6)',
    'border:0.5px solid rgba(255,255,255,0.14)', 'border-radius:999px',
    'box-shadow:0 1px 2px rgba(0,0,0,0.2),0 8px 22px rgba(0,0,0,0.28)',
  ].join(';');
  const label = document.createElement('span');
  label.className = 'aura-bulk-label';
  label.textContent = 'Gathering bookmarks… 0';
  const btn = document.createElement('button');
  btn.textContent = 'Stop & import';
  btn.style.cssText = [
    'all:unset', 'cursor:pointer', 'box-sizing:border-box', 'white-space:nowrap',
    'font:600 12.5px/1 -apple-system,BlinkMacSystemFont,sans-serif',
    'color:#0b0b0d', 'background:#ffffff', 'padding:8px 13px', 'border-radius:999px',
  ].join(';');
  btn.addEventListener('click', (e) => { e.preventDefault(); finishBulk(); });
  el.appendChild(label);
  el.appendChild(btn);
  document.body.appendChild(el);
  bulkControlEl = el;
  bulkEscHandler = (e) => { if (e.key === 'Escape') { e.preventDefault(); finishBulk(); } };
  window.addEventListener('keydown', bulkEscHandler, true);
}
function updateBulkControl(count) {
  const label = bulkControlEl && bulkControlEl.querySelector('.aura-bulk-label');
  if (label) label.textContent = `Gathering bookmarks… ${count}`;
}
function hideBulkControl() {
  if (bulkEscHandler) { window.removeEventListener('keydown', bulkEscHandler, true); bulkEscHandler = null; }
  if (bulkControlEl) { bulkControlEl.remove(); bulkControlEl = null; }
}

// ── Instant bookmark-click capture (works anywhere on x.com) ─────────
document.addEventListener('click', (e) => {
  const button = findBookmarkButton(e.target);
  if (!button) return;
  const label = (button.getAttribute('aria-label') || '').toLowerCase();
  if (label.includes('remove')) return;            // ignore un-bookmark

  const article = findArticle(button);
  if (!article) return;
  const tweetUrl = findTweetUrl(article);
  if (!tweetUrl) return;
  const tweetId = (tweetUrl.match(/\/status\/(\d+)/) || [])[1];

  // Prefer the interceptor's rich payload; fall back to a DOM scrape.
  const tweet = (tweetId && tweetCache.get(tweetId)) || scrapeArticle(article, tweetUrl, tweetId);
  if (!tweet) return;

  chrome.runtime.sendMessage({ type: 'aura:tweets', mode: 'click', tweets: [tweet] }, (resp) => {
    if (!resp) return;
    if (resp.offline) return;                       // app closed — stay quiet
    if (resp.ok) showToast(resp.duplicate ? 'Already in Aura' : 'Saved to Aura');
    else showToast(`Aura save failed: ${resp.error || 'unknown error'}`, { tone: 'error' });
  });
}, true);

function findBookmarkButton(target) {
  let el = target;
  while (el && el !== document.body) {
    if (el.getAttribute && el.getAttribute('data-testid') === BOOKMARK_TESTID) return el;
    el = el.parentElement;
  }
  return null;
}
function findArticle(el) {
  while (el && el !== document.body) { if (el.tagName === 'ARTICLE') return el; el = el.parentElement; }
  return null;
}
function findTweetUrl(article) {
  for (const link of article.querySelectorAll('a[href*="/status/"]')) {
    const m = (link.getAttribute('href') || '').match(/^(\/[^/]+\/status\/\d+)(?:[/?#]|$)/);
    if (m) return new URL(m[1], 'https://x.com').href;
  }
  return null;
}
// Minimal DOM fallback when the tweet isn't in the interceptor cache yet.
function scrapeArticle(article, tweetUrl, tweetId) {
  const nameEl = article.querySelector('[data-testid="User-Name"]');
  const lines = nameEl ? nameEl.innerText.split('\n').map((l) => l.trim()).filter(Boolean) : [];
  const authorName = lines[0] || '';
  const authorHandle = lines.find((l) => l.startsWith('@')) || '';
  const avatarImg = article.querySelector('[data-testid="Tweet-User-Avatar"] img');
  const captionEl = article.querySelector('[data-testid="tweetText"]');
  const caption = captionEl ? captionEl.innerText.trim() : '';
  const imageUrls = [];
  article.querySelectorAll('img').forEach((img) => {
    const src = img.currentSrc || img.getAttribute('src') || '';
    if (/pbs\.twimg\.com\/(media|tweet_video_thumb|ext_tw_video_thumb|amplify_video_thumb)\//.test(src)) {
      imageUrls.push(src);
    }
  });
  if (!caption && imageUrls.length === 0) return null;
  return {
    tweetId: tweetId || null,
    tweetUrl,
    authorName,
    authorHandle,
    authorAvatarUrl: avatarImg ? (avatarImg.getAttribute('src') || '') : '',
    caption,
    imageUrls,
    videoUrl: null,
    posterUrl: '',
    quoted: null,
  };
}

// ── In-page toast (own DOM node + inline styles so x.com's CSS can't bleed) ──
let toastEl = null, toastTimer = null;
function showToast(message, { tone = 'ok', sticky = false } = {}) {
  if (!toastEl) {
    toastEl = document.createElement('div');
    toastEl.style.cssText = [
      'position:fixed', 'right:24px', 'bottom:24px', 'z-index:2147483647',
      'display:flex', 'align-items:center', 'gap:8px', 'padding:10px 14px',
      'font:500 13px/1.2 -apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif',
      'color:rgba(255,255,255,0.96)', 'background:rgba(20,20,22,0.82)',
      'backdrop-filter:blur(20px) saturate(1.6)', '-webkit-backdrop-filter:blur(20px) saturate(1.6)',
      'border:0.5px solid rgba(255,255,255,0.14)', 'border-radius:999px',
      'box-shadow:0 1px 2px rgba(0,0,0,0.2),0 8px 22px rgba(0,0,0,0.28)',
      'opacity:0', 'transform:translateY(8px)', 'transition:opacity .16s ease,transform .16s ease',
      'pointer-events:none',
    ].join(';');
    document.body.appendChild(toastEl);
  }
  const dot = tone === 'error' ? 'rgba(255,90,90,0.95)' : 'rgba(110,220,140,0.95)';
  toastEl.innerHTML = `<span style="width:6px;height:6px;border-radius:50%;background:${dot};display:inline-block"></span><span></span>`;
  toastEl.querySelector('span:last-child').textContent = message;
  requestAnimationFrame(() => { toastEl.style.opacity = '1'; toastEl.style.transform = 'translateY(0)'; });
  if (toastTimer) clearTimeout(toastTimer);
  if (!sticky) {
    toastTimer = setTimeout(() => {
      if (!toastEl) return;
      toastEl.style.opacity = '0'; toastEl.style.transform = 'translateY(8px)';
    }, 2400);
  }
}

maybeStartBulk();
