import Foundation

/// Pure column-balancing for a Pinterest-style masonry: each item goes into the
/// currently shortest column, using an estimated height. Lazy-friendly because
/// the result is just `[[Item]]` rendered into side-by-side LazyVStacks.
enum MasonryColumnizer {
    static func columns(items: [Item], count: Int, columnWidth: CGFloat) -> [[Item]] {
        guard count > 0 else { return [items] }
        var buckets = Array(repeating: [Item](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)

        for item in items {
            let height = estimatedHeight(item, columnWidth: columnWidth)
            var shortest = 0
            for index in 1..<count where heights[index] < heights[shortest] {
                shortest = index
            }
            buckets[shortest].append(item)
            heights[shortest] += height + 16
        }
        return buckets
    }

    static func estimatedHeight(_ item: Item, columnWidth: CGFloat) -> CGFloat {
        switch item.itemType {
        case .image:
            if let w = item.thumbWidth, let h = item.thumbHeight, w > 0 {
                return columnWidth * CGFloat(h) / CGFloat(w)
            }
            return columnWidth * 0.72
        case .url:
            return 188
        case .color:
            return 168
        case .file:
            if let w = item.thumbWidth, let h = item.thumbHeight, w > 0 {
                return columnWidth * CGFloat(h) / CGFloat(w) + 52
            }
            return 150
        case .text:
            let length = item.textContent?.count ?? 0
            return min(340, 110 + CGFloat(length) / 2.6)
        }
    }
}
