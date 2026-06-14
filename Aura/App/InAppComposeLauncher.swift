import Foundation
import Observation

/// Bridges in-app note composing to the Library window. `LibraryWindowView`
/// sets `present` on appear (now: start an inline draft) and clears it on
/// disappear, and a window-key observer keeps `isLibraryKey` current.
/// `AppDelegate.routeNewNote` consults this: when the Library is the key window
/// it composes in-app; otherwise it falls back to the notch.
///
/// `draft` and `autofocusItemID` are the in-place editing channel (observed, so
/// the grid reacts): `draft` is a transient, unsaved note prepended to the grid
/// and edited like any card; `autofocusItemID` tells exactly one card to grab
/// the caret on appear.
@MainActor
@Observable
final class InAppComposeLauncher {
    /// Starts an inline note draft. Non-nil only while the Library is alive.
    @ObservationIgnored var present: (() -> Void)?
    /// True while the Library window is the app's key window.
    @ObservationIgnored var isLibraryKey = false

    /// The current unsaved note draft, shown as a focused card at the top of the
    /// grid. Cleared when the draft is saved or discarded.
    var draft: Item?
    /// The item id that should grab the caret when its card next appears.
    var autofocusItemID: String?
}
