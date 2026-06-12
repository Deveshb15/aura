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
    /// Returns to the library (the gear/back arrow owns the actual dismissal).
    var onBack: () -> Void

    @AppStorage("captureEnabled") private var captureEnabled = true
    @AppStorage("linkPreviewsEnabled") private var linkPreviewsEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var confirmingClear = false
    @State private var isExporting = false
    @State private var exportError: String?

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
                    rowLabel("Export")
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
                clearRow
            }
            if let exportError {
                footnote(exportError, color: AuraTheme.destructive)
            }
            footnote("Saves a .zip you can open anywhere — each saved item becomes its own file, grouped into Text, Links, Images, Files and Colors folders, plus an aura-export.json with the details.")
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
