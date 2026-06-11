import SwiftUI

struct MenuBarContent: View {
    let composeLauncher: ComposeLauncher
    @Environment(\.openWindow) private var openWindow
    @Environment(DataStore.self) private var dataStore
    @EnvironmentObject private var updater: SparkleUpdater

    var body: some View {
        Button("New Note  ⌥⌘N") {
            composeLauncher.compose?()
        }
        // No .keyboardShortcut here: ⌥⌘N is handled by the global Carbon hotkey.
        // Binding it again would double-fire and toggle compose to a no-op.

        Button("Open Library") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "library")
        }
        .keyboardShortcut("v", modifiers: [.command, .option])

        Text("\(dataStore.libraryItems.count) items saved")

        Divider()

        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")

        Button("Quit Aura") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
