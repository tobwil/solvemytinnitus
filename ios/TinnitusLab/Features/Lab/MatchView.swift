import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Pitch match on a frequency pad (3 independent trials), octave check, loudness and minimum masking level.
struct MatchView: View {
    var start: Double?
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var engine = AudioEngine.shared

    enum Phase: Equatable { case setup, pitch, octave, loudness, mml, done }
    @State private var phase = Phase.setup
    @State private var ear: Ear = .both
    @State private var timbre: Timbre = .tone
    @State private var startFreq = 6000.0
    @State private var freq = 6000.0
    @State private var trials: [Double] = []
    @State private var loudnessDb = -32.0
    @State private var mmlDb = -50.0
    @State private var voice: VoiceHandle?
    @State private var noise: VoiceHandle?
    @State private var spectrum: [SpectrumPoint] = []
    @State private var saved: TinnitusMatch?
    private let steps = 5

    var body: some View {
        Screen {
            Eyebrow("Messung · Schritt 3", color: Theme.lab)
            Text("Feinabstimmung").font(.titleXL)
            if !engine.canMeasure { MeasurementBlocked() }
            switch phase {
            case .setup: setup
            case .pitch: pitch
            case .octave: octave
            case .loudness: loudness
            case .mml: mml
            case .done: done
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear { stopAll() }
    }

    private func load() {
        engine.configureSession()
        let spec = ctx.latestSpectrum()
        let prev = ctx.latestMatch()
        ear = spec?.ear ?? ctx.settings().preferredEar
        timbre = spec?.timbre ?? prev?.timbre ?? .tone
        startFreq = start ?? spec?.peak ?? prev?.freq ?? 6000
        freq = startFreq
        loudnessDb = prev?.loudnessDb ?? -32
        spectrum = spec?.points ?? []
    }

    private func recipe(_ f: Double) -> Recipe {
        timbre == .tone ? .tone(freq: f) : .narrowband(freq: f, widthOctaves: 1.0 / 3)
    }

    private func startVoice(_ f: Double, db: Double? = nil) {
        voice?.stop(fadeMs: 40)
        let v = engine.play(recipe(f), ear: ear, levelDb: db ?? loudnessDb, purpose: .measurement)
        v.setFrequency(f)
        voice = v
    }

    private func stopVoice() {
        voice?.stop(fadeMs: 60)
        voice = nil
    }

    private func stopAll() {
        stopVoice()
        noise?.stop(fadeMs: 100)
        noise = nil
    }

    private func playBriefly(_ f: Double, seconds: Double = 1.4) {
        startVoice(f)
        let v = voice
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if voice === v { stopVoice() }
        }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ctx.latestSpectrum() != nil
                 ? "Dein Spektrum zeigt den Schwerpunkt bei \(Format.hz(startFreq)). Jetzt stimmen wir das genau ab: drei unabhängige Durchgänge auf dem Frequenz-Pad, dann Lautheit und Maskierungsschwelle."
                 : "Drei unabhängige Durchgänge auf dem Frequenz-Pad, dann Lautheit und Maskierungsschwelle. Tipp: Das Tinnitus-Spektrum vorher macht das Ergebnis deutlich verlässlicher.")
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 12) {
                Text("Ohr").font(.titleM)
                Picker("Ohr", selection: $ear) { ForEach(Ear.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Text("Vergleichsklang").font(.titleM)
                Picker("Klang", selection: $timbre) {
                    Text("Reiner Ton").tag(Timbre.tone)
                    Text("Schmalband-Rauschen").tag(Timbre.hiss)
                }
                .pickerStyle(.segmented)
            }
            .card()
            if ctx.latestSpectrum() == nil {
                TextLinkButton("Erst Spektrum messen") { model.replaceTop(with: .spectrum) }
            }
            Button("Los") {
                trials = []
                freq = startFreq
                phase = .pitch
            }
            .buttonStyle(.primary(Theme.lab))
            .disabled(!engine.canMeasure)
        }
    }

