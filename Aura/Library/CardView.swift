import SwiftUI

/// Shared card chrome that dispatches to the right per-type card.
/// Primary click opens the item (link → browser, file/image → default app);
/// text & colors copy. A hover action bar adds explicit Copy / Open buttons,
/// and the context menu has the full set.
struct CardView: View {
    let item: Item
    /// The masonry column width, threaded down to size the in-place text editor.
    var columnWidth: CGFloat = 0
    @Environment(DataStore.self) private var store
    @State private var hovering = false
    @State private var copied = false

    private let radius: CGFloat = 18
    /// Horizontal padding inside a text card (`TextCardView` pads 20 each side).
    private let textPadding: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            cardContent
            CardMetaFooter(item: item)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Height hint for MasonryLayout. Text/url/color have determinate,
            // load-independent heights, so the layout MEASURES the whole card
            // (body + the shared meta footer) — this is what keeps cards from
            // overlapping. Image/file depend on an async thumbnail, so measuring
            // would reflow on load; they use the aspect-correct estimate (which
            // includes the meta footer) instead.
            .layoutValue(key: CardHeightHintKey.self,
                         value: CardHeightHint(
                            estimate: MasonryColumnizer.estimatedHeight(item, columnWidth: columnWidth),
                            measuresHeight: item.itemType != .image && item.itemType != .file))
            .background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(AuraTheme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .topTrailing) { actionBar }
            .shadow(color: AuraTheme.shadow.opacity(hovering ? 1 : 0.5), radius: hovering ? 14 : 6, y: 4)
            // Text cards are the only ones that can host a live NSTextView (while
            // being edited). A scale TRANSFORM on a card hosting an AppKit view can
            // invert its layer geometry (the footer-flip bug), so text cards skip
            // the hover scale — they keep the shadow lift, just not the transform.
            .scaleEffect(item.itemType == .text ? 1 : (hovering ? 1.012 : 1))
            .animation(.easeOut(duration: 0.16), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .dragOut(item: item, assetURL: store.assetURL(for: item))
            .onHover { hovering = $0 }
            // Text cards edit in place — the click must reach the editor, so we
            // don't attach a primary-action tap (or drag-out) for them.
            .primaryTap(for: item) { store.primaryAction(item) }
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
            .help(helpText)
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
                CardActionButton(systemName: "xmark", help: "Delete") { delete() }
            }
            .padding(8)
            .transition(.opacity)
        }
    }

    /// Text cards edit in place on click; everything else opens or copies.
    private var helpText: String {
        if item.itemType == .text { return "Click to edit" }
        return item.canOpen ? openHelp : "Click to copy"
    }

    private var openHelp: String {
        switch item.itemType {
        case .url, .text: return "Open link"
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
        case .text: TextCardView(item: item,
                                 heroURL: store.fileURL(forRelativePath: item.ogImagePath),
                                 faviconURL: store.fileURL(forRelativePath: item.faviconPath),
                                 contentWidth: columnWidth - textPadding * 2)
        }
    }
}

private extension View {
    /// Makes a card draggable OUT of the vault: images/files drag as a file URL
    /// (drop into Finder or another app), links as a URL, colors as text. Text
    /// cards are intentionally excluded — they edit in place, so a click-drag
    /// must select text rather than start a drag.
    @ViewBuilder
    func dragOut(item: Item, assetURL: URL?) -> some View {
        switch item.itemType {
        case .image, .file:
            if let assetURL { self.draggable(assetURL) } else { self }
        case .url:
            if let url = URL(string: item.textContent ?? "") { self.draggable(url) } else { self }
        case .color:
            self.draggable(item.textContent ?? "")
        case .text:
            self
        }
    }

    /// Attaches a primary-click action for every type except text. Text cards
    /// omit it so clicks fall through to the in-place editor.
    @ViewBuilder
    func primaryTap(for item: Item, _ action: @escaping () -> Void) -> some View {
        if item.itemType == .text {
            self
        } else {
            self.onTapGesture(perform: action)
        }
    }
}

/// A small dark circular icon button used in the card hover action bar.
struct CardActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

