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
    private var licenseController: LicenseActivationController?
    private var didActivateApp = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        NSApp.setActivationPolicy(.accessory)

        // Stability: flush decoded-image caches the moment the OS reports memory
        // pressure (keeps a low-RAM Mac out of swap thrash), and surface any
        // main-thread hang in the log so it's diagnosable instead of invisible.
        ImageCache.startMonitoringMemoryPressure()
        MainThreadWatchdog.startIfEnabled()

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

        // A revoked or deactivated license tears the app back down to the paywall
        // while it's running (see lockApp()).
        env.license.onLockedOut = { [weak self] in self?.lockApp() }

        // Hard paywall. The notch reveal + clipboard capture (activateAppIfNeeded)
        // are unreachable until the app is BOTH onboarded and licensed:
        //   • not onboarded        → onboarding (carousel → license → launch-at-login)
        //   • onboarded + licensed → go live now, then re-validate in the background
        //   • onboarded, no license→ standalone license gate (key cleared/revoked)
        // `.offlineGrace` counts as licensed, so a licensed relaunch never blocks
        // on the network.
        let onboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        switch (onboarded, env.license.isLicensed) {
        case (false, _):
            presentOnboarding()
        case (true, true):
            autoEnableLaunchAtLoginForExistingUsersIfNeeded()
            activateAppIfNeeded()
            Task { await env.license.validateOnLaunch() }
        case (true, false):
            presentLicenseGate()
        }
    }

    /// Existing users onboarded before launch-at-login was offered never made a
    /// choice — so enable it once, matching the new opt-out default, so the app
    /// returns after a restart. Gated by `configuredDefaultsKey` (also set when
    /// onboarding finishes), so a brand-new user who opts out is never overridden,
    /// and a user who later disables it in Settings stays disabled.
    private func autoEnableLaunchAtLoginForExistingUsersIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: LaunchAtLogin.configuredDefaultsKey)
        else { return }
        UserDefaults.standard.set(true, forKey: LaunchAtLogin.configuredDefaultsKey)
        if LaunchAtLogin.status != .enabled { LaunchAtLogin.setEnabled(true) }
        UserDefaults.standard.set(LaunchAtLogin.isEnabled,
                                  forKey: LaunchAtLogin.enabledDefaultsKey)
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
    /// Its completion marks onboarding done and brings the app live. The license
    /// step inside it is a hard wall — onboarding can't complete unlicensed.
    private func presentOnboarding() {
        guard onboardingController == nil else { return }
        let controller = OnboardingController(license: env.license) { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self?.activateAppIfNeeded()
            self?.onboardingController = nil
        }
        onboardingController = controller
        controller.show()
    }

    /// Present the standalone license gate (returning user with no/invalid key,
    /// or a mid-session re-lock). On successful activation it brings the app live.
    private func presentLicenseGate() {
        guard licenseController == nil else { return }
        let controller = LicenseActivationController(license: env.license) { [weak self] in
            self?.activateAppIfNeeded()
            self?.licenseController = nil
        }
        licenseController = controller
        controller.show()
    }

    /// Tear the app back down to the hard paywall mid-session — triggered when a
    /// background re-validate finds the key revoked (refund/chargeback) or the
    /// user deactivates this Mac from Settings. Hides the notch, stops capture,
    /// resets the one-shot activation guard, and re-presents the gate.
    private func lockApp() {
        notchController?.hide()
        env.clipboardWatcher.stop()
        env.settingsPresenter.isPresented = false
        didActivateApp = false
        presentLicenseGate()
    }
}
