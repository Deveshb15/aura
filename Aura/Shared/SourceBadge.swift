import SwiftUI

/// A small logo for a web domain. Paints a synchronous fallback immediately
/// (stored favicon → SF type icon) so it's never blank, then asynchronously
/// resolves the domain's logo via `LogoService` and cross-fades it in.
struct AsyncLogo: View {
    let domain: String?
    var appName: String? = nil
    var fallbackFavicon: URL? = nil
    var fallbackSymbol: String = "globe"
    var size: CGFloat = 16

    @State private var resolved: NSImage?

    var body: some View {
        ZStack {
            if let resolved {
                Image(nsImage: resolved)
                    .resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else if let favicon = DiskImage.load(fallbackFavicon) {
                Image(nsImage: favicon)
                    .resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .task(id: "\(domain ?? "")|\(appName ?? "")") {
            resolved = nil
            let image: NSImage?
            if let domain {
                image = await LogoService.shared.logo(for: domain)
            } else if let appName {
                image = await LogoService.shared.logo(forAppNamed: appName)
            } else {
                image = nil
            }
            withAnimation(.easeOut(duration: 0.2)) { resolved = image }
        }
    }
}

/// Source provenance chip: the domain/app logo plus its name. Used in the
/// library card meta footer.
struct SourceBadge: View {
    let item: Item
    var faviconURL: URL? = nil

    var body: some View {
        if let name = item.sourceName {
            HStack(spacing: 5) {
                AsyncLogo(domain: item.sourceDomain,
                          appName: item.sourceApp,
                          fallbackFavicon: faviconURL,
                          fallbackSymbol: item.typeSymbol,
                          size: 14)
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
