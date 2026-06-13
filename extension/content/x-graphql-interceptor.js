// MAIN-world script — runs in the same JavaScript context as x.com's own
// code, so it can wrap `fetch` / `XMLHttpRequest` and read the response
// bodies of X's GraphQL calls. We NEVER forge a request: we only read copies
// of responses the page itself fetched, so every anti-bot header is genuine
// and the user's session does the work. Parsed tweets are handed to the
// isolated-world watcher via window.postMessage (the standard MAIN↔isolated
// bridge in an MV3 extension).
//
// This is a focused port of GatherOS's interceptor: bookmarks only, plus a
// per-tweet cache so an instant bookmark-click can attach the rich payload.

(function auraXInterceptor() {
  if (window.__AURA_X_INTERCEPTOR__) return;
  window.__AURA_X_INTERCEPTOR__ = true;

  const ORIGIN = window.location.origin;

  // ── Tweet parsing ──────────────────────────────────────────────────
  // X has been migrating user fields out of `legacy` into a `core` object
  // (and the avatar into a dedicated `avatar` object). Read both so this
  // keeps working during and after the rollout — without this, freshly
  // migrated accounts return null for every tweet.
  function parseTweet(result) {
    if (!result || typeof result !== 'object') return null;
    const t = result.tweet || result;            // visibility/quote wrappers nest one deeper
    const legacy = t.legacy;
    if (!legacy || !legacy.id_str) return null;

    const userResult = t.core && t.core.user_results && t.core.user_results.result;
    if (!userResult) return null;
    const userCore = userResult.core || {};
    const userLegacy = userResult.legacy || {};
    const screenName = userCore.screen_name || userLegacy.screen_name;
    if (!screenName) return null;
    const displayName = userCore.name || userLegacy.name || '';
    const avatarUrl =
      (userResult.avatar && userResult.avatar.image_url) ||
      userLegacy.profile_image_url_https || '';

    const tweetId = legacy.id_str;
    const tweetUrl = `https://x.com/${screenName}/status/${tweetId}`;

    // extended_entities.media is authoritative (entities.media truncates).
    const mediaList =
      (legacy.extended_entities && legacy.extended_entities.media) ||
      (legacy.entities && legacy.entities.media) || [];
    const imageUrls = [];
    let videoUrl = null;
    let posterUrl = '';
    for (const m of mediaList) {
      if (!m) continue;
      if (m.type === 'photo' && m.media_url_https) {
        imageUrls.push(`${m.media_url_https}?format=jpg&name=large`);
      } else if ((m.type === 'video' || m.type === 'animated_gif') &&
                 m.video_info && Array.isArray(m.video_info.variants)) {
        let best = null;
        for (const v of m.video_info.variants) {
          if (!v || v.content_type !== 'video/mp4' || !v.url) continue;
          const br = typeof v.bitrate === 'number' ? v.bitrate : 0;
          if (!best || br > best.bitrate) best = { url: v.url, bitrate: br };
        }
        if (best && !videoUrl) { videoUrl = best.url; posterUrl = m.media_url_https || ''; }
      }
    }

    // Nothing to save only when there's no media AND no text.
    const caption = legacy.full_text || '';
    if (imageUrls.length === 0 && !videoUrl && !caption.trim()) return null;

    let quoted = null;
    const qr = t.quoted_status_result && t.quoted_status_result.result;
    if (qr) {
      const q = parseTweet(qr);
      if (q) quoted = { authorName: q.authorName, authorHandle: q.authorHandle, caption: q.caption };
    }

    return {
      tweetId, tweetUrl,
      authorName: displayName,
      authorHandle: `@${screenName}`,
      authorAvatarUrl: avatarUrl,
      caption,
      imageUrls,
      videoUrl,
      posterUrl,
      quoted,
    };
  }

  // Walk a Bookmarks GraphQL response → flat array of parsed tweets.
  // The feed lives at data.bookmark_timeline_v2.timeline.instructions[].
  // entries[]; tweet entries have entryId "tweet-…" and the payload at
  // content.itemContent.tweet_results.result.
  function extractBookmarkEntries(json) {
    const out = [];
    (function walk(node) {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) { for (const c of node) walk(c); return; }
      if (typeof node.entryId === 'string' && node.entryId.startsWith('tweet-')) {
        const wrapped = node.content && node.content.itemContent &&
          node.content.itemContent.tweet_results &&
          node.content.itemContent.tweet_results.result;
        if (wrapped) { const p = parseTweet(wrapped); if (p) out.push(p); }
      }
      for (const k of Object.keys(node)) { if (k !== '__typename') walk(node[k]); }
    })(json);
    return out;
  }

  // Cache every tweet we parse anywhere (timeline, detail, bookmarks) by id,
  // so an instant bookmark-click in the isolated world can attach the rich
  // payload instead of scraping the DOM.
  function cacheAllTweets(json) {
    const found = [];
    (function walk(node) {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) { for (const c of node) walk(c); return; }
      if (node.legacy && node.legacy.id_str && node.core && node.core.user_results) {
        const p = parseTweet(node); if (p) found.push(p);
      }
      for (const k of Object.keys(node)) { if (k !== '__typename') walk(node[k]); }
    })(json);
    if (found.length) {
      window.postMessage({ source: 'aura-x', type: 'tweet-cache', tweets: found }, ORIGIN);
    }
  }

  function isBookmarksEndpoint(url) {
    return typeof url === 'string' && /\/graphql\/[^/]+\/Bookmarks/.test(url);
  }

  // True for the "top of the list" request (no pagination cursor). New
  // bookmarks always land at the top, so forward-sync only trusts this page;
  // paginated pages are tagged so the bulk-import session can opt in.
  function isTopOfList(url) {
    try {
      const vars = new URL(url).searchParams.get('variables');
      if (!vars) return true;
      const decoded = JSON.parse(vars);
      return !decoded || !decoded.cursor;
    } catch { return false; }
  }

  function handleResponse(url, json) {
    cacheAllTweets(json);
    if (isBookmarksEndpoint(url)) {
      const tweets = extractBookmarkEntries(json);
      console.debug('[aura] Bookmarks response —', tweets.length, 'tweets, top:', isTopOfList(url));
      if (tweets.length) {
        window.postMessage(
          { source: 'aura-x', type: 'bookmarks', tweets, top: isTopOfList(url) },
          ORIGIN,
        );
      }
    }
  }

  function shouldIntercept(url) {
    return typeof url === 'string' && (url.includes('/graphql/') || url.includes('/i/api/'));
  }

  // Wrap fetch — read from a clone so the page's own consumer is untouched.
  const ORIGINAL_FETCH = window.fetch;
  window.fetch = function auraFetch(...args) {
    const reqUrl = (typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url) || '';
    const p = ORIGINAL_FETCH.apply(this, args);
    if (!shouldIntercept(reqUrl)) return p;
    p.then((res) => {
      if (!res || !res.ok) return;
      res.clone().json().then((json) => handleResponse(reqUrl, json)).catch(() => {});
    }).catch(() => {});
    return p;
  };

  // Wrap XHR — a few X code paths still use it.
  const XHR_OPEN = XMLHttpRequest.prototype.open;
  const XHR_SEND = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function auraXhrOpen(method, url, ...rest) {
    this.__auraUrl = url;
    return XHR_OPEN.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function auraXhrSend(...args) {
    this.addEventListener('load', () => {
      if (!shouldIntercept(this.__auraUrl)) return;
      try { handleResponse(this.__auraUrl, JSON.parse(this.responseText)); } catch {}
    });
    return XHR_SEND.apply(this, args);
  };
})();
