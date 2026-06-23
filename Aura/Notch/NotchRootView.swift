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
    let onSaveCompose: (String) -> Void
    let onAddNote: () -> Void
    let onBackCompose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            styledPanel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Drop target spans the whole notch window, not just the (collapsed-size)
        // panel, so a drag is caught over the generous region the window's
        // hitTest now lets drags through (see `NotchContainerView.dropRect`).
        // Entering it flips `isTargeted` → springs the notch open → the drop
        // lands on the expanded surface.
        .onDrop(of: DropReceiver.acceptedTypes, isTargeted: dropBinding) { providers in
            DropReceiver.handle(providers) { candidate in
                Task { await dataStore.save(candidate) }
            }
            return true
        }
    }

    private var styledPanel: some View {
        panel
            .frame(width: panelSize.width, height: panelSize.height)
            .background(NotchShape().fill(AuraTheme.notchPanel))
            .overlay(NotchShape().stroke(AuraTheme.hairlineStrong, lineWidth: 0.5))
            .clipShape(NotchShape())
            // Panel size springs between collapsed / nudge / expanded.
            // Critically damped on pending so the notch grows/shrinks cleanly —
            // a hair slower so the grow paces with the card blooming inside it.
            .animation(.spring(response: 0.4, dampingFraction: 1.0), value: state.pending == nil)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: state.mode)
            // Click the notch / its empty chrome (e.g. the "Aura" header) to open
            // the library. The card's Keep / ✕ buttons handle their own taps first.
            // (Drag-and-drop is handled one level up, on the full-window view.)
            .onTapGesture { onOpenLibrary() }
    }

    @ViewBuilder private var panel: some View {
        ZStack(alignment: .top) {
            if let pending = state.pending {
                NudgeCardView(item: pending, onKeep: onKeepPending, onDismiss: onDismissPending)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    // Panel size is driven by `pending != nil`; the card's
                    // appearance is driven separately so the sequence is always:
                    //   show → panel expands first, then the card blooms in
                    //   hide → card eases out first, then panel collapses
                    // Opacity + a subtle settle (slides down from the notch and
                    // scales up from its top edge). `.smooth` has zero bounce, so
                    // it reads as a gentle glide, never the old rubber-band nudge.
                    .opacity(state.showPendingContent ? 1 : 0)
                    .scaleEffect(state.showPendingContent ? 1 : 0.98, anchor: .top)
                    .offset(y: state.showPendingContent ? 0 : -6)
                    // Asymmetric: blooms in gently, leaves a touch quicker.
                    .animation(state.showPendingContent
                               ? .smooth(duration: 0.42)
                               : .smooth(duration: 0.28),
                               value: state.showPendingContent)
            } else if state.mode == .compose {
                ComposeView(
                    text: $state.composeText,
                    onSave: onSaveCompose,
                    onBack: onBackCompose
                )
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .opacity(state.showComposeContent ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: state.showComposeContent)
            } else if state.mode == .expanded {
                NotchExpandedView(dataStore: dataStore,
                                  isDropTargeted: state.isDropTargeted,
                                  onAddNote: onAddNote,
                                  onOpenLibrary: onOpenLibrary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // Center vertically below the notch so the gap above the
                    // header matches the gap below the Open App button.
                    .frame(maxHeight: .infinity, alignment: .center)
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
        case .compose:
            return CGSize(width: NotchGeometry.composeWidth, height: notchInset + NotchGeometry.composeHeight)
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
