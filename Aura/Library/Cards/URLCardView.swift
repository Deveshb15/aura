import SwiftUI

struct URLCardView: View {
    let item: Item
    let heroURL: URL?
    let faviconURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            footer
        }
    }

    // MARK: - Hero

    @ViewBuilder private var hero: some View {
        let heroURL = heroURL
        AsyncCardImage(id: heroURL?.path ?? "none-\(item.id)", load: { DiskImage.load(heroURL) }) { image in
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: heroHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                if item.subtype.isVideo { playBadge }
            }
        } placeholder: {
            ZStack {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
        }
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.6), in: Circle())
            .padding(8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            faviconView
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? item.host ?? "Link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    @ViewBuilder private var faviconView: some View {
        let faviconURL = faviconURL
        AsyncCardImage(id: faviconURL?.path ?? "none-\(item.id)", load: { DiskImage.load(faviconURL) }) { favicon in
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } placeholder: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }

    // MARK: - Style

    /// For videos, prefer the channel name (captured into `ogDescription`) over
    /// the bare host — "Marques Brownlee" reads better than "www.youtube.com",
    /// and it's the same text search now matches on. Falls back to the host.
    private var subtitle: String {
        if item.subtype.isVideo, let channel = item.ogDescription, !channel.isEmpty {
            return channel
        }
        return item.host ?? ""
    }

    private var heroHeight: CGFloat { item.subtype == .youtube ? 132 : 120 }

    private var icon: String {
        switch item.subtype {
        case .youtube: return "play.rectangle.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .twitter: return "at"
        default: return "globe"
        }
    }

    private var gradient: [Color] {
        switch item.subtype {
        case .youtube: return [.red, .orange]
        case .github: return [Color(white: 0.3), Color(white: 0.1)]
        case .twitter: return [.blue, .cyan]
        default: return [.indigo, .purple]
        }
    }
}
