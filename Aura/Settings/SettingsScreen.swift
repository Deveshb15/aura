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
    @Environment(LicenseManager.self) private var license
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
    @State private var showingXHelp = false
    /// True when macOS has the login item registered but pending the user's
    /// approval in System Settings — it won't actually launch until approved.
    @State private var launchAtLoginNeedsApproval = false
    @State private var confirmingDeactivate = false
    @State private var isDeactivating = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    captureSection
                    generalSection
                    // Only purchasers (who actually activated a key) see the
                    // License section; grandfathered/free users never do.
                    if license.licenseKey != nil { licenseSection }
                    dataSection
                    HelpFooter()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
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
            }
            if launchAtLoginNeedsApproval {
                HStack(spacing: 8) {
                    footnote("Approve Carpet in System Settings → General → Login Items so it can start at login.",
                             color: AuraTheme.textSecondary)
                    Spacer(minLength: 8)
                    Button("Open Login Items") {
                        LaunchAtLogin.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    // MARK: - License

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("License")
            card {
                HStack {
                    rowLabel("Status")
                    Spacer()
                    licenseStatusBadge
                }
                .padding(.vertical, 13)
                if let masked = license.maskedKey {
                    rowDivider
                    HStack {
                        rowLabel("License key")
                        Spacer()
                        Text(masked)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AuraTheme.textSecondary)
                    }
                    .padding(.vertical, 13)
                }
                if let last = license.lastValidatedAt {
                    rowDivider
                    HStack {
                        rowLabel("Last checked")
                        Spacer()
                        Text(RelativeTime.medium(last))
                            .font(.system(size: 14))
                            .foregroundStyle(AuraTheme.textSecondary)
                    }
                    .padding(.vertical, 13)
                }
                rowDivider
                HStack {
                    rowLabel("Need help with your license?")
                    Spacer()
                    Button("Email Support") { NSWorkspace.shared.open(LicenseAPI.manageURL) }
                        .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                }
                .padding(.vertical, 10)
                rowDivider
                deactivateRow
            }
            footnote("Your license covers up to 3 Macs. Deactivate this one to free a slot for another Mac.")
        }
    }

    /// A colored dot + label reflecting the live license state.
    @ViewBuilder private var licenseStatusBadge: some View {
        let (dot, label): (Color, String) = {
            switch license.status {
            case .licensed:          return (.green, "Active")
            case .offlineGrace:      return (.orange, "Active (offline)")
            case .invalid(.revoked): return (AuraTheme.destructive, "Revoked")
            case .activating:        return (AuraTheme.textTertiary, "Activating…")
            default:                 return (AuraTheme.textTertiary, "Not active")
            }
        }()
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AuraTheme.textSecondary)
        }
    }

    /// Two-step inline confirm (no native dialog), mirroring `clearRow`. On
    /// confirm it frees this Mac's Dodo slot, clears the Keychain, and re-locks
    /// the app (the gate window reappears via `LicenseManager.onLockedOut`).
    @ViewBuilder private var deactivateRow: some View {
        if confirmingDeactivate {
            HStack(spacing: 10) {
                Text("Deactivate Carpet on this Mac? You'll need to re-enter your key to use it here again.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AuraTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel") {
                    withAnimation(.easeOut(duration: 0.15)) { confirmingDeactivate = false }
                }
                .buttonStyle(AuraSecondaryButtonStyle(compact: true))
                .disabled(isDeactivating)
                Button {
                    Task {
                        isDeactivating = true
                        await license.deactivate()
                        isDeactivating = false
                        confirmingDeactivate = false
                    }
                } label: {
                    Group {
                        if isDeactivating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Deactivate")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AuraTheme.destructive))
                }
                .buttonStyle(.plain)
                .disabled(isDeactivating)
            }
            .padding(.vertical, 10)
        } else {
            HStack {
                rowLabel("Deactivate this Mac")
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { confirmingDeactivate = true }
                } label: {
                    Text("Deactivate…")
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
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        rowLabel("X bookmarks")
                        Button { showingXHelp.toggle() } label: {
                            HStack(spacing: 3) {
                                Text("How does this work?")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(AuraTheme.textTertiary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingXHelp, arrowEdge: .bottom) {
                            xHelpPopover
                        }
                    }
                    Spacer()
                    Button(action: startXBookmarkImport) {
                        Text("Import my bookmarks…")
                    }
                    .buttonStyle(AuraSecondaryButtonStyle(compact: true))
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

    /// The Carpet — X Bookmark Sync browser extension on the Chrome Web Store.
    private static let extensionURL = URL(string: "https://chromewebstore.google.com/detail/carpet-%E2%80%94-x-bookmark-sync/okblnhfjfpfjmljaagmebbmhkcgmmgli")!

    /// How the X bookmark sync works + how to set up the companion extension.
    private var xHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync your X bookmarks")
                .font(AuraFont.serif(16, .medium))
                .foregroundStyle(AuraTheme.textPrimary)

            VStack(alignment: .leading, spacing: 9) {
                xStep("1", "Get the extension") {
                    Button {
                        NSWorkspace.shared.open(Self.extensionURL)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Install Carpet — X Bookmark Sync from the Chrome Web Store")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(AuraTheme.accentDot)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .help("Open the Carpet extension on the Chrome Web Store")
                }
                xStep("2", "Bookmark on X like normal",
                      "While you’re on x.com, anything you bookmark is saved to Carpet automatically — author, text and image included. Keep Carpet running.")
                xStep("3", "Bring in your history",
                      "“Import my bookmarks” opens your X bookmarks and pulls in up to 400 existing ones as it scrolls.")
            }

            Text("Carpet only reads your bookmarks page’s own data while you’re on X — no passwords, no background access, nothing leaves your Mac.")
                .font(.system(size: 11))
                .foregroundStyle(AuraTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .background(AuraTheme.background)
    }

    /// One numbered step with plain-text detail (steps 2–3).
    private func xStep(_ number: String, _ title: String, _ detail: String) -> some View {
        xStep(number, title) {
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(AuraTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One numbered step with a custom detail view (step 1 hosts a store link).
    private func xStep<Detail: View>(_ number: String, _ title: String,
                                     @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AuraTheme.textSecondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(AuraTheme.hairline))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AuraTheme.textPrimary)
                detail()
            }
        }
    }

    /// Opens the user's X bookmarks with the import trigger so the extension's
    /// watcher starts a one-time, capped harvest (auto-scroll → up to 400).
    private func startXBookmarkImport() {
        guard let url = URL(string: "https://x.com/i/bookmarks?aura_import=1") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Export (system save panel is the only native UI)

    /// Asks where to save, then builds the zip off the main actor and reveals it
    /// in Finder. The save panel runs first so the user picks the destination
    /// before any (potentially slow) file copying begins.
    private func startExport() {
        let panel = NSSavePanel()
        panel.title = "Export Carpet Vault"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "Carpet Export \(Self.fileDateStamp()).zip"
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
            Text("A .zip you can open anywhere — each saved item becomes its own file, grouped into Text, Links, Images, Files and Colors folders, plus a carpet-export.json with the details.")
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
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginNeedsApproval = (LaunchAtLogin.status == .requiresApproval)
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        LaunchAtLogin.setEnabled(isOn)
        // Re-read the system's view: a register() can land on `.requiresApproval`
        // rather than `.enabled`, in which case we surface the approval hint.
        launchAtLoginNeedsApproval = (LaunchAtLogin.status == .requiresApproval)
    }
}
