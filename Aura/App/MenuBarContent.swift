import SwiftUI

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DataStore.self) private var dataStore
    @EnvironmentObject private var updater: SparkleUpdater

    var body: some View {
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
