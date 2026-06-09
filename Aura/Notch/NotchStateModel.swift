import AppKit
import Observation

/// Observable state for the notch panel, read by `NotchRootView` and driven by
/// `NotchController`.
@MainActor
@Observable
final class NotchStateModel {
    enum Mode {
        case collapsed
        case expanded
    }

    var mode: Mode = .collapsed
    var isDropTargeted = false

    /// A just-copied item awaiting "keep" — shown as a chip only when the user
    /// hovers the notch (it is NOT auto-popped as a card). Expires if ignored.
    var pending: NudgeItem?

    /// Incremented on every copy to fire the one-shot elastic bounce animation.
    var bounceTrigger: Int = 0

    /// The collapsed panel size (≈ the physical notch), kept in sync by the
    /// controller so the SwiftUI panel can size itself reactively.
    var collapsedSize: CGSize = CGSize(width: 200, height: 32)
}

/// A clipboard capture awaiting "keep".
struct NudgeItem: Identifiable {
    let id = UUID()
    let candidate: CaptureCandidate
    let preview: NudgePreview
}

enum NudgePreview {
    case text(String)
    case url(String)
    case image(NSImage)
    case file(String)
    case color(String)
}
