import SwiftUI

/// The expanded notch content: a header plus a horizontal strip of recently
/// saved items, or a drop hint when empty.
struct NotchExpandedView: View {
    let dataStore: DataStore
    let isDropTargeted: Bool
    let onAddNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Aura", systemImage: "tray.full.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(isDropTargeted ? "Drop to save" : "\(dataStore.recentItems.count) saved")
                    .font(.system(size: 10))
                    .foregroundStyle(isDropTargeted ? Color.green : Color.white.opacity(0.5))
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
        }
    }

    /// Opens the quick-note composer (same surface as the ⌃⌘N hotkey).
    private var addNoteButton: some View {
        Button(action: onAddNote) {
            HStack(spacing: 3) {
                Image(systemName: "square.and.pencil").font(.system(size: 10, weight: .semibold))
                Text("Note").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("New note")
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(.white.opacity(isDropTargeted ? 0.7 : 0.25))
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 16))
                    Text("Drop files, links, or images").font(.system(size: 11))
                }
                .foregroundStyle(.white.opacity(0.5))
            )
            .frame(maxWidth: .infinity)
            .frame(height: 118)
    }
}

/// A small recent-item tile inside the notch. Tap copies it back to the clipboard.
struct NotchMiniCard: View {
    let item: Item
    let dataStore: DataStore

    var body: some View {
        content
            .frame(width: 96, height: 110)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { dataStore.primaryAction(item) }
            .help(item.canOpen ? "Click to open" : "Click to copy")
    }

    @ViewBuilder private var content: some View {
        switch item.itemType {
        case .image:
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                centeredIcon("photo", caption: nil)
            }
        case .url:
            if let image = DiskImage.load(dataStore.fileURL(forRelativePath: item.ogImagePath)) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                centeredIcon(urlIcon, caption: item.host ?? "Link")
            }
        case .color:
            Color(hex: item.colorHex ?? "") ?? Color.gray
        case .file:
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                centeredIcon("doc.fill", caption: item.fileName ?? "File")
            }
        case .text:
            Text(item.textContent ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func centeredIcon(_ name: String, caption: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: name)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.85))
            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var urlIcon: String {
        switch item.subtype {
        case .youtube: return "play.rectangle.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .twitter: return "at"
        default: return "link"
        }
    }
}
