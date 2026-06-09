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

    private let radius: CGFloat = 18

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(AuraTheme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .topTrailing) { actionBar }
            .overlay(alignment: .bottomTrailing) { if hovering { ResizeGrip() } }
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.18), radius: hovering ? 14 : 6, y: 4)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
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
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { delete() }
            }
            .help(item.canOpen ? openHelp : "Click to copy")
    }

    private func delete() {
        withAnimation(.easeOut(duration: 0.18)) { store.delete(item) }
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
                CardActionButton(systemName: "xmark", help: "Delete", destructive: true) { delete() }
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

/// A small dark circular icon button used in the card hover action bar.
struct CardActionButton: View {
    let systemName: String
    let help: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(destructive ? AuraTheme.destructive : Color.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Decorative bottom-right resize grip (three diagonal hatches), matching the
/// mockup. Purely cosmetic — the masonry grid stays automatic.
struct ResizeGrip: View {
    var body: some View {
        Canvas { ctx, size in
            let shading = GraphicsContext.Shading.color(.white.opacity(0.22))
            for i in 0..<3 {
                let offset = CGFloat(i) * 4 + 1
                var path = Path()
                path.move(to: CGPoint(x: size.width - offset, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height - offset))
                ctx.stroke(path, with: shading, lineWidth: 1.2)
            }
        }
        .frame(width: 11, height: 11)
        .padding(9)
        .allowsHitTesting(false)
    }
}
