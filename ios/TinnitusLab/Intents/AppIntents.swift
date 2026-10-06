import AppIntents
import Foundation
import TinnitusCore

@MainActor
enum SoundIntentSink {
    static var handler: (@MainActor (TherapyMode, Int, EntryOrigin) -> Bool)?
}

enum SoundModeEntity: String, AppEnum {
    case enrichment, reset, notched, cr

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Klangprogramm"
    static let caseDisplayRepresentations: [SoundModeEntity: DisplayRepresentation] = [
        .enrichment: "Klanganreicherung",
        .reset: "Reset-Sitzung",
        .notched: "Notched Sound",
        .cr: "CR-Neuromodulation",
    ]

    var mode: TherapyMode { TherapyMode(rawValue: rawValue)! }
}

/// "Hey Siri, starte Klanganreicherung für 30 Minuten" – also usable in a sleep focus automation.
/// AudioPlaybackIntent lets iOS run it in the background and start audio.
struct StartSoundIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Klangprogramm starten"
    static let description = IntentDescription("Startet ein Klangprogramm, zugeschnitten auf deine gemessene Tinnitus-Frequenz, mit Sleep-Timer.")

    @Parameter(title: "Programm", default: .enrichment)
    var program: SoundModeEntity

    @Parameter(title: "Minuten", default: 30, inclusiveRange: (5, 480))
    var minutes: Int

    /// Set when started from the sleep focus automation: no ratings.
    @Parameter(title: "Schlafmodus", default: false)
    var sleep: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$program) für \(\.$minutes) Minuten starten") { \.$sleep }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let h = SoundIntentSink.handler, h(program.mode, minutes, sleep ? .sleepFocus : .siri) else {
            return .result(dialog: "Bitte miss zuerst deine Tinnitus-Frequenz (Ich › Messungen).")
        }
        return .result(dialog: "\(SoundContent.mode(program.mode).title) läuft für \(minutes) Minuten.")
    }
}

struct StopSoundIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Klangprogramm beenden"

    @MainActor
    func perform() async throws -> some IntentResult {
        SessionController.shared.finish(auto: false)
        return .result()
    }
}

struct OpenBreathingIntent: AppIntent {
    static let title: LocalizedStringResource = "Atemübung öffnen"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.tool("breath").url))
    }
}

struct OpenSpikePlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Notfallplan öffnen"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.tool("plan").url))
    }
}

struct TinnitusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSoundIntent(), phrases: [
            "Starte \(\.$program) in \(.applicationName)",
            "Starte Klanganreicherung mit \(.applicationName)",
            "\(.applicationName) Klang starten",
        ], shortTitle: "Klang starten", systemImageName: "cloud.rain")
        AppShortcut(intent: LogCheckInIntent(), phrases: [
            "Tinnitus Check-in in \(.applicationName)",
            "Wie laut ist mein Tinnitus in \(.applicationName)",
        ], shortTitle: "Check-in", systemImageName: "waveform.path.ecg")
        AppShortcut(intent: StopSoundIntent(), phrases: ["Stoppe \(.applicationName)"], shortTitle: "Klang beenden", systemImageName: "stop.fill")
        AppShortcut(intent: OpenBreathingIntent(), phrases: ["Atemübung in \(.applicationName)"], shortTitle: "Atemübung", systemImageName: "wind")
        AppShortcut(intent: OpenSpikePlanIntent(), phrases: ["Notfallplan in \(.applicationName)"], shortTitle: "Notfallplan", systemImageName: "shield")
        AppShortcut(intent: OpenBodyProgramIntent(), phrases: ["Kiefer lockern mit \(.applicationName)", "\(.applicationName) Körper-Programm"], shortTitle: "Körper-Programm", systemImageName: "figure.cooldown")
    }
}

/// Focus filter (02 §10): in the "Schlafen" focus the app only offers sound enrichment and breathing.
struct SleepFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Tinnitus Lab"
    static let description: IntentDescription? = IntentDescription("Im Schlafen-Fokus zeigt die App nur Klanganreicherung und Atemübung.")

    @Parameter(title: "Nur Schlaf-Funktionen", default: true)
    var sleepOnly: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: sleepOnly ? "Nur Klanganreicherung und Atemübung" : "Alle Funktionen")
    }

    func perform() async throws -> some IntentResult {
        SharedStore.defaults.set(sleepOnly, forKey: SharedStore.focusSleepKey)
        return .result()
    }
}

/// Evening routine building block (06): open a body programme from Shortcuts.
struct OpenBodyProgramIntent: AppIntent {
    static let title: LocalizedStringResource = "Körper-Programm öffnen"
    static let openAppWhenRun = true

    enum Program: String, AppEnum {
        case neck, jaw
        static let typeDisplayRepresentation: TypeDisplayRepresentation = "Programm"
        static let caseDisplayRepresentations: [Program: DisplayRepresentation] = [.neck: "Nacken und Schultern", .jaw: "Kiefer und Gesicht"]
    }

    @Parameter(title: "Programm", default: .jaw)
    var program: Program

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.body(BodyProgramID(rawValue: program.rawValue)).url))
    }
}
