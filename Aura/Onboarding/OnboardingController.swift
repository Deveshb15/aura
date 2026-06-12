import AppKit
import SwiftUI

/// A borderless-looking `NSWindow` that can still become key, so the name
/// `TextField` in onboarding receives keyboard input even though the app is a
/// menu-bar accessory agent.
final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the first-launch onboarding window and its lifecycle. Mirrors the
/// AppKit-owns-the-window / SwiftUI-hosted-inside idiom used by `NotchController`.
///
/// While onboarding is open the app is temporarily promoted to `.regular` (so it
/// foregrounds with a real key window and the system notification prompt attaches
/// correctly); on finish it reverts to `.accessory`. The completion closure is
/// what wires the app "live" — it reveals the notch and starts clipboard capture.
@MainActor
final class OnboardingController {
    private var window: OnboardingWindow?
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func show() {
        let size = NSSize(width: 560, height: 640)
        let window = OnboardingWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],   // no .resizable / .closable
            backing: .buffered,
            defer: false)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(AuraTheme.background)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.moveToActiveSpace]
        window.level = .normal

        let root = OnboardingView(onFinish: { [weak self] in self?.finish() })
        window.contentView = NSHostingView(rootView: root)
        window.center()
        self.window = window

        // Promote to a regular foreground app for the duration of onboarding.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
        onFinish()
    }
}
