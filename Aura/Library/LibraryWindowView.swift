import SwiftUI

/// The main library window, redesigned to match the Figma: a near-black canvas,
/// a centered "Capture Aura" serif wordmark, a giant serif "Ask your Memory…"
/// hero that doubles as the search field, content-type tabs, and the bento grid.
struct LibraryWindowView: View {
    @Environment(DataStore.self) private var store
    @State private var query = ""
    @State private var selectedTab: ContentTab = .all
    @State private var searchResults: [Item] = []
    @State private var editingSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            AuraTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                wordmark
                    .padding(.top, 26)
                    .padding(.bottom, 52)
                searchHero
                    .padding(.horizontal, 40)
                    .padding(.bottom, 26)
                ContentTypeTabBar(selection: $selectedTab)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 18)
                content
            }
        }
        .preferredColorScheme(.dark)
        .background(WindowFullScreenEnabler())
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { searchResults = []; return }
            try? await Task.sleep(nanoseconds: 200_000_000) // debounce
            guard !Task.isCancelled else { return }
            searchResults = await store.search(trimmed)
        }
    }

    // MARK: - Header

    private var wordmark: some View {
        Text("Capture Aura")
            .font(AuraFont.serif(21, .medium))
            .foregroundStyle(AuraTheme.textPrimary)
            .frame(maxWidth: .infinity)
    }

    // The hero doubles as the search field, but the text field is only inserted
    // (and focused) once tapped — otherwise the window would auto-focus it on
    // launch and show a blinking caret before the user has clicked anything.
    @ViewBuilder private var searchHero: some View {
        Group {
            if editingSearch {
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AuraTheme.textPrimary)
                    .tint(AuraTheme.accentDot)
                    .focused($searchFocused)
                    .onAppear { searchFocused = true }
                    .onChange(of: searchFocused) { _, focused in
                        if !focused && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            editingSearch = false
                        }
                    }
            } else {
                Text(query.isEmpty ? "Ask your Memory…" : query)
                    .foregroundStyle(query.isEmpty ? AuraTheme.textSecondary : AuraTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { editingSearch = true }
            }
        }
        .font(AuraFont.serif(60, .regular, .tall))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if filteredItems.isEmpty {
            emptyState
        } else {
            BentoGridView(items: filteredItems)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34))
                .foregroundStyle(AuraTheme.textTertiary)
            Text(emptyTitle)
                .font(AuraFont.serif(22, .regular))
                .foregroundStyle(AuraTheme.textSecondary)
            Text("Drop things into the notch or copy something to get started.")
                .font(.system(size: 12))
                .foregroundStyle(AuraTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredItems: [Item] {
        // While searching, show all matches across types; otherwise filter by tab.
        if isSearching { return searchResults }
        if selectedTab == .all { return store.libraryItems }
        return store.libraryItems.filter { ContentTab.of($0) == selectedTab }
    }

    private var emptyTitle: String {
        if isSearching { return "No matches" }
        return store.libraryItems.isEmpty ? "Nothing saved yet" : "Nothing in \(selectedTab.label)"
    }
}

/// Configures the Library window's chrome directly on the `NSWindow`: a
/// transparent, full-size-content title bar for the edge-to-edge dark look,
/// while keeping native full screen enabled (the green button). We avoid
/// SwiftUI's `.windowStyle(.hiddenTitleBar)` because it strips
/// `.fullScreenPrimary`, leaving the green button to only "maximize".
private struct WindowFullScreenEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfigView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfigView)?.applyChrome()
    }

    /// SwiftUI's `Window` scene forces `.fullScreenNone` on its window shortly
    /// after creation (so the green button only "maximizes"). We re-assert our
    /// chrome — transparent full-size title bar + `.fullScreenPrimary` — on
    /// attach, on every SwiftUI update, and on a few delayed ticks to outlast
    /// that reset, plus a one-time observer in case it re-applies later.
    final class ConfigView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            applyChrome()
            for delay in [0.1, 0.5, 1.0, 2.0, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.applyChrome() }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(reapply),
                name: NSWindow.didBecomeKeyNotification, object: window)
        }

        @objc private func reapply() { applyChrome() }

        func applyChrome() {
            guard let window else { return }
            window.styleMask.insert([.titled, .resizable, .fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
    }
}
