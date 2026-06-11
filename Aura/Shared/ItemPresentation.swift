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

    /// The web domain this item came from, if any — drives the source logo.
    /// Derived from the page it was copied from, or the link's own host. Never
    /// the source *app* name (e.g. "Safari"), which is not a domain.
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
