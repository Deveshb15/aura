import SwiftUI
import AppKit

/// An in-place, self-sizing text editor used by `TextCardView` so notes can be
/// edited directly in the grid (no modal). It wraps a non-scrolling `NSTextView`
/// for two reasons SwiftUI can't give us on macOS 14:
///   1. Clicking puts the caret exactly where you clicked (native NSTextView).
///   2. It reports a real `intrinsicContentSize`, so the masonry card grows with
///      the text instead of clipping (which `TextField(axis:.vertical)` does
///      unreliably inside a LazyVStack on macOS 14).
/// Styling is matched to the read-only `Text` it replaces (size 15,
/// `textPrimary`, 2pt line spacing, pink caret).
struct InlineNoteEditor: NSViewRepresentable {
    @Binding var text: String
    /// Available content width (column width minus the card's horizontal padding).
    /// The text container is pinned to this so height layout is deterministic.
    var width: CGFloat
    /// When true, the editor grabs first responder once (used for a new draft).
    var autoFocus: Bool
    /// Called as first-responder status flips (true = began, false = blurred).
    var onFocusChange: (Bool) -> Void
    /// Esc pressed while editing.
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SelfSizingTextView {
        let tv = SelfSizingTextView()
        tv.delegate = context.coordinator
        tv.onFocusChange = { context.coordinator.parent.onFocusChange($0) }
        tv.onEscape = { context.coordinator.parent.onEscape() }

        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.insertionPointColor = NSColor(AuraTheme.accentDot)

        tv.font = .systemFont(ofSize: 15)
        tv.textColor = NSColor(AuraTheme.textPrimary)
        tv.defaultParagraphStyle = Self.paragraphStyle
        tv.typingAttributes = Self.typingAttributes

        tv.string = text
        tv.preferredMaxWidth = width
        return tv
    }

    func updateNSView(_ tv: SelfSizingTextView, context: Context) {
        // Keep the coordinator's closures (which capture current SwiftUI state)
        // fresh across re-renders.
        context.coordinator.parent = self
        tv.preferredMaxWidth = width

        // Only mirror external text in when we're NOT the first responder, so a
        // background re-publish (e.g. link enrichment) never clobbers what the
        // user is typing.
        let isEditing = tv.window?.firstResponder === tv
        if !isEditing, tv.string != text {
            tv.string = text
            tv.invalidateIntrinsicContentSize()
        }

        if autoFocus, !context.coordinator.didAutoFocus {
            context.coordinator.didAutoFocus = true
            DispatchQueue.main.async {
                guard let window = tv.window else {
                    // Not in a window yet — let a later update retry.
                    context.coordinator.didAutoFocus = false
                    return
                }
                window.makeFirstResponder(tv)
            }
        }
    }

    private static let paragraphStyle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        return p
    }()

    private static let typingAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15),
        .foregroundColor: NSColor(AuraTheme.textPrimary),
        .paragraphStyle: paragraphStyle,
    ]

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineNoteEditor
        var didAutoFocus = false

        init(_ parent: InlineNoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// A non-scrolling `NSTextView` that sizes its height to its content and reports
/// focus changes / Esc up to SwiftUI.
final class SelfSizingTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var onEscape: (() -> Void)?

    /// Fixed wrapping width for height calculation. Set by the representable.
    var preferredMaxWidth: CGFloat = 0 {
        didSet {
            guard preferredMaxWidth != oldValue, preferredMaxWidth > 0 else { return }
            textContainer?.containerSize = NSSize(width: preferredMaxWidth,
                                                  height: .greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }
    }

    private let minHeight: CGFloat = 20

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer, preferredMaxWidth > 0 else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height)
        return NSSize(width: preferredMaxWidth, height: max(height, minHeight))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
        window?.makeFirstResponder(nil)
    }
}
