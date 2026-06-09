import SwiftUI
import UniformTypeIdentifiers

/// Content-type filter for the library, matching the redesigned tab bar
/// (Writing / Images / Links / Music / Videos).
enum ContentTab: String, CaseIterable, Identifiable {
    case all, writing, images, links, music, videos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:     return "All"
        case .writing: return "Text"
        case .images:  return "Images"
        case .links:   return "Links"
        case .music:   return "Music"
        case .videos:  return "Videos"
        }
    }

    /// Classify an item at display time — derived from `itemType` + `host`, so it
    /// works for existing rows without a DB migration. Never returns `.all`
    /// (that tab is a catch-all handled by the caller).
    static func of(_ item: Item) -> ContentTab {
        switch item.itemType {
        case .text, .color:
            return .writing
        case .image:
            return .images
        case .file:
            return isImageUTI(item.uti) ? .images : .links
        case .url:
            let host = (item.host ?? URL(string: item.textContent ?? "")?.host ?? "").lowercased()
            if host.contains("youtube.") || host == "youtu.be" || host.contains("vimeo.") {
                return .videos
            }
            if host.contains("spotify") || host.contains("music.apple.com")
                || host.contains("soundcloud") || host.contains("bandcamp") {
                return .music
            }
            return .links
        }
    }

    private static func isImageUTI(_ uti: String?) -> Bool {
        guard let uti, let type = UTType(uti) else { return false }
        return type.conforms(to: .image)
    }
}

/// Horizontal content-type tab bar. Active tab = solid white pill with black
/// text; inactive tabs = no background, muted text — exactly as in the mockup.
struct ContentTypeTabBar: View {
    @Binding var selection: ContentTab

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
        return Button {
            selection = tab
        } label: {
            Text(tab.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.black : AuraTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule().fill(AuraTheme.activePill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
