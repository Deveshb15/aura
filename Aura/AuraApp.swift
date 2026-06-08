import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Aura", systemImage: "tray.full.fill") {
            MenuBarContent()
                .environment(appDelegate.env.dataStore)
        }

        Window("Library", id: "library") {
            LibraryWindowView()
                .environment(appDelegate.env.dataStore)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 720)

        Settings {
            SettingsPlaceholderView()
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.full.fill").font(.largeTitle).foregroundStyle(.tint)
            Text("Aura").font(.title2).bold()
            Text("Settings coming soon.").foregroundStyle(.secondary)
        }
        .frame(width: 380, height: 220)
    }
}
