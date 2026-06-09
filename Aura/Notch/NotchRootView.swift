import SwiftUI

/// Animated values for the elastic "copied" bounce — a vertical stretch, a
/// horizontal squash-then-overshoot, and a sideways skew wobble, so it reads
/// like rubber being yanked on every side.
private struct BounceValue {
    var scaleY: CGFloat = 1.0
    var scaleX: CGFloat = 1.0
    var skew: CGFloat = 0.0
    static let rest = BounceValue()
}

/// A horizontal shear: the bottom leans sideways while the top edge stays put.
private struct SkewModifier: ViewModifier {
    let skew: CGFloat
    func body(content: Content) -> some View {
        content.transformEffect(CGAffineTransform(a: 1, b: 0, c: skew, d: 1, tx: 0, ty: 0))
    }
}

/// SwiftUI root hosted inside the FIXED-size notch window. The window stays a
/// transparent full-width strip; the black panel is a top-centered, explicitly
/// sized view. On copy the notch does a rubber-band bounce (content only, no
/// window resize). Hovering reveals a "keep" chip for a pending copy.
struct NotchRootView: View {
    @Bindable var state: NotchStateModel
    let dataStore: DataStore
    let onKeepPending: () -> Void
    let onDismissPending: () -> Void
    let onDragTargetedChange: (Bool) -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        // Captured as a plain value so the (Sendable) keyframe closure doesn't
        // touch main-actor state; the bounce only affects the collapsed nub.
        let bounceActive = state.mode == .collapsed
        return VStack(spacing: 0) {
            styledPanel
                .keyframeAnimator(initialValue: BounceValue.rest, trigger: state.bounceTrigger) { content, value in
                    content
                        .scaleEffect(
                            x: bounceActive ? value.scaleX : 1,
                            y: bounceActive ? value.scaleY : 1,
                            anchor: .top
                        )
                        .modifier(SkewModifier(skew: bounceActive ? value.skew : 0))
                } keyframes: { _ in
                    // Vertical: yank down deep and a touch slow, then a long bouncy settle.
                    KeyframeTrack(\.scaleY) {
                        SpringKeyframe(2.4, duration: 0.30, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.90, spring: .bouncy(extraBounce: 0.55))
                    }
                    // Horizontal: squash narrow on the drop, then overshoot WIDER than the
                    // notch ("ears" past the sides), undershoot, settle.
                    KeyframeTrack(\.scaleX) {
                        SpringKeyframe(0.80, duration: 0.30, spring: .snappy)
                        SpringKeyframe(1.22, duration: 0.32, spring: .bouncy(extraBounce: 0.45))
                        SpringKeyframe(0.94, duration: 0.30, spring: .bouncy(extraBounce: 0.3))
                        SpringKeyframe(1.0, duration: 0.25, spring: .snappy)
                    }
                    // Skew: tug to one side, wobble to the other, straighten.
                    KeyframeTrack(\.skew) {
                        SpringKeyframe(0.14, duration: 0.30, spring: .snappy)
                        SpringKeyframe(-0.09, duration: 0.32, spring: .bouncy(extraBounce: 0.4))
                        SpringKeyframe(0.04, duration: 0.30, spring: .bouncy(extraBounce: 0.3))
                        SpringKeyframe(0.0, duration: 0.25, spring: .snappy)
                    }
                }
                .onDrop(of: DropReceiver.acceptedTypes, isTargeted: dropBinding) { providers in
                    DropReceiver.handle(providers) { candidate in
                        Task { await dataStore.save(candidate) }
                    }
                    return true
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var styledPanel: some View {
        panel
            .frame(width: panelSize.width, height: panelSize.height)
            .background(NotchShape().fill(Color.black))
            .overlay(NotchShape().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .clipShape(NotchShape())
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: state.mode)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: state.pending?.id)
            // Click the notch / its empty chrome (e.g. the "Aura" header) to open
            // the library. Cards and the keep chip handle their own taps first.
            .onTapGesture { onOpenLibrary() }
    }

    @ViewBuilder private var panel: some View {
        ZStack(alignment: .top) {
            if state.mode == .expanded {
                NotchExpandedView(
                    dataStore: dataStore,
                    isDropTargeted: state.isDropTargeted,
                    pending: state.pending,
                    onKeepPending: onKeepPending,
                    onDismissPending: onDismissPending
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Push content below the physical notch so it isn't clipped by it.
        .padding(.top, notchInset)
    }

    /// Height of the physical notch — content is inset by this so it clears it.
    private var notchInset: CGFloat { state.collapsedSize.height }

    private var panelSize: CGSize {
        switch state.mode {
        case .expanded:
            let chip = state.pending != nil ? KeepChipView.height + 8 : 0
            return CGSize(width: NotchGeometry.expandedWidth,
                          height: notchInset + NotchGeometry.expandedHeight + chip)
        case .collapsed:
            return state.collapsedSize
        }
    }

    private var dropBinding: Binding<Bool> {
        Binding(
            get: { state.isDropTargeted },
            set: { newValue in
                state.isDropTargeted = newValue
                onDragTargetedChange(newValue)
            }
        )
    }
}
