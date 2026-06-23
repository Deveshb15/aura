import Foundation
import Observation
import GRDB
import SwiftUI

/// Bridges "open the library window" from AppKit (the notch) to SwiftUI's
/// scene-based `openWindow`. A scene view (the menu-bar label) fills in `open`
/// at launch; the notch just calls it.
@MainActor
final class LibraryLauncher {
    var open: (() -> Void)?
}

/// Shared presentation state for the in-app Settings screen. Both entry points
/// — the gear in the Library window and the menu-bar "Settings…" item — flip
/// `isPresented`, and `LibraryWindowView` renders the full-page screen from it.
@MainActor
@Observable
final class SettingsPresenter {
    var isPresented = false
}

/// Bridges "open the quick-note composer" from a SwiftUI scene (the menu-bar
/// menu) to the AppKit notch controller. `AppDelegate` fills in `compose` at
/// launch once the controller exists; the menu just calls it.
@MainActor
final class ComposeLauncher {
    var compose: (() -> Void)?
}

enum AuraThemeMode { case dark, light }

/// The selected app theme. Dark is the default. SwiftUI surfaces read
/// `colorScheme` and apply `.preferredColorScheme(...)`; the AppKit-hosted notch
/// subscribes to `onChange` to flip its window appearance. Persists to
/// UserDefaults under `isDarkTheme`.
@MainActor
@Observable
final class ThemeManager {
    var mode: AuraThemeMode {
        didSet { UserDefaults.standard.set(mode == .dark, forKey: "isDarkTheme") }
    }

    /// Installed by the Library window's AppKit layer. The palette is dynamic
    /// `NSColor`, so a theme flip re-resolves every color *instantly* — there is
    /// no value to interpolate. To make the switch feel like a light dimming up /
    /// down, the window snapshots its current rendering, flips underneath, and
    /// cross-fades the snapshot out. Falls back to an instant flip when unset
    /// (e.g. no window). Takes the actual flip as a closure so the snapshot is
    /// captured *before* the appearance changes.
    @ObservationIgnored var crossfade: ((@escaping () -> Void) -> Void)?

    init() {
        let isDark = UserDefaults.standard.object(forKey: "isDarkTheme") as? Bool ?? true
        mode = isDark ? .dark : .light
    }

    var colorScheme: ColorScheme { mode == .dark ? .dark : .light }

    func toggle() { mode = (mode == .dark) ? .light : .dark }

    /// Flips the theme with a smooth cross-fade when a window is available.
    func toggleAnimated() {
        if let crossfade {
            crossfade { [weak self] in self?.toggle() }
        } else {
            toggle()
        }
    }
}

/// Dependency-injection root: builds the database, store, and services once and
/// shares the single `DataStore` instance across both surfaces.
@MainActor
final class AppEnvironment {
    let assetStore: AssetStore
    let dbPool: DatabasePool
    let dataStore: DataStore
    let clipboardWatcher: ClipboardWatcher
    let libraryLauncher = LibraryLauncher()
    let composeLauncher = ComposeLauncher()
    let inAppComposeLauncher = InAppComposeLauncher()
    let settingsPresenter = SettingsPresenter()
    let themeManager = ThemeManager()
    let toastCenter = ToastCenter()
    let updater = SparkleUpdater()
    let xBridge: XBookmarkBridge

    init() {
        do {
            let assetStore = try AssetStore()
            let dbPool = try AppDatabase.open()
            self.assetStore = assetStore
            // Point the source-logo cache at the shared Assets/ directory.
            LogoService.configure(baseURL: assetStore.baseURL)
            self.dbPool = dbPool
            let dataStore = DataStore(dbPool: dbPool, assetStore: assetStore)
            self.dataStore = dataStore
            self.clipboardWatcher = ClipboardWatcher()
            self.xBridge = XBookmarkBridge(dataStore: dataStore)
        } catch {
            fatalError("Aura failed to initialize storage: \(error)")
        }
    }
}
