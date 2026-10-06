import Foundation
import TinnitusCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Small snapshot the app writes into the app group for widgets (no SwiftData/CloudKit in extensions).
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var day: String
    var checkinsToday: Int
    var lastLoudness: Double?
    var tasksDone: Int
    var tasksTotal: Int
    var soundMinutesToday: Int
    var programDay: Int
    var programWeek: Int
    var spikePlan: String
    var tinnitusHz: Double?
    var updatedAt: Date

    static let empty = WidgetSnapshot(day: Day.key(), checkinsToday: 0, lastLoudness: nil, tasksDone: 0, tasksTotal: 4, soundMinutesToday: 0, programDay: 1, programWeek: 1, spikePlan: "", tinnitusHz: nil, updatedAt: .now)

    /// Counts reset at midnight even if the app was not opened.
    var normalized: WidgetSnapshot {
        guard day != Day.key() else { return self }
        var s = self
        s.day = Day.key()
        s.checkinsToday = 0
        s.soundMinutesToday = 0
        s.tasksDone = 0
        return s
    }
}

/// A check-in recorded outside the app process (widget, Siri without app, watch) waiting for import.
struct PendingCheckIn: Codable, Sendable {
    var ts: Date
    var loudness: Double
    var distress: Double
    var origin: EntryOrigin
}

enum SharedStore {
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: TinnitusSchema.appGroup) ?? .standard
    private static let snapshotKey = "widget.snapshot"
    private static let pendingKey = "pending.checkins"

    static var snapshot: WidgetSnapshot {
        get {
            guard let d = defaults.data(forKey: snapshotKey), let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: d) else { return .empty }
            return s.normalized
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { defaults.set(d, forKey: snapshotKey) }
        }
    }

    static func enqueue(_ c: PendingCheckIn) {
        var list = pending
        list.append(c)
        if let d = try? JSONEncoder().encode(list) { defaults.set(d, forKey: pendingKey) }
        var s = snapshot
        s.checkinsToday += 1
        s.lastLoudness = c.loudness
        snapshot = s
        reloadWidgets()
    }

    static var pending: [PendingCheckIn] {
        guard let d = defaults.data(forKey: pendingKey), let l = try? JSONDecoder().decode([PendingCheckIn].self, from: d) else { return [] }
        return l
    }

    static func drainPending() -> [PendingCheckIn] {
        let l = pending
        defaults.removeObject(forKey: pendingKey)
        return l
    }

    /// iCloud sync (CloudKit) is optional; applied at the next launch because the store is opened once.
    static var iCloudSync: Bool {
        get { defaults.object(forKey: "icloud.sync") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "icloud.sync") }
    }

    /// Set by the "Schlafen" focus filter.
    static let focusSleepKey = "focus.sleepOnly"

    /// Value used when the store was opened.
    nonisolated(unsafe) static let iCloudSyncAtLaunch = iCloudSync

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
