import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// Full-page settings rendered INSIDE the Library window (no separate native
/// Settings window). Styled with `AuraTheme` to match the app; the only system
/// UI it surfaces is the `NSSavePanel` file picker used by Export. Behavior is
/// unchanged from the old `Form`-based settings — only the presentation differs.
struct SettingsScreen: View {
    @Environment(DataStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    /// Returns to the library (the gear/back arrow owns the actual dismissal).
    var onBack: () -> Void

    @AppStorage("captureEnabled") private var captureEnabled = true
    @AppStorage("linkPreviewsEnabled") private var linkPreviewsEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var confirmingClear = false
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isImporting = false
    @State private var importSummary: String?
    @State private var importError: String?
    @State private var showingExportHelp = false
    @State private var showingExportInfo = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    captureSection
                    generalSection
                    dataSection
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)        // center the column
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AuraTheme.background)
        .onAppear { syncLaunchAtLogin() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            Text("Settings")
                .font(AuraFont.serif(21, .medium))
                .foregroundStyle(AuraTheme.textPrimary)
                .frame(maxWidth: .infinity)

            // Back sits clear of the window's traffic-light cluster (top-left).
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13.5, weight: .medium))
                    }
                    .foregroundStyle(AuraTheme.textSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to library")
                Spacer()
            }
            .padding(.leading, 76)
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Sections

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Capture")
            card {
                Toggle(isOn: $captureEnabled) { rowLabel("Watch clipboard (nudge to save)") }
                    .toggleStyle(.aura)
                    .padding(.vertical, 13)
                rowDivider
                Toggle(isOn: $linkPreviewsEnabled) { rowLabel("Fetch link previews") }
                    .toggleStyle(.aura)
                    .padding(.vertical, 13)
            }
            footnote("Link previews are the only feature that uses the network. Everything else is fully local.")
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("General")
            card {
                Toggle(isOn: $launchAtLogin) { rowLabel("Launch at login") }
                    .toggleStyle(.aura)
                    .padding(.vertical, 13)
                    .onChange(of: launchAtLogin) { _, isOn in setLaunchAtLogin(isOn) }
                rowDivider
                HStack {
                    rowLabel("Welcome tour")
                    Spacer()
                    Button("Replay…") {
                        NotificationCenter.default.post(name: .auraReplayOnboarding, object: nil)
                    }
                    .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Data")
            card {
                HStack {
                    rowLabel("Saved items")
                    Spacer()
                    Text("\(store.libraryItems.count)")
                        .font(.system(size: 14))
                        .foregroundStyle(AuraTheme.textSecondary)
                }
                .padding(.vertical, 13)
                rowDivider
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        rowLabel("Export")
                        Button { showingExportInfo.toggle() } label: {
                            HStack(spacing: 3) {
                                Text("What's included?")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(AuraTheme.textTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingExportInfo, arrowEdge: .bottom) {
                            exportInfoPopover
                        }
                    }
                    Spacer()
                    Button(action: startExport) {
                        if isExporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Export to Zip…")
                        }
                    }
                    .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                    .disabled(isExporting || store.libraryItems.isEmpty)
                }
                .padding(.vertical, 10)
                rowDivider
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        rowLabel("Import bookmarks")
                        Button { showingExportHelp.toggle() } label: {
                            HStack(spacing: 3) {
                                Text("How do I export?")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(AuraTheme.textTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingExportHelp, arrowEdge: .bottom) {
                            exportHelpPopover
                        }
                    }
                    Spacer()
                    Button(action: startBookmarkImport) {
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Import bookmarks…")
                        }
                    }
                    .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                    .disabled(isImporting)
                }
                .padding(.vertical, 10)
                rowDivider
                clearRow
            }
            if let exportError {
                footnote(exportError, color: AuraTheme.destructive)
            }
            if let importError {
                footnote(importError, color: AuraTheme.destructive)
            }
            if let importSummary {
                footnote(importSummary)
            }
        }
    }

    /// The destructive row, with an inline two-step confirm (no native dialog).
    @ViewBuilder private var clearRow: some View {
        if confirmingClear {
            HStack(spacing: 10) {
                Text("Delete everything? This can't be undone.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AuraTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.15)) { confirmingClear = false }
                }
                .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                Button {
                    store.deleteAllItems()
                    withAnimation(.easeOut(duration: 0.15)) { confirmingClear = false }
                } label: {
                    Text("Delete Everything")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AuraTheme.destructive))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
        } else {
            HStack {
                rowLabel("Clear all saved items")
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { confirmingClear = true }
                } label: {
                    Text("Clear All Data…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AuraTheme.destructive)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AuraTheme.destructive.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AuraTheme.destructive.opacity(0.22)))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: - Building blocks

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(AuraTheme.textSecondary)
            .padding(.leading, 4)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(AuraTheme.textPrimary)
    }

    private func footnote(_ text: String, color: Color = AuraTheme.textTertiary) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 4)
            .padding(.top, 2)
    }

    @ViewBuilder private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AuraTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AuraTheme.hairline))
    }

    private var rowDivider: some View {
        Rectangle().fill(AuraTheme.hairline).frame(height: 1)
    }

    // MARK: - Export (system save panel is the only native UI)

    /// Asks where to save, then builds the zip off the main actor and reveals it
    /// in Finder. The save panel runs first so the user picks the destination
    /// before any (potentially slow) file copying begins.
    private func startExport() {
        let panel = NSSavePanel()
        panel.title = "Export Aura Vault"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "Aura Export \(Self.fileDateStamp()).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        exportError = nil
        isExporting = true
        Task {
            do {
                let zipURL = try await store.exportVaultZip()
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: zipURL, to: destination)
                isExporting = false
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                isExporting = false
                exportError = error.localizedDescription
            }
        }
    }

    // MARK: - Import (browser bookmarks)

    private struct ExportGuide: Identifiable {
        let browser: String
        let steps: String
        var id: String { browser }
    }

    /// Where each browser hides "Export bookmarks". The Chromium families share a
    /// path, so the last row covers Arc/Opera/Vivaldi without claiming a wrong menu.
    private static let exportGuides: [ExportGuide] = [
        ExportGuide(browser: "Chrome, Edge, Brave",
                    steps: "Bookmarks → Bookmark Manager → ⋮ (top-right) → Export bookmarks"),
        ExportGuide(browser: "Safari",
                    steps: "File → Export → Bookmarks…"),
        ExportGuide(browser: "Firefox",
                    steps: "Bookmarks → Manage Bookmarks → Import and Backup → Export Bookmarks to HTML…"),
        ExportGuide(browser: "Arc & other Chromium browsers",
                    steps: "Open the bookmark manager, then choose Export bookmarks"),
    ]

    /// Per-browser export steps, shown right where the user is about to import.
    /// Fills its own background so the dark theme survives inside the popover.
    private var exportHelpPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export bookmarks from your browser")
                .font(AuraFont.serif(16, .medium))
                .foregroundStyle(AuraTheme.textPrimary)

            VStack(alignment: .leading, spacing: 11) {
                ForEach(Self.exportGuides) { guide in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guide.browser)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AuraTheme.textPrimary)
                        Text(guide.steps)
                            .font(.system(size: 12))
                            .foregroundStyle(AuraTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Save the .html anywhere, then click Import bookmarks and pick it.")
                .font(.system(size: 11.5))
                .foregroundStyle(AuraTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .background(AuraTheme.background)
    }

    /// What the Zip export contains — shown inline like "How do I export?" so the
    /// detail lives next to the action instead of as a footnote.
    private var exportInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's in the export")
                .font(AuraFont.serif(16, .medium))
                .foregroundStyle(AuraTheme.textPrimary)
            Text("A .zip you can open anywhere — each saved item becomes its own file, grouped into Text, Links, Images, Files and Colors folders, plus an aura-export.json with the details.")
                .font(.system(size: 12))
                .foregroundStyle(AuraTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .background(AuraTheme.background)
    }

    /// Picks a bookmarks HTML file, imports it off the main actor, then reports a
    /// human summary. Mirrors `startExport` but with an open panel.
    private func startBookmarkImport() {
        let panel = NSOpenPanel()
        panel.title = "Import Bookmarks"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importError = nil
        importSummary = nil
        isImporting = true
        Task {
            do {
                let result = try await store.importBookmarks(from: url)
                isImporting = false
                applyImportResult(result)
            } catch {
                isImporting = false
                importError = error.localizedDescription
            }
        }
    }

    /// Turns the counts into a friendly, success-toned message. A file with no
    /// recognizable bookmarks is the one case surfaced as an error.
    private func applyImportResult(_ result: BookmarkImporter.ImportResult) {
        if result.imported > 0 {
            var message = "Imported \(result.imported) bookmark\(result.imported == 1 ? "" : "s")."
            if result.skippedDuplicates > 0 {
                message += " Skipped \(result.skippedDuplicates) already in your vault."
            }
            importSummary = message
            toasts.show(AuraToast(
                title: "Imported \(result.imported) bookmark\(result.imported == 1 ? "" : "s")",
                subtitle: result.skippedDuplicates > 0
                    ? "\(result.skippedDuplicates) already saved — skipped"
                    : "Now at the top of your library",
                symbol: "checkmark.circle.fill"))
        } else if result.skippedDuplicates > 0 {
            importSummary = "All \(result.skippedDuplicates) bookmark\(result.skippedDuplicates == 1 ? " was" : "s were") already in your vault."
        } else if result.totalParsed == 0 {
            importError = "This doesn't look like a bookmarks file. Export bookmarks from your browser as HTML and try again."
        } else {
            importSummary = "No web bookmarks found to import."
        }
    }

    private static func fileDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Launch at login

    /// Reflect the actual login-item state (it can change outside the app).
    private func syncLaunchAtLogin() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Aura: launch-at-login toggle failed: \(error)")
        }
    }
}
