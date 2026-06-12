import Foundation
import Observation

/// Bridges "open the in-app note composer" to whatever the Library window
/// registered. `LibraryWindowView` sets `present` / `presentEdit` on appear and
/// clears them on disappear, and a window-key observer keeps `isLibraryKey`
/// current. `AppDelegate.routeNewNote` consults this: when the Library is the
/// key window it composes in-app; otherwise it falls back to the notch.
@MainActor
@Observable
final class InAppComposeLauncher {
    /// Opens the create-mode composer sheet. Non-nil only while the Library is alive.
    @ObservationIgnored var present: (() -> Void)?
    /// Opens the edit-mode composer sheet for an existing item.
    @ObservationIgnored var presentEdit: ((Item) -> Void)?
    /// True while the Library window is the app's key window.
    @ObservationIgnored var isLibraryKey = false
}
