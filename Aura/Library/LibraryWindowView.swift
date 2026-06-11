import SwiftUI

/// The main library window, redesigned to match the Figma: a near-black canvas,
/// a centered "Capture Aura" serif wordmark, a giant serif "Ask your Memory…"
/// hero that doubles as the search field, content-type tabs, and the bento grid.
struct LibraryWindowView: View {
    @Environment(DataStore.self) private var store
    @State private var query = ""
    @State private var selectedTab: ContentTab = .all
    @State private var searchResults: [Item] = []
    @FocusState private var searchFocused: Bool

    // On-device AI answer (macOS 26+ / Apple Silicon). Streamed on Return.
    @State private var answerText = ""
    @State private var isAnswering = false
    @State private var answeredQuery = ""
    @State private var answerTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            AuraTheme.background
                .ignoresSafeArea()
                // The search hero is always live — clicking anywhere returns the
                // pink caret to it.
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }

            VStack(spacing: 0) {
                wordmark
                    .padding(.top, 26)
                    .padding(.bottom, 52)
                searchHero
                    .padding(.horizontal, 40)
                    .padding(.bottom, showAnswer ? 16 : 26)
                answerBanner
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
        .onChange(of: query) { _, newValue in
            // A typed edit invalidates any answer for the previous question.
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != answeredQuery {
                clearAnswer()
            }
        }
        // Switching tabs (or any stray focus change) shouldn't strand the caret.
        .onChange(of: selectedTab) { _, _ in searchFocused = true }
    }

    // MARK: - Header

    private var wordmark: some View {
        Text("Capture Aura")
            .font(AuraFont.serif(21, .medium))
            .foregroundStyle(AuraTheme.textPrimary)
            .frame(maxWidth: .infinity)
    }

    // The hero IS the search field, always live: the pink caret is always
    // present and "Ask your Memory…" shows behind it whenever the query is empty.
    @ViewBuilder private var searchHero: some View {
        ZStack(alignment: .leading) {
            if query.isEmpty {
                Text("Ask your Memory…")
                    .foregroundStyle(AuraTheme.textSecondary)
                    .allowsHitTesting(false)
            }
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(AuraTheme.textPrimary)
                .tint(AuraTheme.accentDot)   // pink caret
                .focused($searchFocused)
                .onSubmit { askMemory() }
        }
        .font(AuraFont.serif(60, .regular, .tall))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { searchFocused = true }
    }

    // MARK: - AI answer

    private var showAnswer: Bool { isAnswering || !answerText.isEmpty }

    @ViewBuilder private var answerBanner: some View {
        if showAnswer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(AuraTheme.accentDot)
                    Text("ANSWER")
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(AuraTheme.textSecondary)
                    if isAnswering {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .tint(AuraTheme.textSecondary)
                    }
                    Spacer()
                }
                Text(answerText.isEmpty ? "Thinking…" : answerText)
                    .font(AuraFont.serif(17, .regular))
                    .foregroundStyle(answerText.isEmpty ? AuraTheme.textTertiary : AuraTheme.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.12), value: answerText)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AuraTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06)))
            .padding(.horizontal, 40)
            .padding(.bottom, 18)
            .transition(.opacity)
        }
    }

    /// Stream a written answer for the current query, grounded in the live
    /// search results. No-op when the on-device model is unavailable, so on
    /// older / Intel Macs Return simply does nothing extra.
    private func askMemory() {
        answerTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.canAnswer, !q.isEmpty else { return }
        answerText = ""
        isAnswering = true
        answeredQuery = q
        answerTask = Task {
            var items = searchResults
            if items.isEmpty { items = await store.search(q) }
            for await chunk in store.answer(to: q, from: items) {
                if Task.isCancelled { return }
                answerText = chunk
            }
            isAnswering = false
        }
    }

    private func clearAnswer() {
        answerTask?.cancel()
        answerTask = nil
        answerText = ""
        isAnswering = false
        answeredQuery = ""
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
        return store.libraryItems.filter { ContentTab.tabs(for: $0).contains(selectedTab) }
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
