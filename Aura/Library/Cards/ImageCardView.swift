import SwiftUI

struct ImageCardView: View {
    let item: Item
    let assetURL: URL?

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadedImage: NSImage? {
        if let data = item.thumbnail, let image = NSImage(data: data) {
            return image
        }
        if let assetURL {
            return NSImage(contentsOf: assetURL)
        }
        return nil
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
        }
        .frame(height: 160)
    }
}
