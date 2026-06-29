import SwiftUI

/// The expanded notch content: a header plus a horizontal strip of recently
/// saved items, or a drop hint when empty.
struct NotchExpandedView: View {
    let dataStore: DataStore
    let isDropTargeted: Bool
    let onAddNote: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Carpet", systemImage: "tray.full.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AuraTheme.textPrimary)
                Spacer()
                Text(isDropTargeted ? "Drop to save" : "\(dataStore.recentItems.count) saved")
                    .font(.system(size: 10))
                    .foregroundStyle(isDropTargeted ? Color.green : AuraTheme.textSecondary)
                addNoteButton
            }

            if dataStore.recentItems.isEmpty {
                dropHint
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dataStore.recentItems) { item in
                            NotchMiniCard(item: item, dataStore: dataStore)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                openAppButton
            }
            // Extra breathing room above the button (on top of the VStack's 8pt).
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Brings the full library window forward — an explicit affordance alongside
    /// the implicit "click the notch chrome to open" gesture.
    private var openAppButton: some View {
        Button(action: onOpenLibrary) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward.app").font(.system(size: 12, weight: .semibold))
                Text("Open App").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AuraTheme.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(AuraTheme.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(AuraTheme.hairline))
        }
        .buttonStyle(.plain)
        .help("Open the Carpet library window")
    }

    /// Opens the quick-note composer (same surface as the ⌃⌘N hotkey).
    private var addNoteButton: some View {
        Button(action: onAddNote) {
            HStack(spacing: 3) {
                Image(systemName: "square.and.pencil").font(.system(size: 10, weight: .semibold))
                Text("Note").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(AuraTheme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AuraTheme.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(AuraTheme.hairlineStrong))
        }
        .buttonStyle(.plain)
        .help("New note")
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(isDropTargeted ? AuraTheme.textSecondary : AuraTheme.textTertiary)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 16))
                    Text("Drop files, links, or images").font(.system(size: 11))
                }
                .foregroundStyle(AuraTheme.textSecondary)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 118)
    }
}

/// A small recent-item tile inside the notch. Tap copies/opens it; hovering
/// blurs the preview and reveals explicit Copy / Open buttons.
struct NotchMiniCard: View {
    let item: Item
    let dataStore: DataStore
    @State private var hovering = false

    var body: some View {
        ZStack {
            content
                .frame(width: 96, height: 110)
                .clipped()
                // Slightly over-scale while blurring so the soft edge stays
                // outside the rounded clip instead of fading to the card bg.
                .blur(radius: hovering ? 7 : 0)
                .scaleEffect(hovering ? 1.06 : 1)

            if hovering {
                Color.black.opacity(0.5)
                HStack(spacing: 8) {
                    NotchMiniButton(systemName: "doc.on.doc", help: "Copy") {
                        dataStore.copyToClipboard(item)
                    }
                    if item.canOpen {
                        NotchMiniButton(systemName: "arrow.up.forward.app", help: "Open") {
                            dataStore.open(item)
                        }
                    }
                }
            }
        }
        .frame(width: 96, height: 110)
        .overlay(alignment: .bottomTrailing) { if !hovering { timestampBadge } }
        .background(AuraTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AuraTheme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { dataStore.primaryAction(item) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(item.canOpen ? "Click to open" : "Click to copy")
    }

    private var timestampBadge: some View {
        Text(RelativeTime.compact(item.createdAt))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(5)
    }

    @ViewBuilder private var content: some View {
        switch item.itemType {
        case .image:
            let id = item.id, data = item.thumbnail
            AsyncCardImage(id: id, load: { data.flatMap { ThumbnailCache.image(id: id, data: $0) } }) { image in
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                centeredIcon("photo", caption: nil)
            }
        case .url:
            let heroURL = dataStore.fileURL(forRelativePath: item.ogImagePath)
            AsyncCardImage(id: heroURL?.path ?? "none-\(item.id)", load: { DiskImage.load(heroURL) }) { image in
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                centeredIcon(item.subtype.symbol, caption: item.host ?? "Link")
            }
        case .color:
            Color(hex: item.colorHex ?? "") ?? Color.gray
        case .file:
            let id = item.id, data = item.thumbnail
            AsyncCardImage(id: id, load: { data.flatMap { ThumbnailCache.image(id: id, data: $0) } }) { image in
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                centeredIcon("doc.fill", caption: item.fileName ?? "File")
            }
        case .text:
            Text(item.textContent ?? "")
                .font(.system(size: 10))
                .foregroundStyle(AuraTheme.textPrimary)
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func centeredIcon(_ name: String, caption: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: name)
                .font(.system(size: 18))
                .foregroundStyle(AuraTheme.textSecondary)
            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(AuraTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

/// A compact circular action button shown over a blurred notch tile on hover.
private struct NotchMiniButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
