import SwiftUI

/// The bento / masonry grid. Computes a column count from the available width
/// and renders one LazyVStack per column for lazy materialization. The grid is
/// transparent so the window's dark canvas shows through.
struct BentoGridView: View {
    let items: [Item]

    private let outer: CGFloat = 32   // matches the hero/tab horizontal margin
    private let gap: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let avail = max(0, geo.size.width - outer * 2)
            let columnCount = max(2, min(5, Int(avail / 300)))
            let columnWidth = max(120, (avail - gap * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            let buckets = MasonryColumnizer.columns(items: items, count: columnCount, columnWidth: columnWidth)

            ScrollView {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                        LazyVStack(spacing: gap) {
                            ForEach(bucket) { item in
                                CardView(item: item, columnWidth: columnWidth)
                                    .frame(width: columnWidth)
                            }
                        }
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
