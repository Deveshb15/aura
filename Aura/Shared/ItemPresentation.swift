import Foundation

/// Presentation-only derivations shared across the notch and library so the
/// type icon and source labels are defined in exactly one place (previously
/// duplicated across NotchMiniCard / URLCardView / NudgeCardView).
extension Item {
    /// The SF Symbol that represents this item's kind.
    var typeSymbol: String {
        switch itemType {
        case .url:
            return subtype.symbol
        case .text:
            // A "link + note" capture reads as a link; plain text as text.
            return linkURL != nil ? subtype.symbol : "text.alignleft"
        case .image: return "photo"
        case .file:  return "doc.fill"
        case .color: return "paintpalette.fill"
        }
    }

    /// The *web* domain this item came from (the page it was copied from, or the
    /// link's own host). App sources have no web domain — their logo is resolved
    /// from the app name by `LogoService.logo(forAppNamed:)`.
    var sourceDomain: String? {
        if let raw = sourceURL, let host = URL(string: raw)?.host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        if let host, !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return nil
    }

    /// Human-readable "where this came from": the app name if known, else the
    /// domain.
    var sourceName: String? {
        sourceApp ?? sourceDomain
    }
}

/// Best-effort map from a capture's source *app* name to a domain, so items
/// copied from an app (which carry only an app name, not a URL) still resolve
/// a brand logo. Unmapped apps simply fall back to the type icon.
enum AppDomains {
    static func domain(for app: String?) -> String? {
        guard let key = app?.lowercased() else { return nil }
        return map[key]
    }

    private static let map: [String: String] = [
        "slack": "slack.com",
        "brave browser": "brave.com",
        "google chrome": "google.com", "chrome": "google.com",
        "safari": "apple.com",
        "arc": "arc.net",
        "notion": "notion.so",
        "firefox": "mozilla.org",
        "discord": "discord.com",
        "telegram": "telegram.org",
        "whatsapp": "whatsapp.com",
        "spotify": "spotify.com",
        "microsoft edge": "microsoft.com",
        "linear": "linear.app",
        "figma": "figma.com",
        "x": "x.com", "twitter": "x.com",
        "cursor": "cursor.com",
        "obsidian": "obsidian.md",
        "visual studio code": "code.visualstudio.com", "code": "code.visualstudio.com",
        "messages": "apple.com", "mail": "apple.com", "notes": "apple.com",
        "zoom": "zoom.us", "zoom.us": "zoom.us",
        "iterm2": "iterm2.com",
    ]
}

extension URLSubtype {
    /// SF Symbol for a URL subtype (used by both type badges and card icons).
    var symbol: String {
        switch self {
        case .youtube, .vimeo: return "play.rectangle.fill"
        case .github:          return "chevron.left.forwardslash.chevron.right"
        case .twitter:         return "at"
        case .article, .generic: return "link"
        }
    }
}
