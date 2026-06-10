import AppKit
import SwiftUI

/// Owns the notch panel. The window is FIXED size and never moves; hover is
/// detected by a global+local mouse-location monitor (no tracking areas), and
/// only the SwiftUI content animates. This is the flicker-free pattern from
/// NotchDrop: open when the cursor is in the small `notchRect`, close when it
/// leaves the large `openedRect` (asymmetric hysteresis) with a short debounce.
@MainActor
final class NotchController {
    let state: NotchStateModel
    private let dataStore: DataStore

    /// Called when the user clicks the notch / "Aura" header to open the library.
    var onOpenLibrary: (() -> Void)?

    private var geometry: NotchGeometry
    private var panel: NotchPanel?
    private var container: NotchContainerView?
    private var hostingView: NSHostingView<NotchRootView>?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var pendingExpiryTask: Task<Void, Never>?
    private var screensChangedWork: DispatchWorkItem?

    private let openDwell: TimeInterval = 0.12
    private let closeDelay: TimeInterval = 0.20

    init(state: NotchStateModel, dataStore: DataStore) {
        self.state = state
        self.dataStore = dataStore
        self.geometry = NotchGeometry.current()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func show() {
        let frame = geometry.windowFrame
        let panel = NotchPanel(contentRect: frame)
        let container = NotchContainerView(frame: NSRect(origin: .zero, size: frame.size))
        container.interactiveRect = geometry.interactiveRect(for: .collapsed)

        state.collapsedSize = geometry.collapsedSize

        let root = NotchRootView(
            state: state,
            dataStore: dataStore,
            onKeepPending: { [weak self] in self?.keepPending() },
            onDismissPending: { [weak self] in self?.dismissPending() },
            onDragTargetedChange: { [weak self] targeted in
                guard let self else { return }
                if targeted { self.expand() } else { self.scheduleCollapse() }
            },
            onOpenLibrary: { [weak self] in self?.onOpenLibrary?() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        container.addSubview(hosting)

        panel.contentView = container
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.container = container
        self.hostingView = hosting

        installMouseMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScreensChanged() }
        }
    }

    /// Display reconfiguration (plug/unplug, lid open/close, resolution change)
    /// can fire several notifications in a burst — debounce, then relocate.
    private func scheduleScreensChanged() {
        screensChangedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.screensChanged() }
        screensChangedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func screensChanged() {
        geometry = NotchGeometry.current()
        // Move the panel onto the (possibly new) notched/main screen and ensure
        // it's still on top after relocating. Falls back to the top-center pill
        // when no notched screen is present (e.g. clamshell on an external).
        panel?.setFrame(geometry.windowFrame, display: true)
        panel?.orderFrontRegardless()
        state.collapsedSize = geometry.collapsedSize
        let mode: NotchInteractiveMode = state.pending != nil
            ? .nudge
            : (state.mode == .expanded ? .expanded : .collapsed)
        container?.interactiveRect = geometry.interactiveRect(for: mode)
    }

    // MARK: - Mouse monitoring (hover detection)

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
            return event
        }
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation
        // While a keep card is up, hovering it pauses the auto-dismiss; leaving
        // restarts the countdown. No hover-to-expand until the card is gone.
        if state.pending != nil {
            if geometry.nudgeRect.contains(location) {
                pendingExpiryTask?.cancel()
                pendingExpiryTask = nil
            } else if pendingExpiryTask == nil {
                schedulePendingExpiry()
            }
            return
        }
        switch state.mode {
        case .collapsed:
            if geometry.notchRect.contains(location) {
                scheduleExpand()
            } else {
                cancelExpand()
            }
        case .expanded:
            if geometry.openedRect.contains(location) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
        }
    }

    // MARK: - Expand / collapse

    private func scheduleExpand() {
        guard expandWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWorkItem = nil
            // Re-check the cursor is still in the notch after the dwell.
            if self.geometry.notchRect.contains(NSEvent.mouseLocation) {
                self.expand()
            }
        }
        expandWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + openDwell, execute: work)
    }

    private func cancelExpand() {
        expandWorkItem?.cancel()
        expandWorkItem = nil
    }

    func expand() {
        cancelExpand()
        cancelCollapse()
        guard state.mode != .expanded else { return }
        // Opening the recents supersedes a pending card (without keeping it).
        pendingExpiryTask?.cancel()
        pendingExpiryTask = nil
        container?.interactiveRect = geometry.interactiveRect(for: .expanded)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            state.pending = nil
            state.mode = .expanded
        }
    }

    func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            if !self.geometry.openedRect.contains(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
    }

    private func cancelCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func collapse() {
        // Don't collapse out from under a pending keep card.
        guard state.pending == nil else { return }
        container?.interactiveRect = geometry.interactiveRect(for: .collapsed)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            state.mode = .collapsed
            state.isDropTargeted = false
        }
    }

    // MARK: - Copy → bounce + pending keep

    /// A new clipboard capture: slide a "keep this?" card down from the notch
    /// automatically and arm it for a few seconds. Keep it, dismiss it, or just
    /// ignore it (it retracts on its own). Hovering the card pauses the timer.
    func handleCopy(_ candidate: CaptureCandidate) {
        cancelExpand()
        cancelCollapse()
        let nudge = NudgeItem(candidate: candidate, preview: Self.preview(for: candidate))
        container?.interactiveRect = geometry.interactiveRect(for: .nudge)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        withAnimation(.spring(response: 0.36, dampingFraction: 1.0)) {
            state.mode = .collapsed
            state.pending = nudge
        }
        schedulePendingExpiry()
    }

    private func schedulePendingExpiry() {
        pendingExpiryTask?.cancel()
        pendingExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingExpiryTask = nil
            self.dismissPending()
        }
    }

    func keepPending() {
        guard let candidate = state.pending?.candidate else { return }
        Task { await dataStore.save(candidate) }
        dismissPending()
    }

    func dismissPending() {
        pendingExpiryTask?.cancel()
        pendingExpiryTask = nil
        container?.interactiveRect = geometry.interactiveRect(for: .collapsed)
        withAnimation(.spring(response: 0.32, dampingFraction: 1.0)) {
            state.pending = nil
            state.mode = .collapsed
        }
    }

    // MARK: - Helpers

    private static func preview(for candidate: CaptureCandidate) -> NudgePreview {
        switch candidate.payload {
        case .text(let value): return .text(value)
        case .url(let url): return .url(url.absoluteString)
        case .image(let data): return .image(NSImage(data: data) ?? NSImage())
        case .file(let url): return .file(url.lastPathComponent)
        case .color(let hex): return .color(hex)
        }
    }
}
