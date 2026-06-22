import SwiftUI

/// The main library window, redesigned to match the Figma: a near-black canvas,
/// a centered Carpet logo wordmark, a giant serif "Ask your Memory…"
/// hero that doubles as the search field, content-type tabs, and the bento grid.
struct LibraryWindowView: View {
    @Environment(DataStore.self) private var store
    @Environment(InAppComposeLauncher.self) private var composeLauncher
    @Environment(SettingsPresenter.self) private var settings
    @Environment(ThemeManager.self) private var theme
    @Environment(ToastCenter.self) private var toasts
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

            // Settings takes over the whole window (in-app, no native popup);
            // otherwise the library is shown.
            if settings.isPresented {
                SettingsScreen(onBack: {
                    withAnimation(.easeOut(duration: 0.22)) { settings.isPresented = false }
                })
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                libraryStack
                    .transition(.opacity)
            }
        }
        // A "New note" affordance and the settings gear flank the header. Both
        // are in-window because the app is an LSUIElement agent (no app menu).
        // Hidden while Settings is up (it has its own Back control).
        .overlay(alignment: .topLeading) { if !settings.isPresented { newNoteButton } }
        .overlay(alignment: .topTrailing) {
            if !settings.isPresented {
                HStack(spacing: 2) { themeToggle; settingsGear }
                    .padding(.top, 18)
                    .padding(.trailing, 20)
            }
        }
        // Transient confirmation banner (e.g. after a bookmark import), floated
        // above whatever surface is showing — library or the Settings overlay.
        .overlay(alignment: .bottom) {
            if let toast = toasts.current {
                ToastView(toast: toast) { toasts.dismiss() }
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: toasts.current)
        .preferredColorScheme(theme.colorScheme)
        .background(WindowFullScreenEnabler(launcher: composeLauncher))
        // ⌘N starts an inline note draft while this window is key (distinct from
        // the global ⌃⌘N, which the notch handles when the Library isn't focused).
        .background {
            Button("") { startDraft() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Register the in-app composer entry point so the global New Note hotkey
        // drives an inline draft in this window.
        .onAppear {
            composeLauncher.present = { startDraft() }
        }
        .onDisappear {
            composeLauncher.present = nil
            composeLauncher.draft = nil
            composeLauncher.autofocusItemID = nil
            composeLauncher.isLibraryKey = false
        }
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
        .onChange(of: selectedTab) { _, _ in
            searchFocused = true
        }
    }

    // MARK: - Library

    /// The library surface: wordmark, search hero, answer, tabs, and grid.
    private var libraryStack: some View {
        VStack(spacing: 0) {
            wordmark
                .padding(.top, 26)
                .padding(.bottom, 52)
            searchHero
                .padding(.horizontal, 40)
                .padding(.bottom, showAnswer ? 16 : 26)
            answerBanner
            ContentTypeTabBar(selection: $selectedTab, counts: tabCounts)
                .padding(.horizontal, 40)
                .padding(.bottom, 18)
            content
        }
    }

    // MARK: - Header

    private var wordmark: some View {
        Image("LogoWithText")
            .resizable()
            .scaledToFit()
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Carpet")
    }

    /// Header affordance to compose a note in-app (also bound to ⌘N).
    private var newNoteButton: some View {
        Button { startDraft() } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                Text("New note")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(AuraTheme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(AuraTheme.surface))
            .overlay(Capsule().strokeBorder(AuraTheme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.leading, 20)
        .help("New note (⌘N)")
    }

    /// Light/dark theme toggle — a single sun/moon that morphs between states.
    /// Sits just left of the gear; one tap flips the whole app's theme.
    private var themeToggle: some View {
        Button {
            withAnimation(.smooth(duration: 0.35)) { theme.toggle() }
        } label: {
            Image(systemName: theme.mode == .dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AuraTheme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 19, height: 19)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.mode == .dark ? "Switch to light theme" : "Switch to dark theme")
    }

    /// Opens the in-app, full-page Settings screen (no native Settings window).
    private var settingsGear: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) { settings.isPresented = true }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AuraTheme.textSecondary)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
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
                .strokeBorder(AuraTheme.hairline))
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
        if gridItems.isEmpty {
            emptyState
        } else {
            BentoGridView(items: gridItems)
        }
    }

    /// The grid's items, with any in-progress note draft pinned to the front so
    /// it renders as the first (top-left) card.
    private var gridItems: [Item] {
        guard let draft = composeLauncher.draft else { return filteredItems }
        return [draft] + filteredItems.filter { $0.id != draft.id }
    }

    /// Starts an inline note draft: a transient, unsaved `.text` item shown as a
    /// focused card at the top of the grid. Saved on non-empty blur, discarded
    /// when left empty. Always opens a *fresh* draft — if one is already open,
    /// swapping it out tears down its card, which commits it (saves non-empty /
    /// discards empty) as it loses focus, so "New note" while writing saves the
    /// current note first.
    private func startDraft() {
        var draft = Item(type: .text)
        draft.sourceApp = "Carpet"
        draft.textContent = ""
        query = ""                                   // leave any search so the draft shows
        composeLauncher.draft = draft
        composeLauncher.autofocusItemID = draft.id
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

    /// Counts shown on the tab bar, over the same base set the tabs filter
    /// (search results while searching, otherwise the library), so each badge
    /// reflects what selecting that tab would show.
    private var tabCounts: [ContentTab: Int] {
        ContentTab.counts(for: isSearching ? searchResults : store.libraryItems)
    }

    private var filteredItems: [Item] {
        // Search and the category tab compose: matches, then narrowed to the tab.
        if isSearching {
            if selectedTab == .all { return searchResults }
            return searchResults.filter { ContentTab.tabs(for: $0).contains(selectedTab) }
        }
        if selectedTab == .all { return store.libraryItems }
        return store.libraryItems.filter { ContentTab.tabs(for: $0).contains(selectedTab) }
    }

    private var emptyTitle: String {
        if isSearching {
            return selectedTab == .all ? "No matches" : "No matches in \(selectedTab.label)"
        }
        return store.libraryItems.isEmpty ? "Nothing saved yet" : "Nothing in \(selectedTab.label)"
    }
}

