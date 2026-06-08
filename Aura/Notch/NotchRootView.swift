import SwiftUI

/// SwiftUI root hosted inside the FIXED-size notch window. The window stays a
/// transparent full-width strip; the black panel is a top-centered, explicitly
/// sized view that springs between collapsed / expanded / nudge sizes. Because
/// the window never resizes, there is no tracking-area thrash and no flicker.
struct NotchRootView: View {
    @Bindable var state: NotchStateModel
    let dataStore: DataStore
    let onKeepNudge: () -> Void
    let onDragTargetedChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            panel
                .frame(width: panelSize.width, height: panelSize.height)
                .background(NotchShape().fill(Color.black))
                .overlay(NotchShape().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .clipShape(NotchShape())
                .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.mode)
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: state.nudge?.id)
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

    @ViewBuilder private var panel: some View {
        ZStack(alignment: .top) {
            if let nudge = state.nudge {
                NudgeCardView(nudge: nudge, onKeep: onKeepNudge)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity)
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
        if state.nudge != nil {
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
