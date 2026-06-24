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
        /// The notch is open as a text composer (triggered by ⌥⌘N).
        case compose
    }

    var mode: Mode = .collapsed
    var isDropTargeted = false

    /// A just-copied item awaiting "keep" — auto-popped as a card from the notch.
    var pending: NudgeItem?

    /// Controls the opacity of the card content independently from the panel
    /// size, so the sequence is: panel expands → content fades in … content
    /// fades out → panel collapses (never the other way around).
    var showPendingContent: Bool = false

    /// Mirrors the live text in ComposeView via @Binding so NotchController's
    /// key monitor can read it without a callback chain.
    var composeText: String = ""

    /// Same expand-then-fade pattern as showPendingContent, for compose mode.
    var showComposeContent: Bool = false

    /// The collapsed panel size (≈ the physical notch), kept in sync by the
    /// controller so the SwiftUI panel can size itself reactively.
    var collapsedSize: CGSize = CGSize(width: 200, height: 24)
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
