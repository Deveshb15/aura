import SwiftUI

/// SwiftUI root hosted inside the FIXED-size notch window. The window stays a
/// transparent full-width strip; the black panel is a top-centered, explicitly
/// sized view that springs between collapsed / expanded / nudge sizes. Because
/// the window never resizes, there is no tracking-area thrash and no flicker.
///
/// On copy, a "keep this?" card slides down from the notch automatically (no
/// hover needed); hovering the notch instead opens the recents strip.
struct NotchRootView: View {
    @Bindable var state: NotchStateModel
    let dataStore: DataStore
    let onKeepPending: () -> Void
    let onDismissPending: () -> Void
    let onDragTargetedChange: (Bool) -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            styledPanel
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
            // Panel size springs between collapsed / nudge / expanded.
            // Critically damped on pending so the notch grows/shrinks cleanly.
            .animation(.spring(response: 0.34, dampingFraction: 1.0), value: state.pending == nil)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: state.mode)
            .onDrop(of: DropReceiver.acceptedTypes, isTargeted: dropBinding) { providers in
                DropReceiver.handle(providers) { candidate in
                    Task { await dataStore.save(candidate) }
                }
                return true
            }
            // Click the notch / its empty chrome (e.g. the "Aura" header) to open
            // the library. The card's Keep / ✕ buttons handle their own taps first.
            .onTapGesture { onOpenLibrary() }
    }

    @ViewBuilder private var panel: some View {
        ZStack(alignment: .top) {
            if let pending = state.pending {
                NudgeCardView(item: pending, onKeep: onKeepPending, onDismiss: onDismissPending)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    // Panel size is driven by `pending != nil`; content opacity is
                    // driven separately so the sequence is always:
                    //   show → panel expands first, then content fades in
                    //   hide → content fades out first, then panel collapses
                    .opacity(state.showPendingContent ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: state.showPendingContent)
            } else if state.mode == .expanded {
                NotchExpandedView(dataStore: dataStore, isDropTargeted: state.isDropTargeted)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Push content below the physical notch so it isn't clipped by it.
        .padding(.top, notchInset)
    }

    /// Height of the physical notch — content is inset by this so it clears it.
    private var notchInset: CGFloat { state.collapsedSize.height }

    private var panelSize: CGSize {
        if state.pending != nil {
            return CGSize(width: NotchGeometry.nudgeWidth, height: notchInset + NotchGeometry.nudgeHeight)
        }
        switch state.mode {
        case .expanded:
            return CGSize(width: NotchGeometry.expandedWidth, height: notchInset + NotchGeometry.expandedHeight)
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
