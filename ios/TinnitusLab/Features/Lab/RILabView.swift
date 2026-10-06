import Charts
import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Residual inhibition lab: 6 stimuli × 2 runs, blinded by default; the stimulus is revealed after rating.
struct RILabView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \RITrial.date) private var trials: [RITrial]
    @State private var engine = AudioEngine.shared

    enum Phase: Equatable { case setup, baseline, stimulate, rate, result }
    @State private var phase = Phase.setup
    @State private var blind = true
    @State private var kind: StimulusKind = .nbnThird
    @State private var durationS = 60.0
    @State private var levelDb = -30.0
    @State private var baseline: Int?
    @State private var left = 0.0
    @State private var current = 5.0
    @State private var curve: [Double] = []
    @State private var task: Task<Void, Never>?
    @State private var voice: VoiceHandle?
    @State private var last: RITrial?
    @State private var pauseUntil: Date?

    private let window = 90.0

    var body: some View {
        Screen {
            Eyebrow("Messung · Schritt 6", color: Theme.lab)
            Text("Residual Inhibition").font(.titleXL)
            if let match = ctx.latestMatch() {
                if !engine.canMeasure { MeasurementBlocked() }
                switch phase {
                case .setup: setup(match)
                case .baseline: baselineView
                case .stimulate: stimulateView(match)
                case .rate: rateView
                case .result: resultView
                }
                if phase == .setup || phase == .result { ranking(match) }
            } else {
                Callout("Für das RI-Labor brauchen wir zuerst deine Tinnitus-Frequenz und Maskierungsschwelle.", tone: .warn)
                Button("Zur Feinabstimmung") { model.replaceTop(with: .match(start: nil)) }.buttonStyle(.primary(Theme.lab))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: stopAll)
    }

    private func load() {
        engine.configureSession()
        blind = ctx.settings().blindRi
        kind = RIAnalysis.leastTested(trials.map(\.stimulus))
        if let m = ctx.latestMatch() { levelDb = RIAnalysis.suggestedLevel(mmlDb: m.mmlDb, loudnessDb: m.loudnessDb) }
    }

    private func stopAll() {
        task?.cancel()
        task = nil
        voice?.stop(fadeMs: 80)
        voice = nil
    }

    // MARK: Setup

    private func setup(_ match: TinnitusMatch) -> some View {
        let cap = SafetyLimits.riCap(mmlDb: match.mmlDb, loudnessDb: match.loudnessDb)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Nach manchen Klängen ist der Tinnitus für Sekunden bis Minuten leiser. Welcher Klang das bei dir auslöst, ist individuell. Hier testen wir es systematisch.")
                .foregroundStyle(Theme.text2)
            if let until = pauseUntil, until > .now {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Callout("Pause: noch \(Format.duration(until.timeIntervalSinceNow)). Warte, bis der Tinnitus wieder auf Ausgangsniveau ist. Du bekommst eine Mitteilung.")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Verblindet testen (empfohlen)", isOn: $blind)
                    .tint(Theme.lab)
                    .onChange(of: blind) { _, v in
                        ctx.settings().blindRi = v
                        if v { kind = RIAnalysis.leastTested(trials.map(\.stimulus)) }
                    }
                Text("Die App wählt den Klang zufällig und zeigt ihn erst nach der Bewertung. So beeinflusst deine Erwartung das Ergebnis nicht.")
                    .font(.caption).foregroundStyle(Theme.text2)
            }
            .card()
            if !blind {
                ForEach(SoundContent.stimuli) { s in
                    ChoiceRow(title: s.label, sub: s.desc, selected: kind == s.kind) { kind = s.kind }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Dauer").font(.titleM)
                Picker("Dauer", selection: $durationS) {
                    Text("30 s").tag(30.0)
                    Text("60 s").tag(60.0)
                    Text("90 s").tag(90.0)
                }
                .pickerStyle(.segmented)
                LabeledSlider(label: "Stimulus-Pegel", value: $levelDb, range: -60...min(-8, cap), color: Theme.lab, format: { "\(Int($0)) dB" })
                SPLHint(dbfs: levelDb, freq: match.freq)
                Text("Vorschlag: MML + 10 dB. Deine MML: \(match.mmlDb.map { "\(Int($0))" } ?? "–") dB. Höchstens MML + 15 dB, nie unangenehm laut.")
                    .font(.caption).foregroundStyle(Theme.text3)
            }
            .card()
            Button("Durchgang starten") {
                if blind { kind = RIAnalysis.leastTested(trials.map(\.stimulus)) }
                ReminderService.shared.cancelRIPause()
                pauseUntil = nil
                baseline = nil
                phase = .baseline
            }
            .buttonStyle(.primary(Theme.lab))
            .disabled(!engine.canMeasure)
        }
    }

    // MARK: Baseline

    private var baselineView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("1 / 3 · Ausgangswert")
            Text("Wie laut ist dein Tinnitus gerade?").font(.titleL)
            Scale10(value: $baseline, labels: ("nicht hörbar", "extrem laut"), color: Theme.lab) { v in
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    stimulate(base: Double(v))
                }
            }
            .card()
        }
    }

    // MARK: Stimulation

    private func stimulate(base: Double) {
        guard let m = ctx.latestMatch() else { return }
        left = durationS
        phase = .stimulate
        let cap = SafetyLimits.riCap(mmlDb: m.mmlDb, loudnessDb: m.loudnessDb)
        voice = engine.play(Recipe.stimulus(kind, freq: m.freq, notchWidth: ctx.settings().notchWidthOctaves), ear: m.ear, levelDb: levelDb, purpose: .measurement, extraCapDb: cap)
        task = Task {
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                left -= 1
            }
            voice?.stop(fadeMs: 80)
            voice = nil
            Haptics.warning()
            rate(base: base)
        }
    }

    private func stimulateView(_ m: TinnitusMatch) -> some View {
        VStack(spacing: 16) {
            Eyebrow("2 / 3 · Stimulation")
            RingView(progress: 1 - left / durationS, color: Theme.lab, lineWidth: 10) {
                VStack(spacing: 4) {
                    Text(Format.duration(left)).font(.display(40)).monospacedDigit()
                    Text(blind ? "Klang verblindet" : SoundContent.label(kind)).font(.caption).foregroundStyle(Theme.text2)
                }
            }
            .frame(width: 220, height: 220)
            if !blind { LiveSpectrumView(tinnitusHz: m.freq, color: Theme.lab) }
            Text("Einfach zuhören. Wenn der Klang endet, bewertest du sofort, wie laut dein Tinnitus ist. Ein kurzes Vibrieren kündigt das an.")
                .font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            TextLinkButton("Abbrechen") {
                stopAll()
                phase = .setup
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Rating

    private func rate(base: Double) {
        current = base
        curve = []
        phase = .rate
        task = Task {
            var elapsed = 0.0
            while elapsed < window {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                elapsed += 2
                curve.append(current)
            }
            finish(base: base)
        }
    }

    private var rateView: some View {
        let base = Double(baseline ?? 5)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("3 / 3 · Bewerten")
                Spacer()
                Text(Format.duration(window - Double(curve.count) * 2)).font(.subheadline.weight(.bold)).monospacedDigit()
            }
            Text("Wie laut ist er jetzt?").font(.titleL)
            Text("Halte den Regler die ganze Zeit aktuell. Wird er leiser, nach links; kommt er zurück, nach rechts.")
                .font(.subheadline).foregroundStyle(Theme.text2)
            VStack(spacing: 10) {
                Text(Format.decimal(current)).font(.display(44)).monospacedDigit().foregroundStyle(Theme.lab)
                Slider(value: $current, in: 0...10, step: 0.5).tint(Theme.lab)
                    .accessibilityLabel("Lautheit jetzt").accessibilityValue(Format.decimal(current))
                HStack { Text("weg"); Spacer(); Text("extrem") }.font(.caption).foregroundStyle(Theme.text3)
                Chart {
                    ForEach(Array(curve.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("s", (i + 1) * 2), y: .value("Lautheit", v))
                            .foregroundStyle(Theme.lab.opacity(0.2))
                        LineMark(x: .value("s", (i + 1) * 2), y: .value("Lautheit", v))
                            .foregroundStyle(Theme.lab)
                    }
                    RuleMark(y: .value("Ausgangswert", base))
                        .foregroundStyle(Theme.tin)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                .chartXScale(domain: 0...window)
                .chartYScale(domain: 0...10)
                .frame(height: 150)
            }
            .card()
            Button("Tinnitus ist wieder voll da, beenden") {
                task?.cancel()
                finish(base: base)
            }
            .buttonStyle(.ghost(Theme.lab, large: true))
        }
    }

    private func finish(base: Double) {
        guard let m = ctx.latestMatch() else { return }
        let e = RIAnalysis.evaluate(baseline: base, curve: curve)
        let t = RITrial(stimulus: kind, blind: blind, centerFreq: m.freq, levelDb: levelDb.rounded(), durationS: durationS,
                        curve: curve.isEmpty ? [base] : curve, baseline: base, depth: e.depth, durationOfEffectS: e.durationS, device: engine.deviceStamp)
        ctx.insert(t)
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
        last = t
        if trials.count < Program.riTarget {
            pauseUntil = .now.addingTimeInterval(4 * 60)
            ReminderService.shared.scheduleRIPause(minutes: 4)
        }
        phase = .result
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let t = last {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(t.blind ? "Aufgedeckt" : "Ergebnis")
                Text(SoundContent.label(t.stimulus)).font(.titleL)
                HStack(spacing: 10) {
                    Metric(label: "Unterdrückung", value: "−\(Format.decimal(t.depth))", unit: "Punkte", color: t.depth >= 1 ? Theme.good : Theme.text)
                    Metric(label: "Dauer", value: "\(Int(t.durationOfEffectS))", unit: "s")
                }
                Text(RIAnalysis.verdict(depth: t.depth)).foregroundStyle(Theme.text2)
            }
            .card(glow: t.depth >= 1 ? Theme.lab : nil)
            if trials.count < Program.riTarget {
                Callout("\(trials.count) von \(Program.riTarget) Durchgängen. Mach 3 bis 5 Minuten Pause, bis der Tinnitus wieder auf Ausgangsniveau ist, bevor du weitermachst.")
            } else {
                Callout("Alle Messungen abgeschlossen. Dein bester Klang wird jetzt automatisch in der Reset-Sitzung verwendet.", tone: .good)
            }
            Button("Nächster Durchgang") { phase = .setup }.buttonStyle(.primary(Theme.lab))
            TextLinkButton("Zu den Klangprogrammen") { model.open(.sound(nil)) }
        }
    }

    // MARK: Ranking

    @ViewBuilder
    private func ranking(_ m: TinnitusMatch) -> some View {
        if !trials.isEmpty {
            let sum = RIAnalysis.summarize(trials.map { .init(stimulus: $0.stimulus, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) })
            let maxScore = max(sum.map(\.score).max() ?? 1, 1)
            let untested = SoundContent.stimuli.filter { s in !sum.contains { $0.stimulus == s.kind } }
            SectionHeader("Deine Rangliste") { Chip("\(trials.count) Durchgänge", tone: .tint(Theme.lab)) }
            VStack(spacing: 10) {
                ForEach(Array(sum.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Text(i == 0 && s.depth > 0 ? "★ \(SoundContent.label(s.stimulus))" : SoundContent.label(s.stimulus))
                            .font(.subheadline.weight(i == 0 && s.depth > 0 ? .bold : .regular))
                            .foregroundStyle(i == 0 && s.depth > 0 ? Theme.tin : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("n=\(s.n)").font(.caption).foregroundStyle(Theme.text3)
                        Text("−\(Format.decimal(s.depth)) · \(Int(s.duration)) s").font(.caption.weight(.semibold)).monospacedDigit()
                        Capsule().fill(Theme.surface3).frame(width: 60, height: 6)
                            .overlay(alignment: .leading) { Capsule().fill(Theme.lab).frame(width: 60 * s.score / maxScore, height: 6) }
                    }
                }
                if !untested.isEmpty {
                    Text("Noch offen: \(untested.map(\.label).joined(separator: ", "))").font(.caption).foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DisclosureGroup("Alle Durchgänge") {
                    ForEach(trials.reversed()) { t in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(SoundContent.label(t.stimulus)).font(.subheadline)
                                Text("\(t.date.formatted(date: .abbreviated, time: .shortened)) · \(Int(t.levelDb)) dB · \(Int(t.durationS)) s\(t.blind ? " · verblindet" : "")")
                                    .font(.caption).foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            Chip("−\(Format.decimal(t.depth)) · \(Int(t.durationOfEffectS)) s", tone: t.depth >= 1 ? .good : .neutral)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.text2)
            }
            .card()
            Callout("**Einordnung:** RI ist gut belegt als kurzfristiger Effekt. Dass wiederholte RI den Tinnitus dauerhaft senkt, ist bisher in keiner kontrollierten Studie gezeigt. Wir nutzen sie hier als persönliches Messinstrument und als Erholungspause.")
            Text("Frequenz \(Format.hz(m.freq))").font(.caption).foregroundStyle(Theme.text3)
        }
    }
}
