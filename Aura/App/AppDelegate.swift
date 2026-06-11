import AppKit
import Carbon.HIToolbox

/// Creates the notch panel, starts clipboard watching, and wires the two
/// together. The app stays an `.accessory` (menu-bar) agent throughout.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()
    private var notchController: NotchController?
    private var libraryHotKey: GlobalHotKey?
    private var composeHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)

        // Warm up the embedding model (and trigger its one-time asset download)
        // so the first search is semantic, not keyword-only.
        Task.detached(priority: .utility) { await EmbeddingService.shared.prepare() }

        let controller = NotchController(state: NotchStateModel(), dataStore: env.dataStore)
        let launcher = env.libraryLauncher
        controller.onOpenLibrary = { launcher.open?() }
        controller.show()
        notchController = controller

        // Let the menu-bar menu open the composer (mirrors libraryLauncher).
        env.composeLauncher.compose = { [weak controller] in controller?.enterCompose() }

        let watcher = env.clipboardWatcher
        watcher.onCandidate = { [weak controller] candidate in
            controller?.handleCopy(candidate)
        }
        env.dataStore.onSelfCopy = { [weak watcher] changeCount in
            watcher?.ignore(changeCount: changeCount)
        }
        watcher.start()

        // Global hotkey ⌥⌘V to summon the library (no Accessibility needed).
        libraryHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_V),
                                     modifiers: UInt32(cmdKey | optionKey),
                                     id: 1) {
            launcher.open?()
        }

        // Global hotkey ⌃⌘N — open quick-note compose mode in the notch.
        // Control+Command+letter is rarely used by apps, so this global hotkey
        // fires reliably everywhere (unlike ⌥⌘N / ⇧⌘N which apps bind heavily).
        composeHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_N),
                                     modifiers: UInt32(cmdKey | controlKey),
                                     id: 2) { [weak self] in
            self?.notchController?.enterCompose()
        }
    }
}
