import SwiftUI

/// History-aware column assignment for the masonry grid.
///
/// A newly added item goes to **column 0** (top-left) and stays there; every
/// existing item keeps its column. So adding a note only shifts column 0 and
/// never reshuffles the rest of the grid (the "top-left, always" behavior).
/// Wholesale changes — first paint, a column-count change on resize, or a swap of
/// the item set (search / tab) — re-balance the whole current set so those views
/// aren't lopsided.
///
/// Held by `BentoGridView` in `@State`. It is a plain (non-observable) class so
/// recomputing in `body` doesn't trigger re-render loops: callers use the
/// returned map, not its internals.
@MainActor
final class ColumnAssigner {
    private var columnOf: [String: Int] = [:]
    private var lastIDs: Set<String> = []
    private var lastColumnCount = 0

    /// Small add/remove deltas stay incremental (a user adding a note, the
    /// draft+save burst, a single delete); anything larger re-balances.
    private let smallDelta = 3

    /// Returns the id→column map for `ordered` (newest-first). Mutates internal
    /// bookkeeping; safe to call every `body` pass.
    func columns(for ordered: [Item], columnCount: Int, columnWidth: CGFloat) -> [String: Int] {
        guard columnCount > 0 else { return [:] }
        let newIDs = Set(ordered.map(\.id))
        let additions = newIDs.subtracting(lastIDs)
        let removed = lastIDs.subtracting(newIDs)

        // Incremental only for a small pure-add or small pure-remove on the same
        // set and column count. Everything else (search/tab swap, bulk import,
        // resize, first paint) re-balances.
        let incremental =
            !columnOf.isEmpty &&
            columnCount == lastColumnCount &&
            ((additions.count <= smallDelta && removed.isEmpty) ||
             (removed.count <= smallDelta && additions.isEmpty))

        if incremental {
            for id in additions { columnOf[id] = 0 }            // new → top-left
            for id in removed { columnOf.removeValue(forKey: id) }
            // Safety: never leave a visible item unassigned.
            for item in ordered where columnOf[item.id] == nil { columnOf[item.id] = 0 }
        } else {
            columnOf = balanced(ordered, columnCount: columnCount, columnWidth: columnWidth)
        }

        lastIDs = newIDs
        lastColumnCount = columnCount
        return columnOf
    }

    /// One-time balanced (greedy shortest-column) assignment for the current set.
    private func balanced(_ ordered: [Item], columnCount: Int, columnWidth: CGFloat) -> [String: Int] {
        var heights = Array(repeating: CGFloat(0), count: columnCount)
        var map: [String: Int] = [:]
        for item in ordered {
            var shortest = 0
            for i in 1..<columnCount where heights[i] < heights[shortest] { shortest = i }
            map[item.id] = shortest
            heights[shortest] += MasonryColumnizer.estimatedHeight(item, columnWidth: columnWidth) + 16
        }
        return map
    }
}
