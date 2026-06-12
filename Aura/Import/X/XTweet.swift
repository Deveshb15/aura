import Foundation

/// One bookmarked tweet, as captured by the browser extension and forwarded
/// through the native-messaging host. Media arrives as URLs (twimg, no auth);
/// the app downloads the bytes itself.
struct XTweet: Decodable {
    var tweetId: String?
    var tweetUrl: String
    var authorName: String?
    var authorHandle: String?          // already "@handle"
    var authorAvatarUrl: String?
    var caption: String?
    var imageUrls: [String]?
    var videoUrl: String?
    var posterUrl: String?
    var quoted: XQuoted?

    /// The canonical dedup key: a tweet's numeric status id (stable across
    /// handle renames and twitter.com↔x.com).
    var statusId: String? {
        if let tweetId, !tweetId.isEmpty { return tweetId }
        if let range = tweetUrl.range(of: "/status/") {
            let digits = tweetUrl[range.upperBound...].prefix { $0.isNumber }
            return digits.isEmpty ? nil : String(digits)
        }
        return nil
    }

    /// What to show as the card's hero: the first photo, else the video poster.
    var bestImageURL: String? {
        if let first = imageUrls?.first(where: { !$0.isEmpty }) { return first }
        if let posterUrl, !posterUrl.isEmpty { return posterUrl }
        return nil
    }
}

struct XQuoted: Decodable {
    var authorName: String?
    var authorHandle: String?
    var caption: String?
}

struct XSaveOutcome {
    var ok: Bool
    var duplicate: Bool
}

/// Maps a captured tweet onto Aura's `Item` shape, reusing the `.url` / `.twitter`
/// columns so X bookmarks render and search like any other saved link.
enum XBookmarkMapper {
    static func makeItem(from t: XTweet, createdAt: Date) -> Item {
        var item = Item(type: .url, createdAt: createdAt, updatedAt: createdAt)
        item.textContent = t.tweetUrl
        item.host = "x.com"
        item.urlSubtype = URLSubtype.twitter.rawValue
        item.sourceApp = "X Bookmarks"

        let author = authorLine(t)
        let caption = (t.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = caption.isEmpty ? (author.isEmpty ? "Tweet" : author) : snippet(caption)
        item.ogTitle = author.isEmpty ? nil : author
        item.ogDescription = caption.isEmpty ? nil : caption

        // Feed the caption (+ any quoted-tweet text) into the FTS corpus so
        // bookmarked tweets are searchable by their words.
        var extracted = caption
        if let q = t.quoted, let qc = q.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !qc.isEmpty {
            let prefix = extracted.isEmpty ? "" : "\n"
            extracted += "\(prefix)↳ \(q.authorHandle ?? "") \(qc)".trimmingCharacters(in: .whitespaces)
        }
        item.extractedText = extracted.isEmpty ? nil : extracted
        return item
    }

    static func authorLine(_ t: XTweet) -> String {
        let name = (t.authorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = (t.authorHandle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch (name.isEmpty, handle.isEmpty) {
        case (false, false): return "\(name) (\(handle))"
        case (false, true):  return name
        case (true, false):  return handle
        case (true, true):   return ""
        }
    }

    private static func snippet(_ s: String) -> String {
        let firstLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return String(firstLine.prefix(100))
    }
}
