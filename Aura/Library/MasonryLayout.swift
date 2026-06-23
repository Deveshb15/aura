import SwiftUI

/// Per-card height hint published by `CardView` so the masonry can pack columns
/// without measuring image cards (which have no determinate height under a
/// width-only proposal). Text cards are measured for real; everything else uses
/// the aspect-correct `estimatedHeight`.
struct CardHeightHint: Equatable {
    var estimate: CGFloat
    var isText: Bool
}

struct CardHeightHintKey: LayoutValueKey {
    static let defaultValue = CardHeightHint(estimate: 160, isText: false)
}

/// The column each card is assigned to, published by `CardView` and computed by
/// `ColumnAssigner`. The Layout stacks cards into their assigned column rather
/// than re-balancing, so adding a card only shifts its own column.
struct CardColumnKey: LayoutValueKey {
    static let defaultValue = 0
}

/// A single-container Pinterest-style masonry. Every card lives in ONE layout
/// with a stable identity and a pre-assigned column (`CardColumnKey`); cards are
/// stacked top-down within their column in subview order (newest-first). Because
/// the column assignment is stable (`ColumnAssigner`), adding a card changes only
/// that one column's contents — so only that column animates, and no card ever
/// teleports across columns.
struct MasonryLayout: Layout {
    var columnCount: Int
    var columnWidth: CGFloat
    var gap: CGFloat

    struct Cache {
        var placements: [CGRect] = []   // one frame per subview, in subview order
        var totalHeight: CGFloat = 0
        var signature: Int = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        rebuildIfNeeded(subviews: subviews, cache: &cache)
        let width = columnWidth * CGFloat(columnCount) + gap * CGFloat(max(0, columnCount - 1))
        return CGSize(width: width, height: cache.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        rebuildIfNeeded(subviews: subviews, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            let frame = cache.placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Stacks each card into its assigned column (`CardColumnKey`), top-down in
    /// subview order. Recomputed only when an input that affects layout changes
    /// (column geometry, count, a height hint, or an assignment), so a single
    /// layout pass doesn't measure twice.
    private func rebuildIfNeeded(subviews: Subviews, cache: inout Cache) {
        guard columnCount > 0, columnWidth > 0 else {
            cache = Cache(); return
        }
        var hasher = Hasher()
        hasher.combine(columnCount)
        hasher.combine(columnWidth)
        hasher.combine(gap)
        hasher.combine(subviews.count)
        for subview in subviews {
            let hint = subview[CardHeightHintKey.self]
            hasher.combine(hint.isText)
            hasher.combine(hint.estimate)
            hasher.combine(subview[CardColumnKey.self])
        }
        let signature = hasher.finalize()
        guard signature != cache.signature || cache.placements.count != subviews.count else { return }

        var columnHeights = Array(repeating: CGFloat(0), count: columnCount)
        var placements: [CGRect] = []
        placements.reserveCapacity(subviews.count)

        for subview in subviews {
            let hint = subview[CardHeightHintKey.self]
            // Text self-sizes; floor the measured height with the estimate so a
            // not-yet-laid-out NSTextView can't collapse to its 20pt minimum for a
            // frame. Non-text uses the aspect-correct estimate directly.
            let height: CGFloat
            if hint.isText {
                let measured = subview.sizeThatFits(
                    ProposedViewSize(width: columnWidth, height: nil)
                ).height
                height = max(measured, hint.estimate)
            } else {
                height = hint.estimate
            }

            // Place into the pre-assigned column (clamped for safety after a resize
            // that reduced the column count before the assigner caught up).
            let col = min(max(0, subview[CardColumnKey.self]), columnCount - 1)
            let x = CGFloat(col) * (columnWidth + gap)
            let y = columnHeights[col]
            placements.append(CGRect(x: x, y: y, width: columnWidth, height: height))
            columnHeights[col] += height + gap
        }

        cache.placements = placements
        cache.totalHeight = max(0, (columnHeights.max() ?? gap) - gap)
        cache.signature = signature
    }
}
