import Foundation
import Combine
import Sparkle

/// Owns Sparkle's updater for the whole app lifetime and exposes a tiny,
/// SwiftUI-friendly surface: a "Check for Updates…" action plus whether a check
/// is currently allowed (so the menu item can disable itself mid-check).
///
/// Everything else — automatic background checks and the native
/// Install / Remind Me Later / Skip This Version panel with release notes — is
/// handled by Sparkle's standard user driver, configured entirely from
/// Info.plist (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, …).
@MainActor
final class SparkleUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    init() {
        // `startingUpdater: true` begins the scheduled background checks; the
        // standard user driver presents the update UI without stealing focus
        // (correct for a menu-bar / notch agent app).
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manual "Check for Updates…" — shows "You're up to date" when current.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
