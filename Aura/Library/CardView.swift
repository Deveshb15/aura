import SwiftUI

/// Shared card chrome that dispatches to the right per-type card. Click copies
/// the item back to the clipboard; the card is also draggable out of the vault.
struct CardView: View {
    let item: Item
    @Environment(DataStore.self) private var store
    @State private var hovering = false

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.07), radius: hovering ? 12 : 5, y: 3)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture { store.copyToClipboard(item) }
            .contextMenu {
                Button("Copy") { store.copyToClipboard(item) }
                Button("Delete", role: .destructive) { store.delete(item) }
            }
            .help("Click to copy")
    }

    @ViewBuilder private var cardContent: some View {
        switch item.itemType {
        case .url: URLCardView(item: item)
        case .image: ImageCardView(item: item, assetURL: store.assetURL(for: item))
        case .color: ColorCardView(item: item)
        case .file: FileCardView(item: item)
        case .text: TextCardView(item: item)
        }
    }
}
