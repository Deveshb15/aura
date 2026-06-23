import AppKit

/// Hosts the SwiftUI content inside the fixed-size notch window and provides
/// click-through everywhere except the current interactive panel region.
///
/// Hover detection lives in `NotchController` (a global mouse monitor), so there
/// are intentionally NO tracking areas here — nothing to rebuild during the
/// content animation, hence no hover flicker. The controller updates
/// `interactiveRect` on every state transition.
final class NotchContainerView: NSView {
    /// Interactive region for CLICKS, in this view's coordinates. Points outside
    /// it return nil from hitTest, so clicks pass through to the menu bar and any
    /// window beneath. Kept deliberately tight (≈ the notch) so tab-bar clicks
    /// just under the notch aren't swallowed.
    var interactiveRect: CGRect = .zero

    /// Interactive region for an in-progress DRAG — generous, so dropping a file
    /// onto the notch doesn't require threading the ~32px collapsed sliver.
    /// Entering it lets SwiftUI's `.onDrop` fire, which springs the notch open.
    var dropRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        // A drag in flight: accept the generous drop region. Clicks stay gated to
        // the tight `interactiveRect` so menu-bar / tab-bar clicks under the notch
        // still pass through to the app beneath.
        if Self.isDragInProgress, dropRect.contains(local) {
            return super.hitTest(point)
        }
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    /// True while AppKit is tracking a drag (the current event is a drag), which
    /// is how the destination's hitTest distinguishes a drop-in-progress from a
    /// plain click. Mirrors the NotchDrop hit-testing pattern this notch follows.
    private static var isDragInProgress: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: return true
        default: return false
        }
    }
}
