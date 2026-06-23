import SwiftUI
import UniformTypeIdentifiers

/// Content-type filter for the library, matching the redesigned tab bar
/// (Notes / Text / Images / Documents / Links / Music / Videos).
enum ContentTab: String, CaseIterable, Identifiable {
    case all, notes, writing, images, documents, links, music, videos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .notes:     return "Notes"
        case .writing:   return "Text"
        case .images:    return "Images"
        case .documents: return "Documents"
        case .links:     return "Links"
        case .music:     return "Music"
        case .videos:    return "Videos"
        }
    }

    /// Tab glyph (SF Symbols), a clean cohesive set.
    var symbol: String {
        switch self {
        case .all:       return "square.grid.2x2.fill"
        case .notes:     return "note.text"
        case .writing:   return "text.alignleft"
        case .images:    return "photo.fill"
        case .documents: return "doc.text"
        case .links:     return "link"
        case .music:     return "music.note"
        case .videos:    return "play.rectangle.fill"
        }
    }

    /// Every tab an item belongs to, derived at display time from `itemType` +
    /// `host` (and, for notes, the source app), so it works for existing rows
    /// without a DB migration. A note written in Carpet lands in `.notes`;
    /// other text captures land in `.writing` — and either, if it embeds a link,
    /// also counts toward its link tab. Never contains `.all` (that tab is a
    /// catch-all handled by the caller).
    static func tabs(for item: Item) -> Set<ContentTab> {
        switch item.itemType {
        case .text:
            var tabs: Set<ContentTab> = [item.isCarpetNote ? .notes : .writing]
            if let host = (item.host ?? item.linkURL?.host)?.lowercased() {
                tabs.insert(linkTab(forHost: host))
            }
            return tabs
        case .color:
            return [.writing]
        case .image:
            return [.images]
        case .file:
            // Files are routed by UTI: images join the photo grid, audio/video
            // join Music/Videos, and everything else (PDFs, Word, text, code,
            // archives…) lands in Documents — never the catch-all Links tab.
            if isImageUTI(item.uti) { return [.images] }
            if conformsTo(item.uti, .audio) { return [.music] }
            if conformsTo(item.uti, .audiovisualContent) { return [.videos] }
            return [.documents]
        case .url:
            let host = (item.host ?? URL(string: item.textContent ?? "")?.host ?? "").lowercased()
            return [linkTab(forHost: host)]
        }
    }

    /// Per-tab item counts over a set, computed in a single pass. `.all` maps to
    /// the total; every other tab to how many items fall under it. An item can
    /// count toward more than one tab (e.g. a note that embeds a link).
    static func counts(for items: [Item]) -> [ContentTab: Int] {
        var counts: [ContentTab: Int] = [.all: items.count]
        for item in items {
            for tab in tabs(for: item) {
                counts[tab, default: 0] += 1
            }
        }
        return counts
    }

    private static func linkTab(forHost host: String) -> ContentTab {
        if host.contains("youtube.") || host == "youtu.be" || host.contains("vimeo.") {
            return .videos
        }
        if host.contains("spotify") || host.contains("music.apple.com")
            || host.contains("soundcloud") || host.contains("bandcamp") {
            return .music
        }
        return .links
    }

    private static func isImageUTI(_ uti: String?) -> Bool {
        conformsTo(uti, .image)
    }

    private static func conformsTo(_ uti: String?, _ parent: UTType) -> Bool {
        guard let uti, let type = UTType(uti) else { return false }
        return type.conforms(to: parent)
    }
}

/// Horizontal content-type tab bar. Active tab = solid white pill with black
/// text; inactive tabs = no background, muted text — exactly as in the mockup.
struct ContentTypeTabBar: View {
    @Binding var selection: ContentTab
    /// Per-tab item counts shown as a muted badge after each label. Tabs with a
    /// zero count render without a badge. See `ContentTab.counts(for:)`.
    var counts: [ContentTab: Int] = [:]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ContentTab.allCases) { tab in
                pill(tab)
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ tab: ContentTab) -> some View {
        let isSelected = selection == tab
        let count = counts[tab] ?? 0
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .imageScale(.medium)
                Text(tab.label)
                    .font(.system(size: 14, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected
                            ? AuraTheme.activePillLabel.opacity(0.5)
                            : AuraTheme.textTertiary)
                }
            }
            .foregroundStyle(isSelected ? AuraTheme.activePillLabel : AuraTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(AuraTheme.activePill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}
