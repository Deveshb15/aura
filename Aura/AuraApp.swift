import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.env.dataStore)
        } label: {
            MenuBarLabel(launcher: appDelegate.env.libraryLauncher)
        }

        Window("Library", id: "library") {
            LibraryWindowView()
                .environment(appDelegate.env.dataStore)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)

        Settings {
            SettingsView()
                .environment(appDelegate.env.dataStore)
        }
    }
}

/// The menu-bar icon. Lives in a SwiftUI scene for the whole app lifetime, so
/// its `onAppear` is a reliable place to capture `openWindow` for the launcher.
private struct MenuBarLabel: View {
    let launcher: LibraryLauncher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "tray.full.fill")
            .onAppear {
                launcher.open = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "library")
                }
            }
    }
}
