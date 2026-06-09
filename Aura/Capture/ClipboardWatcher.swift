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
    private var powerObserver: NSObjectProtocol?

    /// Poll faster on AC/normal power, slower in Low Power Mode to save battery.
    /// (Reading `changeCount` is cheap, but there's no reason to spin at 250ms
    /// when the user has asked the system to conserve power.)
    private var currentInterval: DispatchTimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? .milliseconds(600) : .milliseconds(250)
    }

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        scheduleTimer()
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleTimer() }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
            self.powerObserver = nil
        }
    }

    private func scheduleTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = currentInterval
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
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
