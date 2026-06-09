import AppKit

/// Polls `NSPasteboard.changeCount` (there is no native change notification) and
/// emits a `CaptureCandidate` when the clipboard changes — unless the change was
/// caused by our own copy-back.
@MainActor
final class ClipboardWatcher {
    var onCandidate: ((CaptureCandidate) -> Void)?

    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?
    private let interval: DispatchTimeInterval = .milliseconds(250)

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Tell the watcher to ignore a specific change count (used when we write to
    /// the pasteboard ourselves during copy-back).
    func ignore(changeCount: Int) {
        ignoredChangeCount = changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if changeCount == ignoredChangeCount {
            ignoredChangeCount = nil
            return
        }

        // Respect the "watch clipboard" setting (we still advanced lastChangeCount
        // above, so re-enabling won't nudge a stale copy).
        guard UserDefaults.standard.object(forKey: "captureEnabled") as? Bool ?? true else { return }

        guard let candidate = PasteboardReader.read(pasteboard) else { return }
        onCandidate?(candidate)
    }
}
