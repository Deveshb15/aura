import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter` for one-shot reminder notifications keyed by
/// item id. Stateless. A second `add()` with the same identifier replaces the
/// pending request, so reschedule-on-edit and launch reconcile are idempotent.
enum ReminderScheduler {

    /// Outcome of a schedule attempt, so callers can hint when permission is off.
    enum ScheduleResult: Equatable {
        case scheduled
        case permissionDenied   // user denied → note still saved, surface a hint
        case failed(String)
        case noop               // fireDate in the past
    }

    private static var center: UNUserNotificationCenter { .current() }

    /// Ensures authorization (requests if not yet determined), then schedules a
    /// non-repeating calendar notification with identifier == `itemID`.
    @discardableResult
    static func schedule(itemID: String, title: String, body: String,
                         fireDate: Date) async -> ScheduleResult {
        guard fireDate > Date() else { return .noop }
        guard await ensureAuthorized() else { return .permissionDenied }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["itemID": itemID]
        content.threadIdentifier = "aura.reminders"

        // Match on y/m/d/h/m components (seconds dropped to avoid sub-minute drift).
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: itemID, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Cancels the pending and any already-delivered notification for an item.
    static func cancel(itemID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [itemID])
        center.removeDeliveredNotifications(withIdentifiers: [itemID])
    }

    /// Clears every Aura reminder notification (used by "delete all").
    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Current status WITHOUT prompting — for proactive UI hints in the composer.
    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Requests authorization if not yet determined; returns whether we may post.
    static func ensureAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Launch-time reconciliation. For each item with a reminder:
    ///  • future & not delivered, not already pending → re-add (idempotent),
    ///  • past & not delivered → return its id so the caller marks it delivered.
    static func reconcile(items: [Item]) async -> [String] {
        guard await ensureAuthorized() else { return [] }
        let now = Date()
        var toMarkDelivered: [String] = []
        let pendingIDs = Set(await center.pendingNotificationRequests().map(\.identifier))

        for item in items {
            guard let fireDate = item.reminderAt, item.reminderDelivered != true else { continue }
            if fireDate > now {
                if !pendingIDs.contains(item.id) {
                    _ = await schedule(itemID: item.id,
                                       title: reminderTitle(for: item),
                                       body: reminderBody(for: item),
                                       fireDate: fireDate)
                }
            } else {
                toMarkDelivered.append(item.id)
            }
        }
        return toMarkDelivered
    }

    // Shared copy builders so schedule + reconcile produce identical notifications.
    static func reminderTitle(for item: Item) -> String { "Reminder" }
    static func reminderBody(for item: Item) -> String {
        item.title ?? item.textContent ?? "You asked to be reminded."
    }
}
