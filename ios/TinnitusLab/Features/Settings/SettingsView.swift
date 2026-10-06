import AVFoundation
import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query private var settingsList: [AppSettings]
    @Query private var checkins: [CheckIn]
    @Query private var sessions: [TherapySession]
    @Query private var ri: [RITrial]
    @Query private var journal: [JournalEntry]
    @State private var engine = AudioEngine.shared
    @State private var exportDoc: JSONDocument?
    @State private var showImport = false
    @State private var confirmDelete = false
    @State private var importError: String?
    @State private var iCloud = SharedStore.iCloudSync

    var body: some View {
        if let s = settingsList.first {
            @Bindable var s = s
            Screen {
                ScreenHeader(eyebrow: "Einstellungen", title: "Einstellungen & Daten", lead: nil)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profil").font(.titleM)
                    TextField("Name (optional)", text: $s.name)
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
                    Text("Bevorzugtes Ohr").font(.subheadline).foregroundStyle(Theme.text2)
                    Picker("Ohr", selection: $s.preferredEar) { ForEach(Ear.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    LabeledSlider(label: "Standard-Breite der Notch", value: $s.notchWidthOctaves, range: 0.5...2, step: 0.25, format: { "\(Format.decimal($0, digits: 2)) Okt." })
                    LabeledSlider(label: "Tagesziel Klangzeit", value: Binding(get: { Double(s.dailyGoalMin) }, set: { s.dailyGoalMin = Int($0) }), range: 10...180, step: 10, format: { "\(Int($0)) min" })
                    Toggle("RI-Labor verblindet", isOn: $s.blindRi)
                    Toggle("Anleitungen vorlesen", isOn: $s.speakTTS)
                    if s.speakTTS { VoiceHint() }
                }
                .tint(Theme.sound)
                .card()

                SectionHeader("Erinnerungen")
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Check-ins zu zufälligen Zeiten", isOn: $s.remindersOn)
                    if s.remindersOn {
                        ForEach(Array(ReminderService.windows.enumerated()), id: \.offset) { i, w in
                            Toggle("\(w.0) (\(w.1)–\(w.2) Uhr)", isOn: Binding(get: { s.reminderWindows.contains(i) }, set: { on in
                                if on { s.reminderWindows = Array(Set(s.reminderWindows + [i])).sorted() } else { s.reminderWindows.removeAll { $0 == i } }
                            }))
                            .font(.subheadline)
                            .padding(.leading, 12)
                        }
                    }
                    Toggle("Reset-Sitzungen (10 und 18 Uhr)", isOn: $s.sessionRemindersOn)
                    Toggle("Kopf-Training des Tages (9 Uhr)", isOn: $s.lessonReminderOn)
                    Text("Zufällige Zeiten vermeiden Erwartungseffekte. Nachts gibt es keine Erinnerung; Fokus-Modi werden respektiert.").font(.caption).foregroundStyle(Theme.text3)
                }
                .tint(Theme.sound)
                .card()
                .onChange(of: s.remindersOn) { _, _ in Task { await reschedule(s) } }
                .onChange(of: s.reminderWindows) { _, _ in Task { await reschedule(s) } }
                .onChange(of: s.sessionRemindersOn) { _, _ in Task { await reschedule(s) } }
                .onChange(of: s.lessonReminderOn) { _, _ in Task { await reschedule(s) } }

                SectionHeader("Kopfhörer & Hörschutz")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Aktuelles Gerät")
                        Spacer()
                        Text(engine.route.name.isEmpty ? engine.deviceKind.label : "\(engine.route.name) · \(engine.deviceKind.label)").foregroundStyle(Theme.text2)
                    }
                    .font(.subheadline)
                    if let off = s.calibrationOffsets[engine.deviceKind.rawValue] {
                        Text("Persönlicher Kalibrier-Offset (1-kHz-Anker): \(Format.signed(off)) dB").font(.caption).foregroundStyle(Theme.text2)
                    }
                    if let p = s.calibrationOffsets[Plausibility.key(engine.deviceKind)] {
                        Text("Abgleich mit Health-Kopfhörerdosis: \(Format.signed(p)) dB").font(.caption).foregroundStyle(Theme.text2)
                    }
                    Toggle("Haltungs-Hinweis bei Klangsitzungen (AirPods)", isOn: $s.postureHint)
                        .font(.subheadline)
                    LabeledSlider(label: "App-Lautstärke", value: $s.masterVolume, range: 0.05...1, step: 0.01, format: { "\(Int($0 * 100)) %" })
                        .onChange(of: s.masterVolume) { _, v in engine.masterVolume = v }
                    Button { model.open(.headphones) } label: { Label("Kopfhörer und Lautstärke neu einrichten", systemImage: "headphones") }
                        .buttonStyle(.ghost())
                    Text("Pegel-Deckel: Klänge max. ca. 85 dB SPL, Messsignale max. 80 dB SPL und höchstens MML + 15 dB. Kalibrierprofile sind Schätzwerte; für unbekannte Kopfhörer wird konservativ gerechnet.")
                        .font(.caption).foregroundStyle(Theme.text3)
                }
                .tint(Theme.sound)
                .card()

                SectionHeader("Apple Health")
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Health verwenden", isOn: Binding(get: { s.useHealthKit }, set: { on in
                        if on {
                            Task {
                                s.useHealthKit = await HealthService.shared.requestAuthorization()
                                if s.useHealthKit { await HealthService.shared.sync(into: ctx) }
                            }
                        } else {
                            s.useHealthKit = false
                        }
                    }))
                    .disabled(!HealthService.shared.isAvailable)
                    Text("Liest Audiogramm, Schlaf, HRV, Ruhepuls, Atemfrequenz, Umgebungs- und Kopfhörerlärm; schreibt Achtsamkeitsminuten. Einzelne Datentypen lassen sich in der Health-App verwalten.")
                        .font(.caption).foregroundStyle(Theme.text3)
                    Label {
                        Text("**Garmin, Oura & Co.:** Schalte in der Hersteller-App die Verbindung zu Apple Health ein (Garmin Connect › Einstellungen › Apple Health). Garmin überträgt Schlaf, Ruhepuls und Schritte, aber keine HRV und keinen Stress-Wert – die App nutzt dann den Ruhepuls als Stressmarker.")
                    } icon: { Image(systemName: "applewatch.side.right") }
                    .font(.caption).foregroundStyle(Theme.text2)
                }
                .tint(Theme.sound)
                .card()

                SectionHeader("Daten")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alles liegt auf diesem Gerät und – wenn iCloud aktiv ist – in deiner privaten iCloud. Kein Server, keine Konten, kein Tracking. \(checkins.count) Check-ins, \(sessions.count) Sitzungen, \(ri.count) RI-Durchgänge, \(journal.count) Tagebucheinträge.")
                        .font(.subheadline).foregroundStyle(Theme.text2)
                    Toggle("iCloud-Synchronisierung (iPhone, iPad, Watch)", isOn: $iCloud)
                        .tint(Theme.sound)
                        .onChange(of: iCloud) { _, v in SharedStore.iCloudSync = v }
                    if iCloud != SharedStore.iCloudSyncAtLaunch {
                        Text("Wird beim nächsten Start der App aktiv.").font(.caption).foregroundStyle(Theme.warn)
                    }
                    HStack(spacing: 10) {
                        Button { export() } label: { Label("Export", systemImage: "square.and.arrow.up") }.buttonStyle(.ghost())
                        Button { showImport = true } label: { Label("Import", systemImage: "square.and.arrow.down") }.buttonStyle(.ghost())
                    }
                    Text("JSON im Format der Web-App: Daten lassen sich zwischen Web-App und iOS-App hin- und hertragen.").font(.caption).foregroundStyle(Theme.text3)
                    if let importError { Text(importError).font(.caption).foregroundStyle(Theme.warn) }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Alle Daten löschen", systemImage: "trash") }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .card()

                Text("Tinnitus Lab · kein Medizinprodukt · ersetzt keine ärztliche Behandlung").font(.caption).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { try? ctx.save(); DataActions.refreshSnapshot(ctx) }
            .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }), document: exportDoc, contentType: .json,
                          defaultFilename: "tinnitus-lab-\(Day.key()).json") { _ in exportDoc = nil }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    try DataTransfer.importData(data, into: ctx)
                    DataActions.applyAudioSettings(ctx.settings())
                    DataActions.refreshSnapshot(ctx)
                    model.showToast("Daten importiert")
                } catch {
                    importError = "Import fehlgeschlagen: \(error.localizedDescription)"
                }
            }
            .alert("Alle Daten löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Alles löschen", role: .destructive) {
                    SessionController.shared.finish(auto: false)
                    try? ctx.deleteEverything()
                    _ = ctx.settings()
                    try? ctx.save()
                    DataActions.refreshSnapshot(ctx)
                    model.showToast("Alle Daten gelöscht")
                }
            } message: {
                Text("Check-ins, Sitzungen, Messungen und Tagebuch werden auf diesem Gerät\(SharedStore.iCloudSync ? " und in deiner iCloud" : "") unwiderruflich gelöscht. Exportiere vorher, wenn du sie behalten willst.")
            }
        }
    }

    private func export() {
        if let data = try? DataTransfer.exportData(from: ctx) { exportDoc = JSONDocument(data: data) }
    }

    private func reschedule(_ s: AppSettings) async {
        if (s.remindersOn || s.sessionRemindersOn || s.lessonReminderOn), !(await ReminderService.shared.requestPermission()) {
            s.remindersOn = false
            s.sessionRemindersOn = false
            s.lessonReminderOn = false
            return
        }
        await ReminderService.shared.reschedule(checkins: s.remindersOn, windows: s.reminderWindows, sessions: s.sessionRemindersOn, lesson: s.lessonReminderOn)
    }
}

struct JSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Which voice reads the exercises, and how to get a natural-sounding one.
private struct VoiceHint: View {
    @State private var speech = Speech.shared
    @State private var refresh = 0

    var body: some View {
        let q = speech.quality
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stimme: \(speech.voiceName)").font(.subheadline)
                Spacer()
                Chip(q == .premium ? "Premium" : q == .enhanced ? "Erweitert" : "Kompakt", tone: q == .default ? .warn : .good)
            }
            if q != .premium {
                Text("Für eine natürliche Stimme lade einmalig eine kostenlose Premium-Stimme (läuft komplett auf dem Gerät): **Einstellungen › Bedienungshilfen › Gesprochene Inhalte › Stimmen › Deutsch** › z. B. *Anna (Premium)*. Die App nimmt sie danach automatisch.")
                    .font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Probehören") { Speech.shared.say("Atme ruhig ein. Und langsam wieder aus.") }
                    .buttonStyle(.ghost(Theme.accent))
                if q != .premium {
                    Button("Einstellungen öffnen") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        .buttonStyle(.ghost())
                }
            }
        }
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in refresh += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh += 1 }
    }
}
