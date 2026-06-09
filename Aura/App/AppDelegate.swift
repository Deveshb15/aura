import AppKit
import Carbon.HIToolbox

/// Creates the notch panel, starts clipboard watching, and wires the two
/// together. The app stays an `.accessory` (menu-bar) agent throughout.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()
    private var notchController: NotchController?
    private var libraryHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchController(state: NotchStateModel(), dataStore: env.dataStore)
        let launcher = env.libraryLauncher
        controller.onOpenLibrary = { launcher.open?() }
        controller.show()
        notchController = controller

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
                                     modifiers: UInt32(cmdKey | optionKey)) {
            launcher.open?()
        }
    }
}
