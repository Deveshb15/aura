import SwiftUI

/// The shared bottom row on every library card: a type icon, the source
/// (logo + name) where it isn't already implied by the card body, and a
/// relative timestamp. Rendered once by `CardView` so it's consistent across
/// every item type.
struct CardMetaFooter: View {
    let item: Item
    @Environment(DataStore.self) private var store
    @Environment(InAppComposeLauncher.self) private var composeLauncher

    /// URL / link-text cards already show a favicon + host in their body, so
    /// repeating the source there would be redundant — show type + time only.
    private var showsSource: Bool {
        switch item.itemType {
        case .url: return false
        case .text: return item.linkURL == nil
        default: return true
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsSource {
                SourceBadge(item: item,
                            faviconURL: store.fileURL(forRelativePath: item.faviconPath))
            }

            if item.hasReminder { reminderChip }

            Spacer(minLength: 4)

            Text(RelativeTime.medium(item.createdAt))
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(AuraTheme.textTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(AuraTheme.hairline).frame(height: 0.5)
        }
    }

    /// Bell chip with the fire time. Accent while pending; muted once the
    /// reminder has fired or its time has passed. Tapping opens the editor.
    @ViewBuilder private var reminderChip: some View {
        if let fireDate = item.reminderAt {
            let past = item.reminderDelivered == true || fireDate < Date()
            Button {
                composeLauncher.presentEdit?(item)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: past ? "bell.slash.fill" : "bell.fill")
                    Text(ReminderTime.chipLabel(fireDate))
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(past ? AuraTheme.textTertiary : AuraTheme.accentDot)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(AuraTheme.surfaceHover))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(past ? "Reminder passed — edit" : "Edit reminder")
        }
    }
}
