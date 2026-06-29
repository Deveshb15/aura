import Foundation

/// Estimated card heights for the Pinterest-style masonry. `MasonryLayout` uses
/// these to pack columns (and as the render height for non-text cards, which have
/// no determinate height under a width-only proposal). Text cards self-size and
/// only use this as a floor.
enum MasonryColumnizer {
    /// Height of the shared `CardMetaFooter` (source + timestamp row) that
    /// `CardView` appends to EVERY card. Image and file cards are placed at their
    /// estimated height (they can't be measured without reflowing when their async
    /// thumbnail loads), so this MUST be included or they overlap the card below.
    /// A touch generous so the estimate never falls short of the real card.
    static let metaFooterHeight: CGFloat = 34

    static func estimatedHeight(_ item: Item, columnWidth: CGFloat) -> CGFloat {
        switch item.itemType {
        case .image:
            let body: CGFloat
            if let w = item.thumbWidth, let h = item.thumbHeight, w > 0 {
                body = columnWidth * CGFloat(h) / CGFloat(w)
            } else {
                body = columnWidth * 0.72
            }
            return body + metaFooterHeight
        case .file:
            if let w = item.thumbWidth, let h = item.thumbHeight, w > 0 {
                return columnWidth * CGFloat(h) / CGFloat(w) + 52 + metaFooterHeight
            }
            return 150 + metaFooterHeight
        // url / color / text are MEASURED at render (heights are load-independent),
        // so these are only a conservative floor + column-assignment hint — they
        // deliberately omit the meta footer so the floor never over-shoots the real
        // (measured) height and opens an extra gap under short cards.
        case .url:
            // Folding in the title length matters beyond a floor: the layout's
            // recompute signature keys off this estimate, so when link enrichment
            // fills in a longer (wrapping) ogTitle, the estimate changes and forces
            // a re-measure rather than leaving a stale 1-line frame.
            let titleLen = (item.ogTitle ?? item.title ?? item.host ?? "").count
            return titleLen > 38 ? 206 : 188
        case .color:
            return 168
        case .text:
            let length = item.textContent?.count ?? 0
            return min(340, 110 + CGFloat(length) / 2.6)
        }
    }
}
