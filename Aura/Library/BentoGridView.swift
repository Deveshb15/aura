import SwiftUI

/// The bento / masonry grid. Computes a column count from the available width and
/// lays every card out in ONE `MasonryLayout` container (not side-by-side
/// LazyVStacks), so cards keep a stable identity: when the grid rebalances inside
/// an animation transaction, each card glides to its new position instead of
/// teleporting between columns. The grid is transparent so the window's dark
/// canvas shows through.
struct BentoGridView: View {
    let items: [Item]

    @Environment(InAppComposeLauncher.self) private var composeLauncher
    @State private var assigner = ColumnAssigner()

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
            let ordered = itemsWithDraft
            let colMap = assigner.columns(for: ordered, columnCount: columnCount, columnWidth: columnWidth)

            ScrollView {
                MasonryLayout(columnCount: columnCount, columnWidth: columnWidth, gap: gap) {
                    ForEach(ordered) { item in
                        CardView(item: item, columnWidth: columnWidth)
                            .frame(width: columnWidth)
                            .layoutValue(key: CardColumnKey.self, value: colMap[item.id] ?? 0)
                            // A newly added card plays a transition (the draft slides
                            // down into column 0; everything else fades in). Existing
                            // cards keep identity. Transitions only play inside an
                            // animation transaction, so first paint stays instant.
                            .transition(item.id == composeLauncher.draft?.id
                                ? .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity)
                                : .opacity)
                    }
                }
                .padding(.horizontal, outer)
                .padding(.top, 4)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
