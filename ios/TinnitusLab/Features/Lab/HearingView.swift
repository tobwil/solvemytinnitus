import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Hearing check: import Apple's hearing test (HealthKit audiogram, 250 Hz–8 kHz), own test only
/// 10–16 kHz in that case (otherwise 0.5–16 kHz), merged into one curve. Wording per 08: "Hörcheck",
/// not a clinical audiogram.
struct HearingView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \HearingTest.date) private var tests: [HearingTest]
    @State private var engine = AudioEngine.shared

    enum Phase { case intro, run, done }
    @State private var phase = Phase.intro
    @State private var ear: Ear = .left
    @State private var audiogram: HealthService.Audiogram?
    @State private var importing = false
    @State private var importMessage: String?
    @State private var staircase = HearingStaircase()
    @State private var results: [Ear: [HearingPoint]] = [:]
    @State private var onlyHigh = false
    @State private var pulsing = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Screen {
            Eyebrow("Messung · Schritt 4", color: Theme.lab)
            Text("Hörcheck").font(.titleXL)
            if !engine.canMeasure { MeasurementBlocked() }
            switch phase {
            case .intro: intro
            case .run: run
            case .done: done
            }
            chart
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { engine.configureSession() }
        .onDisappear { pending?.cancel(); engine.stopAll() }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wir suchen pro Ohr die leiseste hörbare Lautstärke. Nach Konzert-Lärm zeigt sich meist ein Abfall im Hochtonbereich, und der Tinnitus sitzt typischerweise genau dort.")
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "airpodspro", color: Theme.lab)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apples Hörtest übernehmen").font(.body.weight(.semibold))
                        Text("Mit AirPods Pro 2/3 in Einstellungen › [deine AirPods] › Hörtest. Das Ergebnis (bis 8 kHz, in dB HL) liest die App aus Health.").font(.caption).foregroundStyle(Theme.text2)
                    }
                }
                Button(importing ? "Lese Health …" : audiogram == nil ? "Aus Health importieren" : "Erneut importieren") { Task { await importAudiogram() } }
                    .buttonStyle(.ghost(Theme.lab))
                    .disabled(importing || !HealthService.shared.isAvailable)
                if let importMessage { Text(importMessage).font(.caption).foregroundStyle(Theme.text2) }
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text("Eigene Messung").font(.titleM)
                Picker("Ohr", selection: $ear) {
                    Text("Links").tag(Ear.left)
                    Text("Rechts").tag(Ear.right)
                }
                .pickerStyle(.segmented)
                Toggle("Nur 10–16 kHz (Rest aus Apples Hörtest)", isOn: $onlyHigh)
                    .disabled(audiogram == nil)
                    .tint(Theme.lab)
                Text(onlyHigh ? "Dauer: ca. 1 Minute pro Ohr." : "Dauer: ca. 3 Minuten pro Ohr. Ganz ruhige Umgebung nötig.").font(.caption).foregroundStyle(Theme.text3)
            }
            .card()
            Callout("Die eigenen Werte sind relativ zu deinem Kopfhörer, nicht in dB HL wie beim HNO. Sie zeigen die Form deines Hörprofils und eignen sich für Verlaufsvergleiche mit denselben Kopfhörern.")
            Button("Test starten") { begin() }
                .buttonStyle(.primary(Theme.lab))
                .disabled(!engine.canMeasure)
        }
    }

    private func importAudiogram() async {
        importing = true
        defer { importing = false }
        let s = ctx.settings()
        if !s.useHealthKit {
            s.useHealthKit = await HealthService.shared.requestAuthorization()
        }
        guard let a = await HealthService.shared.latestAudiogram(), !(a.left.isEmpty && a.right.isEmpty) else {
            importMessage = "Kein Audiogramm in Health gefunden. Mach zuerst Apples Hörtest mit AirPods Pro."
            return
        }
        audiogram = a
        onlyHigh = true
        ctx.insert(HearingTest(date: a.date, left: a.left, right: a.right, source: .healthKit, device: DeviceStamp(kind: .airPodsPro2, name: "Apple Hörtest", calibrated: true)))
        try? ctx.save()
        importMessage = "Audiogramm vom \(a.date.formatted(date: .abbreviated, time: .omitted)) übernommen."
        Haptics.success()
    }

    private func begin() {
        staircase = HearingStaircase(frequencies: onlyHigh ? [1000, 8000] + HearingStaircase.highFrequencies : HearingStaircase.frequencies)
        phase = .run
        schedule(0.3)
    }

    // MARK: Run

    private var run: some View {
        VStack(spacing: 14) {
            ProgressDots(total: staircase.frequencies.count, done: staircase.index, color: Theme.lab)
            VStack(spacing: 10) {
                PulseOrb(symbol: "ear", color: Theme.lab, active: pulsing)
                Text("\(ear.label) · \(staircase.currentFrequency.map(Format.hz) ?? "")").font(.titleM)
                Text("Drei kurze Pieptöne. Antworte, sobald du sie hörst, auch wenn sie sehr leise sind.").font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                TextLinkButton("Wiederholen", symbol: "arrow.counterclockwise") { present() }
            }
            .card()
            Button("Gehört") { answer(true) }.buttonStyle(.primary(Theme.lab))
            Button("Nichts gehört") { answer(false) }.buttonStyle(.ghost(Theme.lab, large: true))
            Text("Nichts zu hören ist normal und hilfreich: Gerade in hohen Tönen und rund um deinen Tinnitus ist das Gehör oft schwächer, oder der Tinnitus überdeckt den Ton.")
                .font(.caption).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
        }
    }

    private func present() {
        guard let f = staircase.currentFrequency else { return }
        engine.play(.toneBursts(freq: f), ear: ear, levelDb: staircase.level, purpose: .measurement)
        pulsing = true
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            pulsing = false
        }
    }

    private func schedule(_ s: Double) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(s))
            if !Task.isCancelled { present() }
        }
    }

    private func answer(_ heard: Bool) {
        guard !staircase.isDone else { return }
        let changed = staircase.answer(heard: heard)
        if staircase.isDone {
            finishEar()
        } else {
            schedule(changed ? 0.35 : 0.25)
        }
    }

    private func finishEar() {
        pending?.cancel()
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
