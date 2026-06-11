import SwiftUI

struct TextCardView: View {
    let item: Item
    var heroURL: URL? = nil
    var faviconURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.textContent ?? "")
                .font(.system(size: 15))
                .foregroundStyle(AuraTheme.textPrimary)
                .lineSpacing(2)
                .lineLimit(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let link = item.linkURL {
                LinkEmbedView(item: item, url: link, heroURL: heroURL, faviconURL: faviconURL)
            }
        }
        .padding(20)
    }
}

/// Compact link preview shown inside a text card whose content embeds a URL
/// ("link + note" captures) — hero image when the Open Graph fetch found one,
/// then favicon + title + host.
private struct LinkEmbedView: View {
    let item: Item
    let url: URL
    let heroURL: URL?
    let faviconURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = DiskImage.load(heroURL) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    if item.subtype.isVideo { playBadge }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                faviconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.ogTitle ?? item.host ?? url.absoluteString)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(item.host ?? url.host ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .background(AuraTheme.surfaceHover)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AuraTheme.hairline))
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.6), in: Circle())
            .padding(6)
    }

    @ViewBuilder private var faviconView: some View {
        if let favicon = DiskImage.load(faviconURL) {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }
}
