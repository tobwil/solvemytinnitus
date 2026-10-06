import Foundation
import TinnitusCore
import WatchConnectivity

/// iPhone side of WatchConnectivity: receives check-ins, breath sessions and start/stop requests from
/// the watch; sends today's progress for the complication. Works without iCloud (CloudKit sync adds
/// the rest when configured).
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    var onCheckIn: (@MainActor (Double, Double, Date) -> Void)?
    var onBreath: (@MainActor (Double, Date) -> Void)?
    var onStartSound: (@MainActor (TherapyMode, Int) -> Void)?
    var onStopSound: (@MainActor () -> Void)?

    private var lastSent: WidgetSnapshot?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendContext(_ snap: WidgetSnapshot, playing: Bool? = nil) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        guard snap != lastSent || playing != nil else { return }
        lastSent = snap
        var ctx: [String: Any] = [
            "checkinsToday": snap.checkinsToday,
            "tasksDone": snap.tasksDone,
            "tasksTotal": snap.tasksTotal,
            "programDay": snap.programDay,
            "day": snap.day,
        ]
        if let l = snap.lastLoudness { ctx["lastLoudness"] = l }
        if let playing { ctx["playing"] = playing }
        try? WCSession.default.updateApplicationContext(ctx)
    }

    fileprivate func handle(_ msg: [String: Any]) {
        switch msg["type"] as? String {
        case "checkin":
            guard let l = msg["loudness"] as? Double, let d = msg["distress"] as? Double else { return }
            onCheckIn?(l, d, (msg["ts"] as? Date) ?? .now)
        case "breath":
            onBreath?((msg["durationS"] as? Double) ?? 60, (msg["ts"] as? Date) ?? .now)
        case "startSound":
            let mode = (msg["mode"] as? String).flatMap(TherapyMode.init(rawValue:)) ?? .enrichment
            onStartSound?(mode, (msg["minutes"] as? Int) ?? 30)
        case "stopSound":
            onStopSound?()
        default:
            break
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let msg = SendableDict(userInfo)
        Task { @MainActor in WatchBridge.shared.handle(msg.value) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let msg = SendableDict(message)
        Task { @MainActor in WatchBridge.shared.handle(msg.value) }
    }
}

/// Property-list dictionaries from WatchConnectivity only contain plist types.
struct SendableDict: @unchecked Sendable {
    let value: [String: Any]
    init(_ v: [String: Any]) { value = v }
}
