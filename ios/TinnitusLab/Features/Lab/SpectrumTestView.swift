import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Tinnitus likeness spectrum (Noreña et al. 2002): 11 frequencies × 2 in random order, rated for
/// similarity. Far more reliable for high-pitched tinnitus than a single pitch match.
struct SpectrumTestView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var engine = AudioEngine.shared

    enum Phase { case intro, run, result }
    @State private var phase = Phase.intro
    @State private var ear: Ear = .both
    @State private var timbre: Timbre = .tone
    @State private var level = -32.0
    @State private var order: [Double] = []
    @State private var index = 0
    @State private var ratings: [Double: [Double]] = [:]
    @State private var current: Int?
    @State private var voice: VoiceHandle?
    @State private var result: SpectrumAnalysis.Result?
    @State private var pulsing = false
    @State private var inaudible: Set<Double> = []

    var body: some View {
        Screen {
            Eyebrow("Messung · Schritt 2", color: Theme.lab)
            Text("Tinnitus-Spektrum").font(.titleXL)
            if !engine.canMeasure { MeasurementBlocked() }
            switch phase {
            case .intro: intro
            case .run: run
            case .result: resultView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear { stop() }
    }

    private func load() {
        let s = ctx.settings()
        ear = s.preferredEar
        if let m = ctx.latestMatch() {
            timbre = m.timbre
            level = m.loudnessDb
        }
        engine.configureSession()
    }

    private func play(_ f: Double, boost: Double = 0) {
        stop()
        let recipe: Recipe = timbre == .tone ? .tone(freq: f) : .narrowband(freq: f, widthOctaves: 1.0 / 3)
        let v = engine.play(recipe, ear: ear, levelDb: level + boost, purpose: .measurement)
        voice = v
        pulsing = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            if voice === v { stop() }
        }
    }

    private func stop() {
        voice?.stop(fadeMs: 80)
        voice = nil
        pulsing = false
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Du hörst \(SpectrumAnalysis.frequencies.count) Töne je \(SpectrumAnalysis.repetitions)× in zufälliger Reihenfolge und bewertest, wie ähnlich jeder deinem Tinnitus ist. Das dauert etwa 4 Minuten und ist bei hohem Tinnitus deutlich verlässlicher als nur einen Regler zu schieben.")
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 12) {
                Text("Ohr").font(.titleM)
                Picker("Ohr", selection: $ear) { ForEach(Ear.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Text("Klingt dein Tinnitus eher wie …").font(.titleM)
                Picker("Klang", selection: $timbre) {
                    Text("Pfeifton").tag(Timbre.tone)
                    Text("Zischen").tag(Timbre.hiss)
                }
                .pickerStyle(.segmented)
                LabeledSlider(label: "Pegel der Testtöne", value: $level, range: -60...(-10), color: Theme.lab, format: { "\(Int($0)) dB" })
                SPLHint(dbfs: level, freq: 4000)
                Button { play(4000) } label: { Label("Probeton 4 kHz", systemImage: "play.fill") }.buttonStyle(.ghost(Theme.lab))
                Text("Stelle den Pegel so ein, dass der Probeton etwa so laut ist wie dein Tinnitus.").font(.caption).foregroundStyle(Theme.text3)
            }
            .card()
            Button("Test starten") {
                order = SpectrumAnalysis.frequencies.flatMap { Array(repeating: $0, count: SpectrumAnalysis.repetitions) }.shuffled()
                index = 0
                ratings = [:]
                inaudible = []
                phase = .run
                play(order[0])
            }
            .buttonStyle(.primary(Theme.lab))
            .disabled(!engine.canMeasure)
        }
    }

    // MARK: Run

    private var run: some View {
        VStack(spacing: 14) {
            ProgressDots(total: order.count, done: index, color: Theme.lab)
            VStack(spacing: 14) {
                PulseOrb(symbol: "waveform", color: Theme.lab, active: pulsing)
                Text("Ton \(index + 1) von \(order.count)").font(.titleM)
                Text("Wie ähnlich ist dieser Ton deinem Tinnitus, in Tonhöhe und Klang?").font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button { play(order[index]) } label: { Label("Nochmal", systemImage: "arrow.counterclockwise") }.buttonStyle(.ghost(Theme.lab))
                    Button { play(order[index], boost: 10) } label: { Label("Lauter", systemImage: "speaker.wave.3") }.buttonStyle(.ghost(Theme.lab))
                }
                Scale10(value: $current, labels: ("gar nicht", "genau so"), color: Theme.lab) { v in record(Double(v)) }
            }
            .card()
            TextLinkButton("Nicht hörbar") {
                inaudible.insert(order[index])
                record(0)
            }
            if !inaudible.isEmpty {
                Text("Nicht hören ist kein Fehler: Oft liegt der Tinnitus genau in dem Bereich, den man schlechter hört, oder er überdeckt den Ton.")
                    .font(.caption).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
            }
        }
    }

    private func record(_ v: Double) {
        let f = order[index]
        ratings[f, default: []].append(v)
        index += 1
        current = nil
        if index >= order.count {
            finish()
        } else {
            Task {
                try? await Task.sleep(for: .milliseconds(280))
                play(order[index])
            }
        }
    }

    private func finish() {
        stop()
        let r = SpectrumAnalysis.evaluate(ratings)
        result = r
        ctx.insert(TinnitusSpectrum(ear: ear, timbre: timbre, points: r.points, peak: r.peak, device: engine.deviceStamp))
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
        Haptics.success()
        phase = .result
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let r = result {
            let (v, u) = Format.hzParts(r.peak)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Ergebnis", color: Theme.lab)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v).font(.display(48)).foregroundStyle(Theme.tin)
                    Text(u).font(.title3.weight(.semibold)).foregroundStyle(Theme.text2)
                }
                Text("Höchste Ähnlichkeit").foregroundStyle(Theme.text2)
                SpectrumBars(points: r.points, peak: r.peak)
                HStack {
                    Chip("Wiederholgenauigkeit ±\(Format.decimal(r.consistency))", tone: r.consistency <= 1.5 ? .good : .warn)
                    Chip(r.shapeLabel, tone: .tint(Theme.lab))
                }
            }
            .card(glow: Theme.lab)
            if let hint = SpectrumAnalysis.inaudibleHint(inaudible: inaudible, peak: r.peak) {
                Callout(hint)
            }
            if r.consistency > 2 {
                Callout("Deine Bewertungen der gleichen Töne weichen stark voneinander ab. Das ist bei hohem Tinnitus häufig. Wiederhole den Test an einem anderen Tag, das Profil wird mit jeder Messung schärfer.", tone: .warn)
            }
            if r.peak >= 14000 {
                Callout("Dein Tinnitus liegt sehr hoch. Prüfe im Hörcheck, ob du den Bereich überhaupt noch hörst; Notched-Programme brauchen hörbares Material um die Frequenz.")
            }
            Button { model.replaceTop(with: .match(start: r.peak)) } label: { NextLabel("Weiter: Feinabstimmung") }
                .buttonStyle(.primary(Theme.lab))
            TextLinkButton("Nochmal messen") { phase = .intro }
        }
    }
}

/// Pulsing circle used while a stimulus plays.
struct PulseOrb: View {
    var symbol: String
    var color: Color
    var active: Bool
    var label: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.10)).frame(width: 130, height: 130)
                .scaleEffect(active && !reduceMotion ? 1.12 : 0.92)
                .animation(active && !reduceMotion ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeOut(duration: 0.3), value: active)
            Circle().fill(color.opacity(0.22)).frame(width: 88, height: 88)
            if let label {
                Text(label).font(.display(30)).foregroundStyle(color).monospacedDigit()
            } else {
                Image(systemName: symbol).font(.system(size: 32, weight: .semibold)).foregroundStyle(color)
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}
