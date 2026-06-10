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

    /// A just-copied item awaiting "keep" — auto-popped as a card that slides
    /// down from the notch (no hover required). Keep it or it retracts on its own.
    var pending: NudgeItem?

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
