import AppKit
import SwiftUI

/// Owns the standalone license-gate window — the hard paywall shown to a
/// returning user whose key is missing/cleared/revoked, and re-shown mid-session
/// when a license is revoked or this Mac is deactivated. A near-verbatim clone of
/// `OnboardingController`: it reuses that file's `OnboardingWindow` (a borderless
/// window that can still become key, so the license `TextField` accepts input
/// while the app is a menu-bar accessory), promotes the app to `.regular` while
/// shown, and reverts to `.accessory` on finish.
@MainActor
final class LicenseActivationController {
    private var window: OnboardingWindow?
    private let license: LicenseManager
    private let onActivated: () -> Void

    init(license: LicenseManager, onActivated: @escaping () -> Void) {
        self.license = license
        self.onActivated = onActivated
    }

    func show() {
        guard window == nil else {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }

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

        let root = LicenseActivationView(
            license: license,
            onActivated: { [weak self] in self?.finish() },
            showsQuit: true)
            .preferredColorScheme(.dark)
        window.contentView = NSHostingView(rootView: root)
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
        window = nil
        NSApp.setActivationPolicy(.accessory)
        onActivated()
    }
}
