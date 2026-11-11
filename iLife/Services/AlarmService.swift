import Foundation
import UserNotifications
import WidgetKit

/// Workout / water / meal / medicine alarms as repeating local notifications.
/// (Phase 2: move workout alarms to AlarmKit so they ring through Silent mode like the Clock app.)
enum AlarmService {
    static func schedule(_ alarm: AppAlarm) {
        cancel(alarm)
        guard alarm.isOn else { return }
        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body = body(for: alarm.label)
        content.sound = .default

        let days = alarm.weekdays.isEmpty ? [0] : alarm.weekdays
        let center = UNUserNotificationCenter.current()
        for day in days {
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            if day > 0 { comps.weekday = day }
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "\(alarm.notificationID)-\(day)", content: content, trigger: trigger))
        }
    }

    static func cancel(_ alarm: AppAlarm) {
        let ids = (0...7).map { "\(alarm.notificationID)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func body(for label: String) -> String {
        let l = label.lowercased()
        if l.contains("water") { return "Time for a glass of water 💧" }
        if l.contains("med") { return "Time to take your medicine 💊" }
        if l.contains("meal") || l.contains("lunch") || l.contains("dinner") || l.contains("breakfast") { return "Log your meal in iLife 🍽" }
        return "Your workout starts now. Let's go 💪"
    }
}

enum WidgetSync {
    static func push(_ snapshot: TodaySnapshot) {
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
