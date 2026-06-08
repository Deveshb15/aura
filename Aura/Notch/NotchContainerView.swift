import AppKit

/// Hosts the SwiftUI content inside the fixed-size notch window and provides
/// click-through everywhere except the current interactive panel region.
///
/// Hover detection lives in `NotchController` (a global mouse monitor), so there
/// are intentionally NO tracking areas here — nothing to rebuild during the
/// content animation, hence no hover flicker. The controller updates
/// `interactiveRect` on every state transition.
final class NotchContainerView: NSView {
    /// Interactive region in this view's coordinates. Points outside it return
    /// nil from hitTest, so clicks/drags pass through to the menu bar and any
    /// window beneath.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}
