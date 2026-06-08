import SwiftUI

struct FileCardView: View {
    let item: Item

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(item.fileName ?? item.title ?? "File")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let size = item.byteSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
    }
}
