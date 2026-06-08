import SwiftUI

/// The library's category filter. Built-in tabs map to predicates over item
/// type (user collections come in a later phase).
enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, links, images, text, files

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .links: return "Links"
        case .images: return "Images"
        case .text: return "Text"
        case .files: return "Files"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .links: return "link"
        case .images: return "photo"
        case .text: return "text.alignleft"
        case .files: return "doc"
        }
    }

    func matches(_ item: Item) -> Bool {
        switch self {
        case .all: return true
        case .links: return item.itemType == .url
        case .images: return item.itemType == .image
        case .text: return item.itemType == .text || item.itemType == .color
        case .files: return item.itemType == .file
        }
    }
}

struct CategoryTabBar: View {
    @Binding var selection: LibraryFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { filter in
                let isSelected = filter == selection
                Button {
                    selection = filter
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filter.symbol).font(.system(size: 11))
                        Text(filter.label).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.gray.opacity(0.12)),
                        in: Capsule()
                    )
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