/// Configures the Library window's chrome directly on the `NSWindow`: a
/// transparent, full-size-content title bar for the edge-to-edge dark look,
/// while keeping native full screen enabled (the green button). We avoid
/// SwiftUI's `.windowStyle(.hiddenTitleBar)` because it strips
/// `.fullScreenPrimary`, leaving the green button to only "maximize".
private struct WindowFullScreenEnabler: NSViewRepresentable {
    let launcher: InAppComposeLauncher
    func makeNSView(context: Context) -> NSView { ConfigView(launcher: launcher) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfigView)?.applyChrome()
    }

    /// SwiftUI's `Window` scene forces `.fullScreenNone` on its window shortly
    /// after creation (so the green button only "maximizes"). We re-assert our
    /// chrome — transparent full-size title bar + `.fullScreenPrimary` — on
    /// attach, on every SwiftUI update, and on a few delayed ticks to outlast
    /// that reset, plus a one-time observer in case it re-applies later. This
    /// view also tracks key-window state into the launcher so New Note can route
    /// to the in-app composer only while the Library is focused.
    final class ConfigView: NSView {
        let launcher: InAppComposeLauncher

        init(launcher: InAppComposeLauncher) {
            self.launcher = launcher
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            applyChrome()
            launcher.isLibraryKey = window.isKeyWindow
            for delay in [0.1, 0.5, 1.0, 2.0, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.applyChrome() }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(didBecomeKey),
                name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(didResignKey),
                name: NSWindow.didResignKeyNotification, object: window)
        }

        @objc private func didBecomeKey() { applyChrome(); launcher.isLibraryKey = true }
        @objc private func didResignKey() { launcher.isLibraryKey = false }

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
