import AppKit

/// Which interactive region is currently live (drives both the hitTest
/// click-through rect and the visible panel size).
enum NotchInteractiveMode {
    case collapsed
    case expanded
    /// A just-copied item is peeking as a card with a Keep button.
    case nudge
    /// The notch is open as a quick-note text composer.
    case compose
}

/// Computes the FIXED notch window frame plus the global-coordinate hover zones.
/// The window never resizes — only the SwiftUI content animates — so there is
/// no tracking-area thrash and therefore no hover flicker.
struct NotchGeometry {
    let screen: NSScreen
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    // Fixed panel sizes (the window itself is a constant full-width strip).
    static let windowHeight: CGFloat = 420
    static let expandedWidth: CGFloat = 560
    static let expandedHeight: CGFloat = 204
    /// The peeking "keep this?" card auto-shown when something is copied.
    static let nudgeWidth: CGFloat = 360
    static let nudgeHeight: CGFloat = 76
    /// The quick-note compose surface opened via ⌥⌘N.
    static let composeWidth: CGFloat = 520
    static let composeHeight: CGFloat = 260

    /// Remembers the last real screen. During display reconfiguration
    /// (lid close / unplug / sleep) `NSScreen.screens` can briefly be empty and
    /// `NSScreen.main` nil — the old `NSScreen.screens.first!` force-unwrap
    /// crashed there. Falling back to the remembered screen (and returning nil
    /// only if no display was ever seen) keeps the app alive; callers then keep
    /// their previous geometry.
    private static var lastScreen: NSScreen?

    static func current() -> NotchGeometry? {
        guard let screen = notchedScreen() ?? NSScreen.main ?? NSScreen.screens.first ?? lastScreen else {
            return nil
        }
        return make(for: screen)
    }

    /// Geometry for the display the cursor is currently on, so the notch can
    /// follow the active screen. On a screen without a physical notch this
    /// produces the same top-center "pill" fallback used in clamshell mode —
    /// i.e. a faked notch on external monitors. `NSEvent.mouseLocation` and
    /// `NSScreen.frame` share the global bottom-left-origin space, so
    /// `frame.contains` is correct even for negatively-positioned externals.
    static func forActiveScreen() -> NotchGeometry? {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                ?? NSScreen.main ?? lastScreen else {
            return nil
        }
        return make(for: screen)
    }

    /// Builds geometry for a specific screen: a real notch (from `safeAreaInsets`
    /// / auxiliary areas) when the display has one, or a 180×32 top-center pill
    /// fallback when it doesn't.
    private static func make(for screen: NSScreen) -> NotchGeometry {
        lastScreen = screen
        let topInset = screen.safeAreaInsets.top
        let hasNotch = topInset > 0
        let height = hasNotch ? topInset : 32

        var width: CGFloat = hasNotch ? 200 : 180
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            width = max(120, screen.frame.width - left.width - right.width)
        }

        return NotchGeometry(screen: screen, hasNotch: hasNotch, notchWidth: width, notchHeight: height)
    }

    static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// Collapsed panel size (≈ the physical notch, or a small pill on non-notch displays).
    var collapsedSize: CGSize {
        CGSize(width: max(notchWidth, 180), height: notchHeight)
    }

    /// The FIXED window: full width of the notch screen × a constant tall strip,
    /// pinned to the very top. Created once, never resized.
    var windowFrame: NSRect {
        NSRect(x: screen.frame.minX,
               y: screen.frame.maxY - Self.windowHeight,
               width: screen.frame.width,
               height: Self.windowHeight)
    }

    /// Centered, top-pinned rect in GLOBAL screen coordinates.
    private func globalRect(width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: screen.frame.midX - width / 2,
               y: screen.frame.maxY - height,
               width: width,
               height: height)
    }

    /// OPEN-trigger zone: stays ENTIRELY within the notch / menu-bar band at the
    /// very top of the screen. A little wider than the notch for an easy
    /// horizontal target, but its bottom edge is pulled UP a few points ABOVE the
    /// menu-bar's lower edge, so it never reaches down into a browser's tab bar /
    /// new-tab button below the notch (which used to pop the panel open when
    /// switching tabs). Monitor-based.
    var notchRect: NSRect {
        globalRect(width: max(notchWidth, 180) + 30, height: notchHeight - 6)
    }

    /// Large CLOSE zone: the expanded panel area (slightly padded for forgiveness).
    /// Staying anywhere inside this keeps the panel open — the asymmetry vs
    /// notchRect is what makes it stay open instead of flickering. The panel
    /// content sits BELOW the physical notch, so the zone height includes the
    /// notch inset.
    var openedRect: NSRect {
        globalRect(width: Self.expandedWidth + 24,
                   height: notchHeight + Self.expandedHeight + 12)
    }

    /// Keep-alive zone for the peeking copy card: hovering inside it pauses the
    /// auto-dismiss countdown; leaving restarts it. Offset below the notch.
    var nudgeRect: NSRect {
        globalRect(width: Self.nudgeWidth + 24, height: notchHeight + Self.nudgeHeight + 16)
    }

    /// Hit-test zone for the compose panel — used by the global mouse monitor to
    /// detect outside-clicks that should dismiss the composer.
    var composeRect: NSRect {
        globalRect(width: Self.composeWidth + 24, height: notchHeight + Self.composeHeight + 12)
    }

    /// The interactive rect in the container VIEW's coordinates (bottom-left
    /// origin, pinned to the top of the window). Used for hitTest click-through.
    func interactiveRect(for mode: NotchInteractiveMode) -> CGRect {
        let size: CGSize
        switch mode {
        case .collapsed:
            // Cover the notch itself for clicks / drag-drop, but do NOT spill
            // below it into the browser tab bar, so tab clicks just under the
            // notch pass through instead of being swallowed.
            size = CGSize(width: max(notchWidth, 180) + 16, height: notchHeight)
        case .expanded:
            size = CGSize(width: Self.expandedWidth + 24,
                          height: notchHeight + Self.expandedHeight + 12)
        case .nudge:
            size = CGSize(width: Self.nudgeWidth + 24,
                          height: notchHeight + Self.nudgeHeight + 16)
        case .compose:
            size = CGSize(width: Self.composeWidth + 24,
                          height: notchHeight + Self.composeHeight + 12)
        }
        let viewWidth = screen.frame.width
        return CGRect(x: (viewWidth - size.width) / 2,
                      y: Self.windowHeight - size.height,
                      width: size.width,
                      height: size.height)
    }
}
