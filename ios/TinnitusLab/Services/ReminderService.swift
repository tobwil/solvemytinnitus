import Foundation
import TinnitusCore
import UserNotifications

/// Ecological momentary assessment: check-in reminders at random times inside morning/noon/evening
/// windows (random to avoid expectation effects), never at night. Plus session, weekly and RI-pause reminders.
@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()
    private let center = UNUserNotificationCenter.current()

    /// Windows (start hour, end hour): morning, noon, evening.
    static let windows: [(String, Int, Int)] = [("Morgens", 8, 11), ("Mittags", 12, 15), ("Abends", 17, 21)]
    static let daysAhead = 7
    static let checkinCategory = "CHECKIN"

    /// Deep link handler set by the app. A route that arrives before it is set (cold launch from a
    /// notification) is kept and delivered as soon as the handler is installed.
    var onOpen: (@MainActor (AppRoute) -> Void)? {
        didSet {
            if let onOpen, let route = pendingRoute {
                pendingRoute = nil
                onOpen(route)
            }
        }
    }
    private var pendingRoute: AppRoute?

    /// Must run before the app finishes launching (App `init`), otherwise the tap that cold-launches
    /// the app is never delivered.
    func setUp() {
        center.delegate = self
        let open = UNNotificationAction(identifier: "open", title: "Jetzt einschätzen", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.checkinCategory, actions: [open], intentIdentifiers: [])])
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Re-plans all reminders from the settings. Called on launch and whenever settings change.
    func reschedule(checkins: Bool, windows: [Int], sessions: Bool, lesson: Bool = false, weekly: Bool = true) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("ema.") || $0.hasPrefix("session.") || $0.hasPrefix("weekly.") || $0.hasPrefix("lesson.") })
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let cal = Calendar.current
        let now = Date.now
        if checkins {
            for d in 0..<Self.daysAhead {
                guard let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now)) else { continue }
                for w in windows where w < Self.windows.count {
                    let (_, a, b) = Self.windows[w]
                    let minute = Int.random(in: (a * 60)..<(b * 60))
                    guard let at = cal.date(byAdding: .minute, value: minute, to: day), at > now else { continue }
                    let c = UNMutableNotificationContent()
                    c.title = "Wie laut ist er gerade?"
                    c.body = "Zehn Sekunden: Lautheit und Belastung einschätzen."
                    c.categoryIdentifier = Self.checkinCategory
                    c.userInfo = ["route": AppRoute.checkin.url.absoluteString]
                    c.interruptionLevel = .active
                    c.threadIdentifier = "checkin"
                    add("ema.\(Day.key(day)).\(w)", c, at: at)
                }
            }
        }
        if sessions {
            for (i, hour) in [10, 18].enumerated() {
                let c = UNMutableNotificationContent()
                c.title = "Reset-Sitzung"
                c.body = "10–15 Minuten mit deinem besten Klang aus dem Labor."
                c.userInfo = ["route": AppRoute.sound(.reset).url.absoluteString]
                c.threadIdentifier = "session"
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
                try? await center.add(UNNotificationRequest(identifier: "session.\(i)", content: c, trigger: trigger))
            }
        }
        if lesson {
            let c = UNMutableNotificationContent()
            c.title = "Kopf-Training"
            c.body = "Eine Lektion oder Übung, 5–10 Minuten. Regelmäßigkeit wirkt."
            c.userInfo = ["route": AppRoute.mind.url.absoluteString]
            c.threadIdentifier = "lesson"
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9, minute: 0), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "lesson.0", content: c, trigger: trigger))
        }
        if weekly {
            let c = UNMutableNotificationContent()
            c.title = "Wochen-Check"
            c.body = "Acht Fragen zur letzten Woche, zwei Minuten."
            c.userInfo = ["route": AppRoute.progress(.weekly).url.absoluteString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 19, minute: 0, weekday: 1), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "weekly.0", content: c, trigger: trigger))
        }
    }

    /// RI lab: tell the user when the tinnitus should be back at baseline.
    func scheduleRIPause(minutes: Double = 4) {
        let c = UNMutableNotificationContent()
        c.title = "Bereit für den nächsten Durchgang"
        c.body = "Dein Tinnitus sollte wieder auf Ausgangsniveau sein."
        c.userInfo = ["route": AppRoute.ri.url.absoluteString]
        c.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: "ri.pause", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: minutes * 60, repeats: false))
        center.add(req)
    }

    func cancelRIPause() { center.removePendingNotificationRequests(withIdentifiers: ["ri.pause"]) }

    private func add(_ id: String, _ content: UNNotificationContent, at date: Date) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    // MARK: Delegate

    private func open(_ link: String?) {
        guard let link, let url = URL(string: link), let route = AppRoute(url: url) else { return }
        if let onOpen { onOpen(route) } else { pendingRoute = route }
    }

    // Completion-handler variants on purpose: the `async` variants run off the main thread, and UIKit
    // then completes the notification response off the main thread, which crashes with
    // "Call must be made on main thread" when a notification is tapped. These are called on the main
    // thread and complete synchronously.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = response.notification.request.content.userInfo["route"] as? String
        Task { @MainActor in self.open(link) }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
