import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(DataStore.self) private var store

    @AppStorage("captureEnabled") private var captureEnabled = true
    @AppStorage("linkPreviewsEnabled") private var linkPreviewsEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Watch clipboard (nudge to save)", isOn: $captureEnabled)
                Toggle("Fetch link previews", isOn: $linkPreviewsEnabled)
                Text("Link previews are the only feature that uses the network. Everything else is fully local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, isOn in setLaunchAtLogin(isOn) }
            }

            Section("Data") {
                LabeledContent("Saved items", value: "\(store.libraryItems.count)")
                Button("Clear All Data…", role: .destructive) { showClearConfirm = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
        .onAppear { syncLaunchAtLogin() }
        .confirmationDialog("Delete all saved items?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { store.deleteAllItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every saved item and its files from this Mac. Collections are kept. This can't be undone.")
        }
    }

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
