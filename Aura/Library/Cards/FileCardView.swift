import SwiftUI
import UniformTypeIdentifiers

struct FileCardView: View {
    let item: Item

    var body: some View {
        if let data = item.thumbnail, let image = NSImage(data: data) {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                footer
            }
        } else {
            iconCard
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(nsImage: typeIcon)
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName ?? item.title ?? "File")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let size = sizeText {
                    Text(size).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var iconCard: some View {
        VStack(spacing: 10) {
            Image(nsImage: typeIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
            Text(item.fileName ?? item.title ?? "File")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
            if let size = sizeText {
                Text(size).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
    }

    private var typeIcon: NSImage {
        let type = item.uti.flatMap(UTType.init) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    private var sizeText: String? {
        guard let size = item.byteSize, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
