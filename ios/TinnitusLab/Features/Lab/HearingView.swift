import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Hearing check: Apple's hearing test (HealthKit audiogram, 250 Hz–8 kHz) is picked up automatically;
/// the own test then only adds 10–16 kHz (otherwise 0.5–16 kHz), merged into one curve. Runs like
/// Apple's test: a circle pulses the whole time (it never shows when a tone plays), tones come at random
/// intervals and the user taps when they hear one. Wording per 08: "Hörcheck", not a clinical audiogram.
struct HearingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \HearingTest.date) private var tests: [HearingTest]
    @State private var engine = AudioEngine.shared

    enum Phase { case intro, practice, run, done }
    @State private var phase = Phase.intro
    @State private var ear: Ear = .left
    @State private var audiogram: HealthService.Audiogram?
    @State private var importing = false
    @State private var importMessage: String?
    @State private var staircase = HearingStaircase()
    @State private var results: [Ear: [HearingPoint]] = [:]
    @State private var runTask: Task<Void, Never>?
    @State private var paused = false
    /// A tone is playing or just ended: a tap now counts as "heard".
    @State private var windowOpen = false
    @State private var tapped = false
    /// Taps without a tone at the current frequency.
    @State private var falseAlarms = 0
    @State private var practiceTones = 0
    @State private var practiceHeard = false

    /// Pause before a tone, random so the timing can't be guessed.
    private static let gap: ClosedRange<Double> = 1.2...2.8
    /// Answer window from tone onset: three bursts (~1.05 s) plus reaction time.
    private static let window = 2.5

    private var onlyHigh: Bool { audiogram != nil }

    var body: some View {
        Screen {
            Eyebrow("Messung · Schritt 4", color: Theme.lab)
            Text("Hörcheck").font(.titleXL)
            if !engine.canMeasure { MeasurementBlocked() }
            switch phase {
            case .intro: intro
            case .practice: practice
            case .run: run
            case .done: done
            }
            chart
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { engine.configureSession() }
        .onDisappear { runTask?.cancel(); engine.stopAll() }
        .task {
            // Apple's hearing test is used automatically once Health access was granted.
            if audiogram == nil, ctx.settings().useHealthKit { await importAudiogram(silent: true) }
        }
    }

    // MARK: Intro

    @ViewBuilder
    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wir suchen pro Ohr die leiseste hörbare Lautstärke. Nach Konzert-Lärm zeigt sich meist ein Abfall im Hochtonbereich, und der Tinnitus sitzt typischerweise genau dort.")
                .foregroundStyle(Theme.text2)
            if let a = audiogram {
                appleImported(a)
            } else {
                appleImport
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(onlyHigh ? "Hochton ergänzen" : "Eigene Messung").font(.titleM)
                Picker("Ohr", selection: $ear) {
                    Text("Links").tag(Ear.left)
                    Text("Rechts").tag(Ear.right)
                }
                .pickerStyle(.segmented)
                Text(onlyHigh ? "10–16 kHz, dazu 1 und 8 kHz als Anschluss an Apples Kurve. Dauer: ca. 2 Minuten pro Ohr." : "0,5–16 kHz. Dauer: ca. 4–5 Minuten pro Ohr. Ganz ruhige Umgebung nötig.")
                    .font(.caption).foregroundStyle(Theme.text3)
            }
            .card()
            Callout("Die eigenen Werte sind relativ zu deinem Kopfhörer, nicht in dB HL wie beim HNO. Sie zeigen die Form deines Hörprofils und eignen sich für Verlaufsvergleiche mit denselben Kopfhörern.")
            Button(onlyHigh ? "Hochton messen" : "Test starten") { startPractice() }
                .buttonStyle(.primary(Theme.lab))
                .disabled(!engine.canMeasure)
            if onlyHigh {
                TextLinkButton("Ohne Ergänzung weiter zum Somatik-Check") { model.replaceTop(with: .somatic) }
            }
        }
    }

    private var appleImport: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(symbol: "airpodspro", color: Theme.lab)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apples Hörtest übernehmen").font(.body.weight(.semibold))
                    Text("Schon mit AirPods Pro 2/3 gemacht (Einstellungen › [deine AirPods] › Hörtest)? Dann liest die App das Ergebnis (bis 8 kHz, in dB HL) aus Health, und du misst hier nur noch den Hochton.").font(.caption).foregroundStyle(Theme.text2)
                }
            }
            Button(importing ? "Lese Health …" : "Aus Health importieren") { Task { await importAudiogram() } }
                .buttonStyle(.ghost(Theme.lab))
                .disabled(importing || !HealthService.shared.isAvailable)
            if let importMessage { Text(importMessage).font(.caption).foregroundStyle(Theme.text2) }
        }
        .card()
    }

    @ViewBuilder
    private func appleImported(_ a: HealthService.Audiogram) -> some View {
        let tinnitus = ctx.latestMatch()?.freq
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconBadge(symbol: "checkmark", color: Theme.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apples Hörtest übernommen").font(.body.weight(.semibold))
                    Text("vom \(a.date.formatted(date: .abbreviated, time: .omitted)) · 0,25–8 kHz").font(.caption).foregroundStyle(Theme.text2)
                }
            }
            if let tinnitus, tinnitus <= 8000 {
                Text("Dein Tinnitus liegt bei \(Format.hz(tinnitus)), also im Bereich von Apples Test. Die Hochton-Ergänzung ist optional.").font(.caption).foregroundStyle(Theme.text2)
            } else {
                Text("Apples Test endet bei 8 kHz. Der Tinnitus sitzt oft darüber, deshalb ergänzt die App nur noch 10–16 kHz.").font(.caption).foregroundStyle(Theme.text2)
            }
        }
        .card()
    }

    /// Reads the latest audiogram from Health. `silent`: automatic lookup on appear, no message if none.
    private func importAudiogram(silent: Bool = false) async {
        importing = true
        defer { importing = false }
        let s = ctx.settings()
        if !s.useHealthKit {
            s.useHealthKit = await HealthService.shared.requestAuthorization()
        }
        guard let a = await HealthService.shared.latestAudiogram(), !(a.left.isEmpty && a.right.isEmpty) else {
            if !silent { importMessage = "Kein Audiogramm in Health gefunden. Mach zuerst Apples Hörtest mit AirPods Pro." }
            return
        }
        audiogram = a
        if !tests.contains(where: { $0.source == .healthKit && $0.date == a.date }) {
            ctx.insert(HearingTest(date: a.date, left: a.left, right: a.right, source: .healthKit, device: DeviceStamp(kind: .airPodsPro2, name: "Apple Hörtest", calibrated: true)))
            try? ctx.save()
            DataActions.refreshSnapshot(ctx)
        }
        if !silent { Haptics.success() }
    }

    // MARK: Practice tone

    private var practice: some View {
        VStack(spacing: 14) {
            Text("Probeton").font(.titleM)
            ListenButton(color: Theme.lab, active: true) { practiceTap() }
            Text(practiceHeard
                 ? "Genau so. Im Test werden die Töne immer leiser und kommen in unregelmäßigen Abständen. Tippe jedes Mal, sobald du einen hörst."
                 : "Gleich kommen drei kurze Pieptöne auf dem \(ear == .left ? "linken" : "rechten") Ohr. Tippe auf den Kreis, sobald du sie hörst.")
                .font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            if !practiceHeard && practiceTones >= 3 {
                Callout("Nichts zu hören? Prüfe, ob die Kopfhörer verbunden sind und die Lautstärke nicht ganz unten ist.", tone: .warn)
            }
            Button("Test starten") { begin() }
                .buttonStyle(.primary(Theme.lab))
                .disabled(!practiceHeard)
            Text("Achte auf die drei kurzen Pieptöne. Dein Tinnitus ist ein Dauerton und zählt nicht.")
                .font(.caption).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
        }
    }

    private func startPractice() {
        runTask?.cancel()
        practiceTones = 0
        practiceHeard = false
        phase = .practice
        runTask = Task {
            while !Task.isCancelled && !practiceHeard {
                try? await Task.sleep(for: .seconds(1.2))
                if Task.isCancelled || practiceHeard { return }
                engine.play(.toneBursts(freq: 1000), ear: ear, levelDb: HearingStaircase.start, purpose: .measurement)
                practiceTones += 1
                try? await Task.sleep(for: .seconds(2.2))
            }
        }
    }

    private func practiceTap() {
        guard practiceTones > 0, !practiceHeard else { return }
        practiceHeard = true
        Haptics.success()
    }

    // MARK: Run

    private func begin() {
        runTask?.cancel()
        staircase = HearingStaircase(frequencies: onlyHigh ? [1000, 8000] + HearingStaircase.highFrequencies : HearingStaircase.frequencies)
        falseAlarms = 0
        paused = false
        phase = .run
        runLoop()
    }

    private var run: some View {
        VStack(spacing: 14) {
            ProgressDots(total: staircase.frequencies.count, done: staircase.index, color: Theme.lab)
            Text("\(ear.label) · \(staircase.currentFrequency.map(Format.hz) ?? "")").font(.titleM)
            ListenButton(color: Theme.lab, active: !paused) { tap() }
            Text(paused ? "Pausiert." : "Tippe auf den Kreis, sobald du einen Ton hörst, auch wenn er sehr leise ist.")
                .font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            if falseAlarms >= 3 && !paused {
                Callout("Tippe nur, wenn du sicher drei kurze Pieptöne hörst. Zwischen den Tönen ist es mal kürzer, mal länger still.", tone: .warn)
            }
            Button(paused ? "Weiter" : "Pause") { paused ? resume() : pause() }
                .buttonStyle(.ghost(Theme.lab, large: true))
            Text("Nichts zu hören ist normal und hilfreich: Gerade in hohen Tönen und rund um deinen Tinnitus ist das Gehör oft schwächer, oder der Tinnitus überdeckt den Ton.")
                .font(.caption).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
        }
    }

    /// One presentation per loop: random pause, three bursts, answer window. No tap in the window counts
    /// as "not heard".
    private func runLoop() {
        runTask?.cancel()
        runTask = Task {
            while !staircase.isDone {
                try? await Task.sleep(for: .seconds(Double.random(in: Self.gap)))
                if Task.isCancelled { return }
                guard let f = staircase.currentFrequency else { break }
                tapped = false
                windowOpen = true
                engine.play(.toneBursts(freq: f), ear: ear, levelDb: staircase.level, purpose: .measurement)
                let deadline = ContinuousClock.now + .seconds(Self.window)
                while !tapped && ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                    if Task.isCancelled { windowOpen = false; return }
                }
                windowOpen = false
                if staircase.answer(heard: tapped) { falseAlarms = 0 }
            }
            finishEar()
        }
    }

    private func tap() {
        guard !paused else { return }
        Haptics.tick()
        if windowOpen {
            tapped = true
        } else {
            falseAlarms += 1
        }
    }

    private func pause() {
        runTask?.cancel()
        windowOpen = false
        engine.stopAll()
        paused = true
    }

    private func resume() {
        paused = false
        runLoop()
    }

    private func finishEar() {
        results[ear] = staircase.results
        let prevApp = tests.last { $0.source != .healthKit }
        var left = results[.left] ?? prevApp?.left ?? []
        var right = results[.right] ?? prevApp?.right ?? []
        var source = HearingSource.app
        if let a = audiogram {
            left = HearingAnalysis.merge(appleHL: a.left, app: left)
            right = HearingAnalysis.merge(appleHL: a.right, app: right)
            source = .merged
            calibrateAnchor(a)
        }
        ctx.insert(HearingTest(left: left, right: right, source: source, device: engine.deviceStamp))
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
        Haptics.success()
        phase = .done
    }

    /// "Nutzer-Kalibrierung light" (05): the own 1 kHz threshold vs Apple's audiogram gives a personal
    /// offset for this device. RETSPL for insert earphones at 1 kHz ≈ 0 dB SPL; clamp to ±10 dB.
    private func calibrateAnchor(_ a: HealthService.Audiogram) {
        guard let own = staircase.results.first(where: { $0.freq == 1000 }),
              let hl = (ear == .left ? a.left : a.right).first(where: { $0.freq == 1000 })?.level else { return }
        var est = engine.estimator
        est.userOffset = 0
        let expected = hl + 0
        let measured = est.spl(dbfs: own.level, at: 1000)
        let offset = min(10, max(-10, expected - measured))
        let s = ctx.settings()
        s.calibrationOffsets[engine.deviceKind.rawValue] = offset
        try? ctx.save()
        DataActions.applyAudioSettings(s)
    }

    // MARK: Done

    @ViewBuilder
    private var done: some View {
        let other: Ear = ear == .left ? .right : .left
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Gespeichert", color: Theme.lab)
            Text("\(ear == .left ? "Linkes" : "Rechtes") Ohr fertig").font(.titleM)
        }
        .card(glow: Theme.lab)
        if results[other] == nil {
            Button("Jetzt \(other == .left ? "linkes" : "rechtes") Ohr") {
                ear = other
                begin()
            }
            .buttonStyle(.primary(Theme.lab))
        } else {
            Button { model.replaceTop(with: .somatic) } label: { NextLabel("Weiter: Somatik-Check") }
                .buttonStyle(.primary(Theme.lab))
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        if let t = tests.last, !(t.left.isEmpty && t.right.isEmpty) {
            let unit = t.source == .app ? "dB rel." : "dB HL"
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Dein Hörprofil").font(.titleM)
                    Spacer()
                    Chip(t.source == .healthKit ? "Apple Hörtest" : t.source == .merged ? "Apple + eigene Messung" : "eigene Messung", tone: .tint(Theme.lab))
                }
                Text("Weiter unten = schlechter gehört").font(.caption).foregroundStyle(Theme.text3)
                HearingChart(left: t.left, right: t.right, tinnitusHz: ctx.latestMatch()?.freq, unit: unit)
                let dl = HearingAnalysis.highFrequencyDrop(t.left.map { HearingPoint(freq: $0.freq, level: $0.level) })
                let dr = HearingAnalysis.highFrequencyDrop(t.right)
                if dl != nil || dr != nil {
                    HStack(spacing: 10) {
                        Metric(label: "Hochton-Abfall links", value: dl.map { "\(Int($0))" } ?? "–", unit: "dB")
                        Metric(label: "Hochton-Abfall rechts", value: dr.map { "\(Int($0))" } ?? "–", unit: "dB")
                    }
                }
                let tinnitus = ctx.latestMatch()?.freq
                if let edge = HearingAnalysis.lossEdge(t.left) ?? HearingAnalysis.lossEdge(t.right) {
                    Callout(HearingAnalysis.edgeHint(edge: edge, tinnitus: tinnitus))
                }
                let silent = Array(Set(HearingAnalysis.notHeard(t.left) + HearingAnalysis.notHeard(t.right))).sorted()
                if t.source == .app, !silent.isEmpty {
                    Callout("Bei \(silent.map(Format.hz).joined(separator: ", ")) hast du bis zum höchsten Testpegel nichts gehört. " + SpectrumAnalysis.inaudibleExplanation)
                }
                let worstHL = t.source != .app ? (t.left + t.right).filter { $0.freq <= 8000 }.map(\.level).max() : nil
                if max(dl ?? 0, dr ?? 0) > 20 || (worstHL ?? 0) >= 25 {
                    Callout("**Hinweis auf Hörverlust.** \(HearingAnalysis.hearingAidHint)", tone: .warn)
                }
            }
            .card()
        }
    }
}

/// Big tap target that pulses continuously while the test runs, whether a tone plays or not, so the
/// animation never gives the tone away (like Apple's hearing test).
private struct ListenButton: View {
    var color: Color
    var active: Bool
    var action: () -> Void
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pulsing = active && breathe && !reduceMotion
        Button(action: action) {
            ZStack {
                Circle().fill(color.opacity(0.10)).frame(width: 220, height: 220)
                    .scaleEffect(pulsing ? 1.0 : 0.86)
                    .opacity(active ? 1 : 0.4)
                    .animation(pulsing ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : .easeOut(duration: 0.3), value: pulsing)
                Circle().fill(color.opacity(active ? 0.24 : 0.12)).frame(width: 140, height: 140)
                VStack(spacing: 4) {
                    Image(systemName: "ear").font(.system(size: 34, weight: .semibold))
                    Text("Tippen").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(color)
            }
            .frame(width: 230, height: 230)
            .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .disabled(!active)
        .frame(maxWidth: .infinity)
        .onAppear { breathe = true }
        .accessibilityLabel("Ton gehört")
        .accessibilityHint("Tippe, sobald du einen Ton hörst.")
    }

    private struct PressScale: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
