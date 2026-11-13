import Foundation
import UserNotifications
import Domain

/// Настройки уведомлений хранятся на устройстве, как настройки календаря.
extension NotificationSettings {
    private static let key = "notificationSettings"

    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(NotificationSettings.self, from: data) else { return NotificationSettings() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Локальные уведомления (12D): разрешение и полная замена расписания после каждого обновления данных.
@MainActor
final class Notifier {
    private let center = UNUserNotificationCenter.current()

    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }

    /// Разрешение спрашивается при первом включении любого уведомления (решение 13.11.2026).
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func replace(with plans: [PlannedNotification]) async {
        center.removeAllPendingNotificationRequests()
        guard await status() == .authorized else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let request = UNNotificationRequest(identifier: plan.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}
