import Foundation

/// Estimated card heights for the Pinterest-style masonry. `MasonryLayout` uses
/// these to pack columns (and as the render height for non-text cards, which have
/// no determinate height under a width-only proposal). Text cards self-size and
/// only use this as a floor.
enum MasonryColumnizer {
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
