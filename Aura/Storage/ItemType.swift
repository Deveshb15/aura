import Foundation

/// The kind of thing a saved item is. One `item` table row carries all of these;
/// type-specific columns are simply nil when not applicable.
enum ItemType: String, Codable, CaseIterable {
    case text
    case url
    case image
    case file
    case color
}

/// For `.url` items, a coarse classification that drives which card style to render.
enum URLSubtype: String, Codable {
    case generic
    case youtube
    case twitter
    case github
    case article
}
