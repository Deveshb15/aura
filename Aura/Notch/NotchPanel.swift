import AppKit

/// A borderless, non-activating panel that floats over the notch on every Space
/// and over fullscreen apps, and never steals focus. It is created once at a
/// FIXED full-width frame and never resized — only its SwiftUI content animates.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        // Above the menu bar (statusBar is 25; +8 mirrors NotchDrop).
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 8)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    /// Set to `true` before calling `makeKeyAndOrderFront(_:)` so the panel can
    /// receive keyboard events (needed for compose mode). Clear it on exit so the
    /// panel returns to its normal click-through, non-key state.
    var acceptsKeyboard: Bool = false

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}
