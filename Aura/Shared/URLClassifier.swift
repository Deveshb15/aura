import Foundation

/// Coarse URL classification used to choose a card style.
enum URLClassifier {
    static func subtype(for url: URL) -> URLSubtype {
        let host = url.host?.lowercased() ?? ""
        if host.contains("youtube.") || host == "youtu.be" {
            return .youtube
        }
        if host == "vimeo.com" || host.hasSuffix(".vimeo.com") || host == "player.vimeo.com" {
            return .vimeo
        }
        if host == "twitter.com" || host == "x.com" || host.hasSuffix(".twitter.com") || host.hasSuffix(".x.com") {
            return .twitter
        }
        if host.contains("github.com") {
            return .github
        }
        return .article
    }
}
