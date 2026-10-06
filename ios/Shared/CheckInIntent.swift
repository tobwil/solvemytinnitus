import AppIntents
import Foundation
import TinnitusCore

/// The app sets this at launch so check-ins from Siri/Shortcuts go straight into SwiftData.
/// In the widget process it stays nil and check-ins are queued in the app group.
@MainActor
enum CheckInSink {
    static var handler: (@MainActor (Double, Double, EntryOrigin) -> Void)?
}

/// "Wie laut ist mein Tinnitus?" – logs a check-in without opening the app.
struct LogCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Tinnitus-Check-in"
    static let description = IntentDescription("Erfasst, wie laut dein Tinnitus gerade ist und wie sehr er dich belastet.")
    static let openAppWhenRun = false

    @Parameter(title: "Lautheit", description: "0 = nicht hörbar, 10 = extrem laut", inclusiveRange: (0, 10))
    var loudness: Int

    @Parameter(title: "Belastung", description: "0 = gar nicht, 10 = extrem", inclusiveRange: (0, 10))
    var distress: Int

    init() {}

    init(loudness: Int, distress: Int) {
        self.loudness = loudness
        self.distress = distress
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Lautheit \(\.$loudness), Belastung \(\.$distress)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let l = Double(min(10, max(0, loudness)))
        let d = Double(min(10, max(0, distress)))
        if let h = CheckInSink.handler {
            h(l, d, .siri)
        } else {
            SharedStore.enqueue(PendingCheckIn(ts: .now, loudness: l, distress: d, origin: .widget))
        }
        return .result(dialog: "Notiert: Lautheit \(loudness), Belastung \(distress).")
    }
}

/// Stop button in the Live Activity / Dynamic Island. LiveActivityIntents run in the app process.
@MainActor
enum SessionStopSink {
    static var handler: (@MainActor () -> Void)?
}

struct StopSessionLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Klang beenden"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        SessionStopSink.handler?()
        return .result()
    }
}