    // MARK: Pitch

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressDots(total: steps, done: trials.count, color: Theme.lab)
            Text("Durchgang \(trials.count + 1) von 3").font(.titleM)
            Text("Halte den Finger auf dem Feld und zieh ihn nach links oder rechts, bis der Ton wie dein Tinnitus klingt. Lass los und vergleiche. Mit den Tasten feinjustieren.")
                .font(.subheadline).foregroundStyle(Theme.text2)
            FrequencyPad(frequency: $freq, overlay: spectrum,
                         onStart: { startVoice($0) },
                         onMove: { voice?.setFrequency($0) },
                         onEnd: { stopVoice() })
            HStack(spacing: 8) {
                nudge("−1 HT", -1)
                nudge("−¼", -0.25)
                nudge("+¼", 0.25)
                nudge("+1 HT", 1)
            }
            Button("Klingt wie mein Tinnitus") {
                stopVoice()
                phase = .octave
            }
            .buttonStyle(.primary(Theme.lab))
        }
    }

    private func nudge(_ label: String, _ semitones: Double) -> some View {
        Button(label) {
            freq = min(MatchAnalysis.fMax, max(MatchAnalysis.fMin, freq * pow(2, semitones / 12)))
            playBriefly(freq, seconds: 1.2)
        }
        .buttonStyle(.ghost(Theme.lab))
        .accessibilityLabel(semitones > 0 ? "Höher, \(label)" : "Tiefer, \(label)")
    }

    // MARK: Octave check

    private var octave: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressDots(total: steps, done: trials.count, color: Theme.lab)
            Text("Oktaven-Check").font(.titleM)
            Text("Die häufigste Verwechslung beim Matching ist die Oktave. Hör dir die Varianten an und wähle die, die wirklich passt.")
                .font(.subheadline).foregroundStyle(Theme.text2)
            ForEach(MatchAnalysis.octaveCandidates(freq), id: \.self) { f in
                let isCurrent = abs(f - freq) < 1
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.hz(f)).font(.display(22)).monospacedDigit()
                        Text(isCurrent ? "deine Einstellung" : f < freq ? "eine Oktave tiefer" : "eine Oktave höher").font(.caption).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    Button { playBriefly(f, seconds: 1.5) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(Theme.lab)
                        .accessibilityLabel("\(Format.hz(f)) anhören")
                    Button("Passt") { pick(f) }
                        .buttonStyle(isCurrent ? AnyButtonStyle(.primary(Theme.lab, large: false)) : AnyButtonStyle(.ghost(Theme.lab)))
                        .frame(width: 90)
                }
                .card(padding: 12)
            }
        }
    }

    private func pick(_ f: Double) {
        stopVoice()
        trials.append(f)
        if trials.count < 3 {
            var g = SystemRandomNumberGenerator()
            freq = MatchAnalysis.jitteredStart(startFreq, using: &g)
            phase = .pitch
        } else {
            freq = MatchAnalysis.combine(trials: trials).freq
            phase = .loudness
        }
    }

    // MARK: Loudness

    private var loudness: some View {
        let c = MatchAnalysis.combine(trials: trials)
        let (v, u) = Format.hzParts(c.freq)
        return VStack(alignment: .leading, spacing: 14) {
            ProgressDots(total: steps, done: 3, color: Theme.lab)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Median aus 3 Durchgängen", color: Theme.lab)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v).font(.display(44)).foregroundStyle(Theme.tin)
                    Text(u).font(.title3.weight(.semibold)).foregroundStyle(Theme.text2)
                }
                FlowChips(items: trials.map { Format.hz($0) } , extra: ("Streuung \(Format.decimal(c.spreadOctaves * 12)) HT", c.spreadOctaves > 0.5))
            }
            .card(glow: Theme.lab)
            if c.spreadOctaves > 0.5 {
                Callout("Die Durchgänge liegen mehr als eine halbe Oktave auseinander. Das ist bei hohem Tinnitus normal. Wiederhole die Messung an einem anderen Tag.", tone: .warn)
            }
            Text("Wie laut ist dein Tinnitus?").font(.titleM)
            Text("Spiel den Ton ab und stell den Pegel so ein, dass er genau so laut wirkt wie dein Tinnitus.").font(.subheadline).foregroundStyle(Theme.text2)
            VStack(spacing: 10) {
                Button(voice == nil ? "Abspielen" : "Stopp") {
                    if voice == nil { startVoice(c.freq) } else { stopVoice() }
                }
                .buttonStyle(.ghost(Theme.lab))
                LabeledSlider(label: "Pegel des Vergleichstons", value: $loudnessDb, range: -75...(-8), color: Theme.lab, format: { "\(Int($0)) dB" })
                    .onChange(of: loudnessDb) { _, v in voice?.setLevel(v) }
                SPLHint(dbfs: loudnessDb, freq: c.freq)
                if let v = voice, v.isCapped { Text("Hörschutz-Deckel aktiv").font(.caption).foregroundStyle(Theme.warn) }
            }
            .card()
            Button("Gleich laut") {
                stopVoice()
                phase = .mml
            }
            .buttonStyle(.primary(Theme.lab))
        }
    }

    // MARK: MML

    private var mml: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressDots(total: steps, done: 4, color: Theme.lab)
            Text("Minimale Maskierungsschwelle").font(.titleM)
            Text("Starte das Rauschen leise und erhöhe es langsam, bis du deinen Tinnitus gerade nicht mehr hörst. Die Schwelle (MML) ist ein objektiverer Verlaufswert als die Lautheit und legt die Pegel für Labor und Klangprogramme fest.")
                .font(.subheadline).foregroundStyle(Theme.text2)
            VStack(spacing: 10) {
                Button(noise == nil ? "Rauschen starten" : "Stopp") {
                    if let n = noise { n.stop(fadeMs: 100); noise = nil } else {
                        noise = engine.play(.noise(.white), ear: ear, levelDb: mmlDb, purpose: .measurement)
                    }
                }
                .buttonStyle(.ghost(Theme.lab))
                LabeledSlider(label: "Pegel Breitbandrauschen", value: $mmlDb, range: -80...(-8), color: Theme.lab, format: { "\(Int($0)) dB" })
                    .onChange(of: mmlDb) { _, v in noise?.setLevel(v) }
            }
            .card()
            Button("Tinnitus ist gerade verdeckt") { save(mml: mmlDb) }.buttonStyle(.primary(Theme.lab))
            TextLinkButton("Lässt sich nicht verdecken") { save(mml: nil) }
        }
    }

    private func save(mml: Double?) {
        stopAll()
        let c = MatchAnalysis.combine(trials: trials)
        let m = TinnitusMatch(ear: ear, freq: c.freq.rounded(), trials: trials.map { $0.rounded() }, spreadOctaves: c.spreadOctaves,
                              loudnessDb: loudnessDb.rounded(), timbre: timbre, mmlDb: mml?.rounded(), device: engine.deviceStamp)
        ctx.insert(m)
        ctx.settings().preferredEar = ear
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
        saved = m
        Haptics.success()
        phase = .done
    }

    // MARK: Done

    @ViewBuilder
    private var done: some View {
        if let m = saved {
            let (v, u) = Format.hzParts(m.freq)
            let est = engine.estimator
            VStack(spacing: 12) {
                Eyebrow("Gespeichert", color: Theme.lab)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v).font(.display(48)).foregroundStyle(Theme.tin)
                    Text(u).font(.title3.weight(.semibold)).foregroundStyle(Theme.text2)
                }
                HStack(spacing: 10) {
                    Metric(label: "Ohr", value: m.ear.label)
                    Metric(label: "Lautheit", value: "\(Int(m.loudnessDb))", unit: "dB")
                    Metric(label: "MML", value: m.mmlDb.map { "\(Int($0))" } ?? "–", unit: "dB")
                }
                if m.device.calibrated {
                    Text("Geschätzt: Lautheit ≈ \(Int(est.spl(dbfs: m.loudnessDb, at: m.freq))) dB SPL\(m.mmlDb.map { " · MML ≈ \(Int(est.spl(dbfs: $0, at: 4000))) dB SPL" } ?? "") (\(m.device.kind.label), ±\(Int(est.profile.uncertainty(at: m.freq))) dB)")
                        .font(.caption).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .card(glow: Theme.lab)
            TinnitusPreviewButton(match: m)
            Button { model.replaceTop(with: .hearing) } label: { NextLabel("Weiter: Hörcheck") }
                .buttonStyle(.primary(Theme.lab))
            TextLinkButton("Anderes Ohr messen") {
                trials = []
                phase = .setup
            }
        }
    }
}

