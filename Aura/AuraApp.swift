import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(composeLauncher: appDelegate.env.composeLauncher)
                .environment(appDelegate.env.dataStore)
                .environment(appDelegate.env.settingsPresenter)
                .environmentObject(appDelegate.env.updater)
        } label: {
            MenuBarLabel(launcher: appDelegate.env.libraryLauncher)
        }

        Window("Library", id: "library") {
            LibraryWindowView()
                .environment(appDelegate.env.dataStore)
                .environment(appDelegate.env.inAppComposeLauncher)
                .environment(appDelegate.env.settingsPresenter)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)

        // Settings now live in-app (full-page inside the Library window, driven
        // by SettingsPresenter), so there is no native `Settings` scene.
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
