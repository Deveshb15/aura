import Foundation
import UserNotifications

/// Handles reminder notifications while Aura is running: presents them even when
/// the app is frontmost, and routes a click to the Library window. Held strongly
/// by `AppDelegate` because `UNUserNotificationCenter.delegate` is weak.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let dataStore: DataStore
    private let openLibrary: @MainActor () -> Void

    init(dataStore: DataStore, openLibrary: @escaping @MainActor () -> Void) {
        self.dataStore = dataStore
        self.openLibrary = openLibrary
    }

    /// Fires while the app is running (including frontmost). Show banner + sound
    /// so the reminder isn't swallowed, and mark the item delivered.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        await MainActor.run { dataStore.markReminderDelivered(itemID: id) }
        return [.banner, .sound, .badge]
    }

    /// Fires when the user clicks the notification (launches/foregrounds Aura).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        await MainActor.run {
            dataStore.markReminderDelivered(itemID: id)
            openLibrary()
        }
    }
}
