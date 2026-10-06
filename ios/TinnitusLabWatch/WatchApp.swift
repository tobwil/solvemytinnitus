import HealthKit
import SwiftUI
import TinnitusCore
import WatchConnectivity
import WatchKit
import WidgetKit

@main
struct TinnitusLabWatchApp: App {
    @State private var link = PhoneLink.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                WatchCheckInView()
                WatchBreathView()
                WatchSoundView()
            }
            .tabViewStyle(.verticalPage)
            .environment(link)
            .onAppear { link.activate() }
        }
    }
}

private enum WColor {
    static let sound = Color(red: 0.37, green: 0.92, blue: 0.83)
    static let tin = Color(red: 0.98, green: 0.75, blue: 0.14)
    static let mind = Color(red: 0.65, green: 0.55, blue: 0.98)
}

// MARK: - Phone link

/// WatchConnectivity: check-ins and breath sessions go to the phone with guaranteed delivery
/// (transferUserInfo); start/stop of sound needs the phone to be reachable.
@MainActor
@Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()
    var checkinsToday = 0
    var tasksDone = 0
    var tasksTotal = 0
    var playing = false
    var reachable = false
    private var day = ""

    static let groupDefaults = UserDefaults(suiteName: TinnitusSchema.appGroup) ?? .standard

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        load()
    }

    func sendCheckIn(loudness: Double, distress: Double) {
        WCSession.default.transferUserInfo(["type": "checkin", "loudness": loudness, "distress": distress, "ts": Date.now])
        if day != Day.key() { day = Day.key(); checkinsToday = 0 }
        checkinsToday += 1
        save()
    }

    func sendBreath(seconds: Double) {
        WCSession.default.transferUserInfo(["type": "breath", "durationS": seconds, "ts": Date.now])
    }

    func startSound(minutes: Int) {
        WCSession.default.sendMessage(["type": "startSound", "mode": TherapyMode.enrichment.rawValue, "minutes": minutes], replyHandler: nil)
        playing = true
    }

    func stopSound() {
        WCSession.default.sendMessage(["type": "stopSound"], replyHandler: nil)
        playing = false
    }

    private func apply(_ ctx: [String: Any]) {
        day = ctx["day"] as? String ?? Day.key()
        checkinsToday = ctx["checkinsToday"] as? Int ?? checkinsToday
        tasksDone = ctx["tasksDone"] as? Int ?? tasksDone
        tasksTotal = ctx["tasksTotal"] as? Int ?? tasksTotal
        if let p = ctx["playing"] as? Bool { playing = p }
        save()
    }

    /// Shared with the complication.
    private func save() {
        let d = Self.groupDefaults
        d.set(day, forKey: "watch.day")
        d.set(checkinsToday, forKey: "watch.checkins")
        d.set(tasksDone, forKey: "watch.tasksDone")
        d.set(tasksTotal, forKey: "watch.tasksTotal")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load() {
        let d = Self.groupDefaults
        day = d.string(forKey: "watch.day") ?? ""
        checkinsToday = day == Day.key() ? d.integer(forKey: "watch.checkins") : 0
        tasksDone = d.integer(forKey: "watch.tasksDone")
        tasksTotal = d.integer(forKey: "watch.tasksTotal")
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = SendableContext(session.receivedApplicationContext)
        let r = session.isReachable
        Task { @MainActor in
            self.reachable = r
            self.apply(ctx.value)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let ctx = SendableContext(applicationContext)
        Task { @MainActor in self.apply(ctx.value) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.reachable = r }
    }
}

struct SendableContext: @unchecked Sendable {
    let value: [String: Any]
    init(_ v: [String: Any]) { value = v }
}

// MARK: - Check-in

/// Two scales, Digital Crown or tap, ten seconds.
struct WatchCheckInView: View {
    @Environment(PhoneLink.self) private var link
    @State private var step = 0
    @State private var loudness = 5.0
    @State private var distress = 5.0
    @State private var saved = false

    var body: some View {
        VStack(spacing: 6) {
            if saved {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(WColor.tin)
                Text("Notiert").font(.headline)
                Text("Heute \(link.checkinsToday)×").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(step == 0 ? "Wie laut ist er?" : "Wie belastend?").font(.headline)
                Text("\(Int(step == 0 ? loudness : distress))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(step == 0 ? WColor.tin : WColor.mind)
                    .focusable()
                    .digitalCrownRotation(step == 0 ? $loudness : $distress, from: 0, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                Text(step == 0 ? "0 still · 10 extrem" : "0 gar nicht · 10 extrem").font(.caption2).foregroundStyle(.secondary)
                Button(step == 0 ? "Weiter" : "Speichern") {
                    if step == 0 { step = 1 } else {
                        link.sendCheckIn(loudness: loudness, distress: distress)
                        WKInterfaceDevice.current().play(.success)
                        saved = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            saved = false
                            step = 0
                        }
                    }
                }
                .tint(step == 0 ? WColor.tin : WColor.mind)
            }
        }
        .containerBackground(WColor.tin.gradient.opacity(0.25), for: .tabView)
    }
}

// MARK: - Breath

/// Breath pacing with haptics on the wrist: 4 s in, 6 s out, without looking at the display.
struct WatchBreathView: View {
    @Environment(PhoneLink.self) private var link
    @State private var minutes = 3
    @State private var running = false
    @State private var inhale = true
    @State private var left = 0.0
    @State private var task: Task<Void, Never>?
    @State private var session: WKExtendedRuntimeSession?
    private let health = HKHealthStore()

    var body: some View {
        VStack(spacing: 8) {
            if running {
                Circle()
                    .fill(WColor.mind.opacity(0.5))
                    .frame(width: inhale ? 110 : 60, height: inhale ? 110 : 60)
                    .animation(.easeInOut(duration: inhale ? 4 : 6), value: inhale)
                    .frame(height: 115)
                Text(inhale ? "Ein" : "Aus").font(.title3.bold())
                Text(Format.duration(left)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button("Stopp") { stop(save: true) }.tint(WColor.mind)
            } else {
                Text("Ruhiger Atem").font(.headline)
                Picker("Dauer", selection: $minutes) {
                    Text("1 min").tag(1)
                    Text("3 min").tag(3)
                    Text("5 min").tag(5)
                }
                .frame(height: 60)
                Button("Starten") { start() }.tint(WColor.mind)
            }
        }
        .containerBackground(WColor.mind.gradient.opacity(0.25), for: .tabView)
    }

    private func start() {
        running = true
        left = Double(minutes * 60)
        // keeps haptics running with the wrist down
        let s = WKExtendedRuntimeSession()
        s.start()
        session = s
        let started = Date.now
        task = Task {
            while left > 0 && !Task.isCancelled {
                inhale = true
                WKInterfaceDevice.current().play(.directionUp)
                try? await Task.sleep(for: .seconds(4))
                left -= 4
                if Task.isCancelled || left <= 0 { break }
                inhale = false
                WKInterfaceDevice.current().play(.directionDown)
                try? await Task.sleep(for: .seconds(6))
                left -= 6
            }
            if !Task.isCancelled { stop(save: true, started: started) }
        }
    }

    private func stop(save: Bool, started: Date? = nil) {
        task?.cancel()
        session?.invalidate()
        session = nil
        let duration = Double(minutes * 60) - max(0, left)
        running = false
        WKInterfaceDevice.current().play(.success)
        guard save, duration >= 20 else { return }
        link.sendBreath(seconds: duration)
        let end = Date.now
        let type = HKCategoryType(.mindfulSession)
        Task {
            try? await health.requestAuthorization(toShare: [type], read: [])
            try? await health.save(HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue, start: end.addingTimeInterval(-duration), end: end))
        }
    }
}

// MARK: - Sound remote

struct WatchSoundView: View {
    @Environment(PhoneLink.self) private var link
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.rain").font(.title).foregroundStyle(WColor.sound)
            Text("Klanganreicherung").font(.headline)
            Text(link.reachable ? "läuft auf dem iPhone" : "iPhone nicht erreichbar").font(.caption2).foregroundStyle(.secondary)
            if link.playing {
                Button("Beenden") { link.stopSound() }.tint(WColor.sound)
            } else {
                Button("30 min starten") { link.startSound(minutes: 30) }.tint(WColor.sound).disabled(!link.reachable)
                Button("8 h (Schlaf)") { link.startSound(minutes: 480) }.disabled(!link.reachable)
            }
            Text("Heute \(link.tasksDone)/\(link.tasksTotal) Aufgaben").font(.caption2).foregroundStyle(.secondary)
        }
        .containerBackground(WColor.sound.gradient.opacity(0.25), for: .tabView)
    }
}
