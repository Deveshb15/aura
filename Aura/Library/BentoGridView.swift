import SwiftUI

/// The bento / masonry grid. Computes a column count from the available width and
/// lays every card out in ONE `MasonryLayout` container (not side-by-side
/// LazyVStacks), so cards keep a stable identity: when the grid rebalances inside
/// an animation transaction, each card glides to its new position instead of
/// teleporting between columns. The grid is transparent so the window's dark
/// canvas shows through.
struct BentoGridView: View {
    let items: [Item]
    /// Extra bottom padding inside the scroll content so the last row can scroll
    /// clear of the floating search pill anchored at the window's bottom edge.
    var bottomInset: CGFloat = 28
    /// Identity of the current view (tab + search query). When it changes, the
    /// grid re-balances its columns and resets the scroll window — a filter/search
    /// switch is a fresh layout, not an in-place edit of the previous set.
    var layoutResetKey: String = ""

    @Environment(InAppComposeLauncher.self) private var composeLauncher
    @State private var assigner = ColumnAssigner()
    /// How many cards are currently rendered. The grid grows this window as the
    /// user scrolls toward the bottom, so it never instantiates all (≤400) cards
    /// — and their image decodes — up front. See `growWindowIfNeeded`.
    @State private var visibleCount = BentoGridView.initialWindow

    /// First-paint window and how much each scroll-triggered growth adds.
    private static let initialWindow = 60
    private static let windowStep = 40
    /// Start growing when one of the last N rendered cards appears.
    private static let growThreshold = 8

    private let outer: CGFloat = 32   // matches the hero/tab horizontal margin
    private let gap: CGFloat = 16

    /// The active note draft prepended as the newest item (it gets column 0). Once
    /// the draft is saved its id appears in `items` (optimistic insert); the dedupe
    /// guard keeps a single continuous card so saving never removes/re-adds it.
    private var itemsWithDraft: [Item] {
        guard let draft = composeLauncher.draft else { return items }
        if items.contains(where: { $0.id == draft.id }) { return items }
        return [draft] + items
    }

    var body: some View {
        GeometryReader { geo in
            let avail = max(0, geo.size.width - outer * 2)
            let columnCount = max(2, min(5, Int(avail / 300)))
            let columnWidth = max(120, (avail - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            let all = itemsWithDraft
            // Assign columns over the FULL set (greedy shortest-column), so a
            // capture/delete is an incremental edit of the whole grid rather than
            // of whatever slice happens to be windowed. The window only limits how
            // many cards are rendered; because the greedy assignment is prefix-
            // stable, the visible cards stay balanced as the window grows on scroll.
            let colMap = assigner.columns(for: all, columnCount: columnCount,
                                          columnWidth: columnWidth, resetKey: layoutResetKey)
            let ordered = Array(all.prefix(visibleCount))

            ScrollView {
                MasonryLayout(columnCount: columnCount, columnWidth: columnWidth, gap: gap) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                        CardView(item: item, columnWidth: columnWidth)
                            .frame(width: columnWidth)
                            .layoutValue(key: CardColumnKey.self, value: colMap[item.id] ?? 0)
                            // A newly added card plays a transition (the draft slides
                            // down into column 0; everything else fades in). Existing
                            // cards keep identity. Transitions only play inside an
                            // animation transaction, so first paint stays instant.
                            .transition(insertionTransition(for: item))
                            .onAppear { growWindowIfNeeded(index: index, total: all.count) }
                    }
                }
                .padding(.horizontal, outer)
                .padding(.top, 4)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Reset the window on a view switch (tab/search), so a deep scroll in
            // one view doesn't carry into the next. Keyed on the view identity —
            // NOT on item changes — so capturing a new item while scrolled deep
            // doesn't snap the scroll back to the top.
            .onChange(of: layoutResetKey) { _, _ in visibleCount = Self.initialWindow }
        }
    }

    /// The insertion/removal transition for a card.
    ///
    /// Saved cards (including text notes, which now render as pure SwiftUI `Text`
    /// in `TextCardView`) embed no AppKit view, so they're safe to fade in. The
    /// ONE exception is the active draft: it mounts the live `NSTextView` editor
    /// while you type, and SwiftUI plays an insertion transition by snapshotting
    /// the entering view — snapshotting an `NSViewRepresentable`-hosting view
    /// inverts its layer geometry (the footer-flip bug). So the draft gets NO
    /// snapshot transition (it appears in place); everything else fades in.
    private func insertionTransition(for item: Item) -> AnyTransition {
        item.id == composeLauncher.draft?.id ? .identity : .opacity
    }

    /// Extends the render window as the user nears the bottom of what's shown.
    private func growWindowIfNeeded(index: Int, total: Int) {
        guard visibleCount < total, index >= visibleCount - Self.growThreshold else { return }
        visibleCount = min(visibleCount + Self.windowStep, total)
    }
}
