import SwiftUI

/// Shared card chrome that dispatches to the right per-type card.
/// Primary click opens the item (link → browser, file/image → default app);
/// text & colors copy. A hover action bar adds explicit Copy / Open buttons,
/// and the context menu has the full set.
struct CardView: View {
    let item: Item
    @Environment(DataStore.self) private var store
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) { actionBar }
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.07), radius: hovering ? 12 : 5, y: 3)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .dragOut(item: item, assetURL: store.assetURL(for: item))
            .onHover { hovering = $0 }
            .onTapGesture { store.primaryAction(item) }
            .contextMenu {
                if item.canOpen {
                    Button("Open", systemImage: "arrow.up.forward.app") { store.open(item) }
                }
                Button("Copy", systemImage: "doc.on.doc") { store.copyToClipboard(item) }
                if item.itemType == .file || item.itemType == .image {
                    Button("Reveal in Finder", systemImage: "folder") { store.revealInFinder(item) }
                }
                Menu("Add to Collection") {
                    if store.collections.isEmpty {
                        Text("No collections yet")
                    } else {
                        ForEach(store.collections) { collection in
                            Button {
                                store.setCollection(item, to: collection.id)
                            } label: {
                                if item.collectionId == collection.id {
                                    Label(collection.name, systemImage: "checkmark")
                                } else {
                                    Text(collection.name)
                                }
                            }
                        }
                    }
                    if item.collectionId != nil {
                        Divider()
                        Button("Remove from Collection") { store.setCollection(item, to: nil) }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item) }
            }
            .help(item.canOpen ? openHelp : "Click to copy")
    }

    @ViewBuilder private var actionBar: some View {
        if hovering {
            HStack(spacing: 6) {
                CardActionButton(systemName: copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                    store.copyToClipboard(item)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_100_000_000)
                        copied = false
                    }
                }
                if item.canOpen {
                    CardActionButton(systemName: "arrow.up.forward.app", help: openHelp) {
                        store.open(item)
                    }
                }
            }
            .padding(8)
            .transition(.opacity)
        }
    }

    private var openHelp: String {
        switch item.itemType {
        case .url: return "Open link"
        case .file: return "Open file"
        case .image: return "Open image"
        default: return "Open"
        }
    }

    @ViewBuilder private var cardContent: some View {
        switch item.itemType {
        case .url:
            URLCardView(item: item,
                        heroURL: store.fileURL(forRelativePath: item.ogImagePath),
                        faviconURL: store.fileURL(forRelativePath: item.faviconPath))
        case .image: ImageCardView(item: item, assetURL: store.assetURL(for: item))
        case .color: ColorCardView(item: item)
        case .file: FileCardView(item: item)
        case .text: TextCardView(item: item)
        }
    }
}

private extension View {
    /// Makes a card draggable OUT of the vault: images/files drag as a file URL
    /// (drop into Finder or another app), links as a URL, text/colors as text.
    @ViewBuilder
    func dragOut(item: Item, assetURL: URL?) -> some View {
        switch item.itemType {
        case .image, .file:
            if let assetURL { self.draggable(assetURL) } else { self }
        case .url:
            if let url = URL(string: item.textContent ?? "") { self.draggable(url) } else { self }
        case .text, .color:
            self.draggable(item.textContent ?? "")
        }
    }
}

/// A small circular icon button used in the card hover action bar.
struct CardActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
