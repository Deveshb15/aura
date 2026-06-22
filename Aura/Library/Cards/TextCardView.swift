import SwiftUI

/// A text note card. The note body is edited in place: clicking puts the caret
/// where you clicked, and the card commits on blur. A brand-new note (a
/// "draft", tracked on `InAppComposeLauncher`) saves on non-empty blur and is
/// discarded when left empty; an existing note updates, or is deleted when
/// emptied. "Link + note" cards keep their preview, which still opens the URL.
struct TextCardView: View {
    let item: Item
    var heroURL: URL? = nil
    var faviconURL: URL? = nil
    /// Width available to the editor (column width minus the card's padding).
    var contentWidth: CGFloat = 0

    @Environment(DataStore.self) private var store
    @Environment(InAppComposeLauncher.self) private var composeLauncher

    @State private var draftText = ""
    @State private var originalText = ""
    @State private var isEditing = false
    @State private var sessionIsDraft = false
    @State private var autoFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if draftText.isEmpty {
                    Text("Write a note…")
                        .font(.system(size: 15))
                        .foregroundStyle(AuraTheme.textTertiary)
                        .allowsHitTesting(false)
                }
                InlineNoteEditor(
                    text: $draftText,
                    width: max(0, contentWidth),
                    autoFocus: autoFocus,
                    onFocusChange: handleFocusChange,
                    onEscape: handleEscape
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let link = item.linkURL {
                LinkEmbedView(item: item, url: link, heroURL: heroURL, faviconURL: faviconURL)
                    .contentShape(Rectangle())
                    .onTapGesture { store.open(item) }
            }
        }
        .padding(20)
        .onAppear { initialSync() }
        .onChange(of: item.textContent ?? "") { _, newValue in
            // Mirror external changes only while not editing, so live enrichment
            // re-publishes don't fight the user's caret.
            if !isEditing {
                draftText = newValue
                originalText = newValue
            }
        }
    }

    // MARK: - Editing lifecycle

    private func initialSync() {
        let text = item.textContent ?? ""
        draftText = text
        originalText = text
        if composeLauncher.autofocusItemID == item.id {
            autoFocus = true
            composeLauncher.autofocusItemID = nil
        }
    }

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            isEditing = true
            sessionIsDraft = (composeLauncher.draft?.id == item.id)
            originalText = item.textContent ?? ""
        } else {
            // Guards against a second resign during view teardown.
            guard isEditing else { return }
            isEditing = false
            commit()
        }
    }

    private func handleEscape() {
        isEditing = false
        if sessionIsDraft || composeLauncher.draft?.id == item.id {
            composeLauncher.draft = nil          // discard the draft
        } else {
            draftText = originalText              // revert the edit
        }
    }

    private func commit() {
        let new = draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        if sessionIsDraft {
            // If a *different* draft is already active, this card was handed off
            // (e.g. "New note" opened a fresh draft) — save our text but leave
            // the new draft alone instead of clearing it.
            if composeLauncher.draft?.id == item.id { composeLauncher.draft = nil }
            guard !new.isEmpty else { return }   // wrote nothing → vanish
            Task { await store.saveNote(text: new, sourceApp: "Carpet") }
            return
        }

        let old = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != old else { return }         // untouched
        if new.isEmpty {
            store.delete(item)                   // cleared an existing note → delete
        } else {
            Task { await store.updateNote(item, text: new) }
        }
    }
}

/// Compact link preview shown inside a text card whose content embeds a URL
/// ("link + note" captures) — hero image when the Open Graph fetch found one,
/// then favicon + title + host.
private struct LinkEmbedView: View {
    let item: Item
    let url: URL
    let heroURL: URL?
    let faviconURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = DiskImage.load(heroURL) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    if item.subtype.isVideo { playBadge }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                faviconView
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.ogTitle ?? item.host ?? url.absoluteString)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(item.host ?? url.host ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .background(AuraTheme.surfaceHover)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AuraTheme.hairline))
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.6), in: Circle())
            .padding(6)
    }

    @ViewBuilder private var faviconView: some View {
        if let favicon = DiskImage.load(faviconURL) {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }
}
