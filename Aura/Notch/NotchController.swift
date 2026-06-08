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

    private var geometry: NotchGeometry
    private var panel: NotchPanel?
    private var container: NotchContainerView?
    private var hostingView: NSHostingView<NotchRootView>?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var nudgeDismissTask: Task<Void, Never>?

    private let openDwell: TimeInterval = 0.10
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
            onKeepNudge: { [weak self] in self?.keepNudge() },
            onDragTargetedChange: { [weak self] targeted in
                guard let self else { return }
                if targeted { self.expand() } else { self.scheduleCollapse() }
            }
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
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    private func screensChanged() {
        geometry = NotchGeometry.current()
        panel?.setFrame(geometry.windowFrame, display: true)
        state.collapsedSize = geometry.collapsedSize
        let mode: NotchInteractiveMode = state.nudge != nil
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

        if state.nudge != nil {
            // While a nudge is up, hovering keeps it; leaving restarts dismissal.
            if geometry.nudgeRect.contains(location) {
                nudgeDismissTask?.cancel()
                nudgeDismissTask = nil
            } else if nudgeDismissTask == nil {
                scheduleNudgeDismiss()
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
        container?.interactiveRect = geometry.interactiveRect(for: .expanded)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            state.nudge = nil
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
        guard state.nudge == nil else { return }
        container?.interactiveRect = geometry.interactiveRect(for: .collapsed)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            state.mode = .collapsed
            state.isDropTargeted = false
        }
    }

    // MARK: - Nudge

    func showNudge(_ candidate: CaptureCandidate) {
        cancelExpand()
        cancelCollapse()
        let nudge = NudgeItem(candidate: candidate, preview: Self.preview(for: candidate))
        container?.interactiveRect = geometry.interactiveRect(for: .nudge)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            state.mode = .collapsed
            state.nudge = nudge
        }
        scheduleNudgeDismiss()
    }

    private func scheduleNudgeDismiss() {
        nudgeDismissTask?.cancel()
        nudgeDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.nudgeDismissTask = nil
            self.dismissNudge()
        }
    }

    func keepNudge() {
        guard let candidate = state.nudge?.candidate else { return }
        Task { await dataStore.save(candidate) }
        dismissNudge()
    }

    private func dismissNudge() {
        nudgeDismissTask?.cancel()
        nudgeDismissTask = nil
        container?.interactiveRect = geometry.interactiveRect(for: .collapsed)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
            state.nudge = nil
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
