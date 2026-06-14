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
    private var onboardingController: OnboardingController?
    private var didActivateApp = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)

        // Warm up the embedding model (and trigger its one-time asset download)
        // so the first search is semantic, not keyword-only.
        Task.detached(priority: .utility) { await EmbeddingService.shared.prepare() }

        // X bookmark sync: start the loopback bridge the browser extension's
        // native host talks to, and (re)install the native-messaging manifests
        // into any installed Chromium-family browsers.
        env.xBridge.start()
        Task.detached(priority: .utility) { XHostManifestInstaller.install() }

        let controller = NotchController(state: NotchStateModel(), dataStore: env.dataStore)
        let launcher = env.libraryLauncher
        controller.onOpenLibrary = { launcher.open?() }
        notchController = controller

        // New Note routes to the in-app composer when the Library is the key
        // window, otherwise to the notch (see routeNewNote).
        env.composeLauncher.compose = { [weak self] in self?.routeNewNote() }

        let watcher = env.clipboardWatcher
        watcher.onCandidate = { [weak controller] candidate in
            controller?.handleCopy(candidate)
        }
        env.dataStore.onSelfCopy = { [weak watcher] changeCount in
            watcher?.ignore(changeCount: changeCount)
        }

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
            self?.routeNewNote()
        }

        // Show onboarding on first launch; otherwise go live immediately. On the
        // first run the notch reveal and clipboard capture are deferred until
        // onboarding finishes, so nothing nudges out over the welcome window.
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            activateAppIfNeeded()
        } else {
            presentOnboarding()
        }
    }

    /// New Note routing: compose in the Library window when it's the key window
    /// and has registered an in-app composer; otherwise pop the notch composer.
    /// This is what makes "create a note while the app is open" not open the notch.
    private func routeNewNote() {
        let inApp = env.inAppComposeLauncher
        if inApp.isLibraryKey, let present = inApp.present {
            present()
        } else {
            notchController?.enterCompose()
        }
    }

    /// Reveal the notch panel and start clipboard capture — exactly once.
    private func activateAppIfNeeded() {
        guard !didActivateApp else { return }
        didActivateApp = true
        notchController?.show()
        env.clipboardWatcher.start()
    }

    /// Present the first-launch onboarding window (no-op if already showing).
    /// Its completion marks onboarding done and brings the app live.
    private func presentOnboarding() {
        guard onboardingController == nil else { return }
        let controller = OnboardingController { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self?.activateAppIfNeeded()
            self?.onboardingController = nil
        }
        onboardingController = controller
        controller.show()
    }
}
