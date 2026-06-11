import Foundation
import WebKit
import os

/// Renders a page in an offscreen WKWebView so JS-built sites (Notion, SPAs,
/// client-rendered blogs) produce real DOM text for the search index. Heavy —
/// it spawns WebKit helper processes — so it is only a fallback, used when the
/// plain HTTP fetch yields no readable article (see
/// `LinkMetadataService.fetchArticleText`). Renders are serialized so at most
/// one WebKit process tree is alive at a time (backfills enrich in a loop).
actor WebPageRenderer {
    static let shared = WebPageRenderer()

    private var previous: Task<Void, Never>?

    /// Loads the page offscreen, waits for it to finish + a short JS settle
    /// delay, and returns the live DOM's HTML — or nil if nothing rendered.
    func renderHTML(url: URL) async -> String? {
        // Chain onto the previous render (actor reentrancy would otherwise let
        // several WKWebViews spin up concurrently during a backfill).
        let prior = previous
        let task = Task<String?, Never> {
            await prior?.value
            return await OffscreenPageLoader().load(url: url)
        }
        previous = Task { _ = await task.value }
        return await task.value
    }
}

/// One-shot offscreen loader: navigates, waits for `didFinish` plus a settle
/// delay (SPAs paint after the load event), then snapshots the live DOM.
/// WebKit is main-thread-only, hence @MainActor.
@MainActor
private final class OffscreenPageLoader: NSObject, WKNavigationDelegate {
    private static let log = Logger(subsystem: "app.captureaura", category: "render")
    /// Match Safari so sites serve the normal page (same UA as the static fetch).
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Extra time after `didFinish` for client-side rendering to paint.
    private let settleSeconds: Double = 2.0
    /// Hard deadline — snapshot whatever has rendered by then.
    private let timeoutSeconds: Double = 15

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var settleTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func load(url: URL) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            continuation = cont

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()   // no cookies/cache on disk
            config.suppressesIncrementalRendering = true
            config.mediaTypesRequiringUserActionForPlayback = .all

            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900),
                                    configuration: config)
            webView.navigationDelegate = self
            webView.customUserAgent = Self.userAgent
            self.webView = webView
            webView.load(URLRequest(url: url))

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.timeoutSeconds ?? 15) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.snapshotAndFinish()
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.settleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.settleSeconds ?? 2) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.snapshotAndFinish()
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.snapshotAndFinish() }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        // Nothing loaded at all (DNS/connection/blocked) — finish; the blank
        // document yields no text and the extractor's guard rejects it.
        Task { @MainActor [weak self] in self?.snapshotAndFinish() }
    }

    /// Grabs the live DOM and resumes the continuation — exactly once.
    private func snapshotAndFinish() {
        guard let cont = continuation else { return }
        continuation = nil
        settleTask?.cancel()
        timeoutTask?.cancel()
        guard let webView else { cont.resume(returning: nil); return }
        self.webView = nil
        webView.stopLoading()
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [webView] result, _ in
            _ = webView   // keep the web view alive until the JS callback lands
            cont.resume(returning: result as? String)
        }
    }
}
