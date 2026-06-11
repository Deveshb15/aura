import AppKit
import Carbon.HIToolbox
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
    private var composeKeyMonitor: Any?
    private var composeClickMonitor: Any?
    private var composeCollapseWork: DispatchWorkItem?
    /// The app that was frontmost when compose opened, so focus can be returned.
    private var previousApp: NSRunningApplication?

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
        if let composeKeyMonitor { NSEvent.removeMonitor(composeKeyMonitor) }
        if let composeClickMonitor { NSEvent.removeMonitor(composeClickMonitor) }
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
            onOpenLibrary: { [weak self] in self?.onOpenLibrary?() },
            onSaveCompose: { [weak self] text in self?.saveCompose(text: text) },
            onAddNote: { [weak self] in self?.enterCompose() }
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
        let mode: NotchInteractiveMode = state.pending != nil ? .nudge
            : state.mode == .expanded ? .expanded
            : state.mode == .compose  ? .compose
            : .collapsed
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
        // While composing, hover-based expand/collapse is suspended.
        guard state.mode != .compose else { return }
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
        case .compose:
            break   // handled by installComposeMonitors outside-click guard
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
        // Never expand recents out from under an open composer (a drag onto the
        // notch must not clobber a half-typed note or leak its monitors).
        guard state.mode != .expanded, state.mode != .compose else { return }
        pendingExpiryTask?.cancel()
        pendingExpiryTask = nil
        // Instantly hide card content before switching to expanded — no fade needed
        // since the whole panel is about to change shape anyway.
        state.showPendingContent = false
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
        // Don't collapse out from under a pending keep card or while composing.
        guard state.pending == nil, state.mode != .compose else { return }
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
        // Don't interrupt the user while they're composing a note.
        guard state.mode != .compose else { return }
        cancelExpand()
        cancelCollapse()
        let nudge = NudgeItem(candidate: candidate, preview: Self.preview(for: candidate))
        container?.interactiveRect = geometry.interactiveRect(for: .nudge)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        // Step 1: panel expands (content invisible — view's animation modifier handles
        // the size change via state.pending == nil).
        state.showPendingContent = false
        state.mode = .collapsed
        state.pending = nudge
        // Step 2: bloom the card in while the panel is still opening, so the grow
        // and the fade read as one continuous motion rather than two steps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.state.showPendingContent = true
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
        // Phase 1: fade out the card content (view's .animation modifier fires).
        let dismissedId = state.pending?.id
        state.showPendingContent = false
        // Phase 2: collapse the panel once the gentler fade-out has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self else { return }
            // Guard against a new capture arriving during the fade window.
            guard self.state.pending?.id == dismissedId else { return }
            self.container?.interactiveRect = self.geometry.interactiveRect(for: .collapsed)
            self.state.pending = nil
            self.state.mode = .collapsed
        }
    }

    // MARK: - Compose mode

    /// Opens the notch as a quick-note text composer. Pressing ⌥⌘N again
    /// while composing toggles it off (no save). ⌘↩ saves; ⎋ dismisses.
    func enterCompose() {
        // Mid-exit (fading closed)? Cancel the collapse and re-open cleanly
        // instead of toggling off into a dead window.
        if let work = composeCollapseWork {
            work.cancel()
            composeCollapseWork = nil
        } else if state.mode == .compose {
            // Fully open → the hotkey toggles it off (no save).
            exitCompose()
            return
        }

        // Conflict resolution: clear any pending card or recents state.
        if state.pending != nil {
            pendingExpiryTask?.cancel()
            pendingExpiryTask = nil
            state.showPendingContent = false
            state.pending = nil
        }
        cancelExpand()
        cancelCollapse()

        state.composeText = ""
        state.showComposeContent = false
        container?.interactiveRect = geometry.interactiveRect(for: .compose)

        // Activate so the panel actually receives keyboard input (a background
        // accessory app's key panel otherwise never gets keystrokes). Remember
        // the prior app so focus returns there on exit — but never record
        // ourselves (e.g. when re-opening mid-exit while Aura is frontmost).
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.acceptsKeyboard = true
        panel?.makeKeyAndOrderFront(nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        state.mode = .compose   // panel springs to compose size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.state.showComposeContent = true   // content fades in
        }
        installComposeMonitors()
    }

    /// Fades out compose content then collapses the panel, returning keyboard
    /// focus to whichever app was frontmost before composing.
    func exitCompose() {
        guard state.mode == .compose, composeCollapseWork == nil else { return }
        removeComposeMonitors()
        state.showComposeContent = false    // phase 1: fade out
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.composeCollapseWork = nil
            self.container?.interactiveRect = self.geometry.interactiveRect(for: .collapsed)
            self.state.mode = .collapsed    // phase 2: panel collapses
            self.panel?.acceptsKeyboard = false
            // Return focus to the app the user was in before composing. Set
            // acceptsKeyboard = false first so the panel can't re-grab key.
            if let prev = self.previousApp,
               prev.bundleIdentifier != Bundle.main.bundleIdentifier {
                prev.activate()
            }
            self.previousApp = nil
        }
        composeCollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26, execute: work)
    }

    /// Saves the composed text (if non-empty) then exits compose mode.
    func saveCompose(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let candidate = CaptureCandidate(payload: .text(trimmed),
                                             sourceApp: "Aura Quick Note")
            Task { await dataStore.save(candidate) }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        exitCompose()
    }

    private func installComposeMonitors() {
        // Local key monitor: intercepts ⌘↩ (save) and ⎋ (dismiss) while the
        // notch panel is key. TextEditor's NSTextView swallows events before
        // SwiftUI's onKeyPress sees them, so we handle shortcuts here.
        composeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.state.mode == .compose else { return event }
            let isReturn = event.keyCode == UInt16(kVK_Return)
                || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
            // Return (or ⌘Return) saves; ⇧Return falls through to insert a newline.
            if isReturn, !event.modifierFlags.contains(.shift) {
                let empty = self.state.composeText
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if empty { return nil }   // nothing to save — swallow, no-op
                self.saveCompose(text: self.state.composeText)
                return nil
            }
            if event.keyCode == UInt16(kVK_Escape) {
                self.exitCompose()
                return nil
            }
            return event
        }
        // Global mouse monitor: outside click dismisses the composer.
        composeClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.state.mode == .compose else { return }
            if !self.geometry.composeRect.contains(NSEvent.mouseLocation) {
                self.exitCompose()
            }
        }
    }

    private func removeComposeMonitors() {
        if let m = composeKeyMonitor { NSEvent.removeMonitor(m); composeKeyMonitor = nil }
        if let m = composeClickMonitor { NSEvent.removeMonitor(m); composeClickMonitor = nil }
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
