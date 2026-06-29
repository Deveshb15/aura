import SwiftUI

struct ImageCardView: View {
    let item: Item
    let assetURL: URL?

    var body: some View {
        let id = item.id
        let data = item.thumbnail
        let assetURL = assetURL
        return AsyncCardImage(id: id, load: {
            // Prefer the small inline thumbnail; fall back to the on-disk
            // original only when it's missing (decode happens off the main thread).
            if let data, let image = ThumbnailCache.image(id: id, data: data) { return image }
            return DiskImage.load(assetURL)
        }) { image in
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } placeholder: {
            placeholder
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
        }
        .frame(height: 160)
    }
}
