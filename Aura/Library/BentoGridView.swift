import SwiftUI

/// The bento / masonry grid. Computes a column count from the available width
/// and renders one LazyVStack per column for lazy materialization.
struct BentoGridView: View {
    let items: [Item]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 16
            let columnCount = max(2, min(5, Int(geo.size.width / 260)))
            let totalSpacing = spacing * CGFloat(columnCount + 1)
            let columnWidth = max(120, (geo.size.width - totalSpacing) / CGFloat(columnCount))
            let buckets = MasonryColumnizer.columns(items: items, count: columnCount, columnWidth: columnWidth)

            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                        LazyVStack(spacing: spacing) {
                            ForEach(bucket) { item in
                                CardView(item: item)
                                    .frame(width: columnWidth)
                            }
                        }
                    }
                }
                .padding(spacing)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
