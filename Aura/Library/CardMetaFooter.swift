import SwiftUI

/// The shared bottom row on every library card: a type icon, the source
/// (logo + name) where it isn't already implied by the card body, and a
/// relative timestamp. Rendered once by `CardView` so it's consistent across
/// every item type.
struct CardMetaFooter: View {
    let item: Item
    @Environment(DataStore.self) private var store

    /// URL / link-text cards already show a favicon + host in their body, so
    /// repeating the source there would be redundant — show type + time only.
    private var showsSource: Bool {
        switch item.itemType {
        case .url: return false
        case .text: return item.linkURL == nil
        default: return true
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.typeSymbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14)

            if showsSource {
                SourceBadge(item: item,
                            faviconURL: store.fileURL(forRelativePath: item.faviconPath))
            }

            Spacer(minLength: 4)

            Text(RelativeTime.medium(item.createdAt))
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(AuraTheme.textTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(AuraTheme.hairline).frame(height: 0.5)
        }
    }
}
