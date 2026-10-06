#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Live Activity / Dynamic Island during a sound session: remaining time, phase (sound/silence), stop.
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        /// When the timer ends (nil = open-ended).
        var endDate: Date?
        /// Session start (for open-ended count-up).
        var startDate: Date
        var paused: Bool
        /// Remaining seconds when paused.
        var remainingWhenPaused: Double?
        /// Reset sessions: true while the silence phase runs.
        var silence: Bool
    }

    var title: String
    var symbol: String
}
#endif