/// Horizontal log-frequency pad: drag to tune, haptic tick at octave boundaries, likeness overlay.
struct FrequencyPad: View {
    @Binding var frequency: Double
    var overlay: [SpectrumPoint] = []
    var fMin = MatchAnalysis.fMin
    var fMax = MatchAnalysis.fMax
    var onStart: (Double) -> Void
    var onMove: (Double) -> Void
    var onEnd: () -> Void
    @State private var dragging = false
    @State private var lastOctave: Int?

    private let octaves: [Double] = [1000, 2000, 4000, 8000, 16000]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let x = CGFloat(MatchAnalysis.position(of: frequency, fMin: fMin, fMax: fMax)) * w
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface2)
                // likeness overlay
                ForEach(overlay, id: \.freq) { p in
                    let px = CGFloat(MatchAnalysis.position(of: p.freq, fMin: fMin, fMax: fMax)) * w
                    Capsule().fill(Theme.tin.opacity(0.10 + 0.25 * p.value / 10))
                        .frame(width: 10, height: max(4, CGFloat(p.value / 10) * h * 0.8))
                        .position(x: px, y: h - max(4, CGFloat(p.value / 10) * h * 0.8) / 2 - 4)
                }
                ForEach(octaves, id: \.self) { f in
                    let px = CGFloat(MatchAnalysis.position(of: f, fMin: fMin, fMax: fMax)) * w
                    Rectangle().fill(Theme.stroke2).frame(width: 1, height: h).position(x: px, y: h / 2)
                    Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))").font(.caption2).foregroundStyle(Theme.text3)
                        .position(x: px, y: 12)
                }
                // cursor
                Rectangle().fill(Theme.lab).frame(width: 2, height: h).position(x: x, y: h / 2)
                Circle().fill(Theme.lab).frame(width: dragging ? 34 : 26, height: dragging ? 34 : 26)
                    .shadow(color: Theme.lab.opacity(0.6), radius: dragging ? 14 : 6)
                    .position(x: x, y: h / 2)
                    .animation(.spring(duration: 0.2), value: dragging)
                Text(Format.hz(frequency)).font(.display(20)).monospacedDigit().foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .position(x: min(max(x, 60), w - 60), y: h - 22)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = MatchAnalysis.freq(at: Double(v.location.x / w), fMin: fMin, fMax: fMax)
                        frequency = f
                        let oct = Int(floor(log2(f / 1000)))
                        if let lo = lastOctave, lo != oct { Haptics.tick() }
                        lastOctave = oct
                        if !dragging {
                            dragging = true
                            onStart(f)
                        } else {
                            onMove(f)
                        }
                    }
                    .onEnded { _ in
                        dragging = false
                        lastOctave = nil
                        onEnd()
                    }
            )
        }
        .frame(height: 200)
        .accessibilityElement()
        .accessibilityLabel("Frequenz-Pad")
        .accessibilityValue(Format.hz(frequency))
        .accessibilityAdjustableAction { dir in
            let semis = dir == .increment ? 1.0 : -1.0
            frequency = min(fMax, max(fMin, frequency * pow(2, semis / 12)))
            onStart(frequency)
            Task {
                try? await Task.sleep(for: .seconds(1))
                onEnd()
            }
        }
    }
}

struct FlowChips: View {
    var items: [String]
    var extra: (String, Bool)?
    var body: some View {
        ViewThatFits {
            HStack { chips }
            VStack(alignment: .leading) { chips }
        }
    }
    @ViewBuilder private var chips: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { Chip($0.element) }
        if let extra { Chip(extra.0, tone: extra.1 ? .warn : .good) }
    }
}

/// Type-erased button style for conditional styling.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
