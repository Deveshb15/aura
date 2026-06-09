import SwiftUI

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        Button("Open Library") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "library")
        }
        .keyboardShortcut("v", modifiers: [.command, .option])

        Text("\(dataStore.libraryItems.count) items saved")

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")

        Button("Quit Aura") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
