import Foundation
import ServiceManagement

/// Single source of truth for "start Carpet at login". Wraps the modern
/// `SMAppService.mainApp` API so onboarding, the existing-user migration, and the
/// Settings toggle all register/unregister through one code path — and so the
/// UserDefaults keys involved can't drift between call sites.
///
/// `SMAppService.mainApp` registers the *running bundle's path* as a login item,
/// so it only relaunches reliably for a properly signed app in a stable location
/// (e.g. installed in /Applications). Ad-hoc dev builds run from DerivedData may
/// register a transient path that won't survive a restart — verify with a real
/// installed build.
enum LaunchAtLogin {
    /// Mirrors the Settings toggle's `@AppStorage` key so the UI reflects state.
    static let enabledDefaultsKey = "launchAtLogin"
    /// Set once a launch-at-login decision has been made for this user — via
    /// onboarding OR the existing-user migration — so we never override it later.
    static let configuredDefaultsKey = "launchAtLoginConfigured"

    /// The system's current view of our login item. Can be `.notRegistered`,
    /// `.enabled`, `.requiresApproval` (user must approve in System Settings), or
    /// `.notFound`.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Register or unregister the app as a login item. Returns `false` (and logs)
    /// if the system call throws, so callers can surface a hint if needed.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else if status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Aura: launch-at-login \(on ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    /// Opens System Settings → General → Login Items so the user can approve a
    /// pending (`.requiresApproval`) login item.
    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
