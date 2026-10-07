import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Somatic modulation screen (Sanchez 2002, Michiels 2018 criteria) plus optional neck mobility
/// baseline from AirPods head tracking for the body module.
struct SomaticView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var engine = AudioEngine.shared

    enum Phase: Equatable { case intro, prepare(Int), hold(Int, Int), rate(Int), mobility, result }
    @State private var phase = Phase.intro
    @State private var results: [SomaticResult] = []
    @State private var rom: NeckROM?
    @State private var saved: SomaticTest?
    @State private var holdTask: Task<Void, Never>?
    private let maneuvers = SomaticContent.maneuvers

    var body: some View {
        Screen {
            Eyebrow("Messung · Schritt 5", color: Theme.lab)
            Text("Somatik-Check").font(.titleXL)
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { holdTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            Text("Bei rund zwei Dritteln der Betroffenen verändert sich der Tinnitus, wenn Kiefer- oder Nackenmuskeln angespannt werden. Das zeigt eine Verschaltung zwischen Hörbahn und Körperwahrnehmung.")
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 12) {
                Label("8 Bewegungen, je 5 Sekunden", systemImage: "hand.raised")
                Label("Danach: lauter, leiser, gleich oder anders?", systemImage: "ear")
                Label("Optional mit AirPods: Nacken-Beweglichkeit messen", systemImage: "airpodspro")
                Label("Dauer: ca. 3 Minuten", systemImage: "clock")
            }
            .foregroundStyle(Theme.text)
            .card()
            Callout("Nur mit mäßiger Kraft und nichts, was schmerzt. Bei Kiefergelenk- oder Nackenbeschwerden die entsprechenden Übungen überspringen.", tone: .warn)
            Button("Starten") { results = []; phase = .prepare(0) }.buttonStyle(.primary(Theme.lab))

        case .prepare(let i):
            let m = maneuvers[i]
            ProgressDots(total: maneuvers.count, done: i, color: Theme.lab)
            VStack(spacing: 10) {
                PulseOrb(symbol: m.symbol, color: Theme.lab, active: false)
                Text(m.title).font(.titleL).multilineTextAlignment(.center)
                Text(m.how).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card()
            Button("Bereit, 5 Sekunden") { hold(i) }.buttonStyle(.primary(Theme.lab))
            TextLinkButton("Überspringen") {
                results.append(SomaticResult(maneuver: m.id, change: 0))
                advance(i)
            }

        case .hold(let i, let s):
            ProgressDots(total: maneuvers.count, done: i, color: Theme.lab)
            VStack(spacing: 10) {
                PulseOrb(symbol: "", color: Theme.lab, active: true, label: "\(s)")
                Text(maneuvers[i].title).font(.titleM)
                Text("Halten und auf den Tinnitus achten …").font(.subheadline).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity)
            .card()

        case .rate(let i):
            ProgressDots(total: maneuvers.count, done: i, color: Theme.lab)
            Text("Was hat sich verändert?").font(.titleL)
            Text("Während der Bewegung, verglichen mit vorher.").foregroundStyle(Theme.text2)
            ChoiceRow(title: "Lauter", symbol: "speaker.wave.3", selected: false) { rate(i, 1) }
            ChoiceRow(title: "Leiser", symbol: "wind", selected: false) { rate(i, -1) }
            ChoiceRow(title: "Tonhöhe oder Klang anders", symbol: "waveform", selected: false) { rate(i, 2) }
            ChoiceRow(title: "Keine Veränderung", symbol: "minus", selected: false) { rate(i, 0) }

        case .mobility:
            MobilityTestView { r in
                rom = r
                save()
            } skip: {
                save()
            }

        case .result:
            if let t = saved { resultView(t) }
        }
    }

    private func hold(_ i: Int) {
        engine.configureSession()
        engine.chime(levelDb: -34)
        holdTask = Task {
            for s in stride(from: 5, through: 1, by: -1) {
                phase = .hold(i, s)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            engine.chime(levelDb: -34)
            Haptics.soft()
            phase = .rate(i)
        }
    }

    private func rate(_ i: Int, _ change: Int) {
        results.append(SomaticResult(maneuver: maneuvers[i].id, change: change))
        advance(i)
    }

    private func advance(_ i: Int) {
        if i + 1 < maneuvers.count {
            phase = .prepare(i + 1)
        } else if HeadTracker.shared.isAvailable {
            phase = .mobility
        } else {
            save()
        }
    }

    private func save() {
        let t = SomaticTest(results: results, somatic: SomaticAnalysis.isSomatic(results), rom: rom)
        ctx.insert(t)
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
        saved = t
        phase = .result
    }

    @ViewBuilder
    private func resultView(_ t: SomaticTest) -> some View {
        let changed = t.results.filter { $0.change != 0 }.map { SomaticContent.info($0.maneuver).title }
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Ergebnis")
            Text(t.somatic ? "Dein Tinnitus ist somatisch modulierbar" : "Keine somatische Modulation").font(.titleL)
            if t.somatic { Text("Verändert bei: \(changed.joined(separator: ", ")).").foregroundStyle(Theme.text2) }
            if let rom = t.rom {
                Text("Nacken: Rotation \(Int(rom.rotationLeft))°/\(Int(rom.rotationRight))°, Seitneigung \(Int(rom.tiltLeft))°/\(Int(rom.tiltRight))°, Beugung \(Int(rom.flexion))°, Streckung \(Int(rom.extensionDeg))°")
                    .font(.caption).foregroundStyle(Theme.text3)
            }
        }
        .card(glow: t.somatic ? Theme.tin : Theme.lab)
        if t.somatic {
            Callout("Kiefer- und Nackenspannung beeinflussen deinen Tinnitus. **Sinnvoll:** Physiotherapie oder Kiefer-Abklärung (Zahnarzt, CMD), in Deutschland auf Rezept. Das Körper-Programm ist ab jetzt eine tägliche Aufgabe. Ob die Modulierbarkeit das Ansprechen auf bimodale Verfahren vorhersagt, ist noch nicht belegt.")
            Button { model.open(.body(nil)) } label: { Label("Zum Körper-Programm", systemImage: "figure.cooldown") }.buttonStyle(.ghost(Theme.body))
        } else {
            Callout("Das ist bei etwa einem Drittel der Betroffenen so und ändert nichts an den anderen Programmen. Das Körper-Programm bleibt als Entspannung verfügbar.")
        }
        Button { model.replaceTop(with: .ri) } label: { NextLabel("Weiter: RI-Labor") }.buttonStyle(.primary(Theme.lab))
    }
}

/// Neck range of motion with AirPods: six movements, the peak angle of each is recorded. The zero is
/// set once while sitting upright; before every movement the head has to be back at zero and still, and
/// each movement starts with a tap and can be repeated.
struct MobilityTestView: View {
    var onDone: (NeckROM) -> Void
    var skip: () -> Void
    @State private var tracker = HeadTracker.shared
    @State private var step = Step.intro
    @State private var values: [Double?] = []
    @State private var peak = 0.0
    @State private var countdown = 6
    @State private var steadyFor = 0.0
    /// Repeating a single movement from the summary: return there afterwards.
    @State private var fromSummary = false
    @State private var task: Task<Void, Never>?

    enum Step: Equatable { case intro, center(Int), measure(Int), review(Int), summary }

    /// Back at zero: every axis within this many degrees …
    private static let tolerance = 8.0
    /// … moving slower than this (°/s) …
    private static let stillSpeed = 12.0
    /// … for this long (s).
    private static let stillTime = 0.8

    private let moves: [(String, MotionTarget.Axis, Double)] = [
        ("Kopf nach links drehen", .yaw, -1), ("Kopf nach rechts drehen", .yaw, 1),
        ("Ohr zur linken Schulter", .roll, -1), ("Ohr zur rechten Schulter", .roll, 1),
        ("Kinn zur Brust", .pitch, 1), ("Blick zur Decke", .pitch, -1),
    ]

    private var ready: Bool { steadyFor >= Self.stillTime }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nacken-Beweglichkeit").font(.titleL)
            switch step {
            case .intro: intro
            case .center(let i): center(i)
            case .measure(let i): measuring(i)
            case .review(let i): review(i)
            case .summary: summary
            }
        }
        .onAppear { tracker.start() }
        .onDisappear { task?.cancel(); tracker.stop() }
        .task(id: step) { await watchNeutral() }
    }

    // MARK: Steps

    @ViewBuilder
    private var intro: some View {
        Text("Setz deine AirPods auf, sitz aufrecht und schau geradeaus: Das ist der Nullpunkt. Vor jeder Bewegung kehrst du dorthin zurück, gemessen wird erst, wenn du tippst. Bewege den Kopf langsam bis zur angenehmen Grenze, nicht darüber hinaus. Der Wert ist dein Ausgangspunkt fürs Körper-Modul.")
            .foregroundStyle(Theme.text2)
        HStack {
            Image(systemName: tracker.connected ? "checkmark.circle.fill" : "airpodspro").foregroundStyle(tracker.connected ? Theme.good : Theme.text3)
            Text(tracker.connected ? "AirPods-Bewegungssensor verbunden" : "Warte auf AirPods-Bewegungsdaten …").font(.subheadline)
        }
        .card(padding: 12)
        Button("Nullpunkt setzen und beginnen") {
            tracker.recenter()
            values = Array(repeating: nil, count: moves.count)
            fromSummary = false
            step = .center(0)
        }
        .buttonStyle(.primary(Theme.body))
        .disabled(!tracker.connected)
        TextLinkButton("Überspringen", action: skip)
    }

    @ViewBuilder
    private func center(_ i: Int) -> some View {
        ProgressDots(total: moves.count, done: i, color: Theme.body)
        VStack(spacing: 12) {
            Text(ready ? "Bereit" : "Zurück zur Mitte").font(.titleM)
            NeutralIndicator(yaw: tracker.yaw, pitch: tracker.pitch, tolerance: Self.tolerance, ready: ready)
            Text("Abweichung \(Int(tracker.deviation))°").font(.caption).monospacedDigit().foregroundStyle(Theme.text3)
            Text(ready ? "Als Nächstes: \(moves[i].0)." : "Sitz aufrecht, schau geradeaus und halt kurz still.")
                .font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
        Button("Messen: \(moves[i].0)") { measure(i) }
            .buttonStyle(.primary(Theme.body))
            .disabled(!ready)
        Text("Du sitzt gerade, aber der Punkt bleibt außerhalb der Mitte? Dann ist der Sensor abgedriftet.")
            .font(.caption).foregroundStyle(Theme.text3)
        TextLinkButton("Nullpunkt hier neu setzen", symbol: "scope") { tracker.recenter() }
    }

    @ViewBuilder
    private func measuring(_ i: Int) -> some View {
        let m = moves[i]
        ProgressDots(total: moves.count, done: i, color: Theme.body)
        VStack(spacing: 12) {
            Text(m.0).font(.titleM)
            AngleGauge(value: tracker.value(m.1) * m.2, peak: peak, color: Theme.body)
            Text("\(countdown) s").font(.display(28)).monospacedDigit().foregroundStyle(Theme.text2)
            if tracker.speed > 120 { Text("Langsamer bewegen").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn) }
        }
        .frame(maxWidth: .infinity)
        .card()
        TextLinkButton("Abbrechen") {
            task?.cancel()
            step = .center(i)
        }
    }

    @ViewBuilder
    private func review(_ i: Int) -> some View {
        let last = fromSummary || i + 1 >= moves.count
        ProgressDots(total: moves.count, done: i + 1, color: Theme.body)
        VStack(spacing: 6) {
            Text(moves[i].0).font(.titleM)
            Text("\(Int(values[i] ?? 0))°").font(.display(44)).monospacedDigit()
            Text("Größter Winkel dieser Bewegung").font(.caption).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity)
        .card()
        Button { step = last ? .summary : .center(i + 1) } label: { NextLabel(last ? "Zur Übersicht" : "Weiter") }
            .buttonStyle(.primary(Theme.body))
        TextLinkButton("Wiederholen", symbol: "arrow.counterclockwise") { step = .center(i) }
    }

    @ViewBuilder
    private var summary: some View {
        Text("Passt ein Wert nicht, wiederhole die Bewegung einzeln.").foregroundStyle(Theme.text2)
        VStack(spacing: 0) {
            ForEach(moves.indices, id: \.self) { i in
                HStack {
                    Text(moves[i].0).font(.subheadline)
                    Spacer()
                    Text(values[i].map { "\(Int($0))°" } ?? "–").font(.body.weight(.semibold)).monospacedDigit()
                    Button {
                        fromSummary = true
                        step = .center(i)
                    } label: {
                        Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("\(moves[i].0) wiederholen")
                }
                if i < moves.count - 1 { Divider() }
            }
        }
        .card(padding: 12)
        Button("Speichern") { save() }
            .buttonStyle(.primary(Theme.body))
            .disabled(values.contains { $0 == nil })
    }

    // MARK: Logic

    /// While waiting at zero: counts how long the head has been near zero and still.
    private func watchNeutral() async {
        steadyFor = 0
        guard case .center = step else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            let wasReady = ready
            let still = tracker.deviation <= Self.tolerance && tracker.speed <= Self.stillSpeed
            steadyFor = still ? steadyFor + 0.1 : 0
            if ready && !wasReady { Haptics.tick() }
        }
    }

    private func measure(_ i: Int) {
        task?.cancel()
        peak = 0
        countdown = 6
        step = .measure(i)
        let move = moves[i]
        task = Task {
            for s in stride(from: 6, through: 1, by: -1) {
                countdown = s
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return }
                    peak = max(peak, tracker.value(move.1) * move.2)
                }
            }
            values[i] = peak
            Haptics.success()
            step = .review(i)
        }
    }

    private func save() {
        let v = values.map { $0 ?? 0 }
        onDone(NeckROM(rotationLeft: v[0], rotationRight: v[1], tiltLeft: v[2], tiltRight: v[3], flexion: v[4], extensionDeg: v[5]))
    }
}

/// Bubble level for "back to zero": the dot follows yaw (left/right) and pitch (up/down); the inner
/// circle is the tolerance.
private struct NeutralIndicator: View {
    var yaw: Double
    var pitch: Double
    var tolerance: Double
    var ready: Bool

    /// Points per degree; the outer ring is ±30°.
    private let scale = 2.4

    var body: some View {
        let color = ready ? Theme.good : Theme.body
        ZStack {
            Circle().stroke(Theme.surface3, lineWidth: 2).frame(width: 144, height: 144)
            Circle().fill(color.opacity(0.18)).frame(width: tolerance * scale * 2, height: tolerance * scale * 2)
            Circle().fill(color).frame(width: 18, height: 18)
                .offset(x: clamp(yaw * scale), y: clamp(pitch * scale))
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ready ? "In der Mitte" : "Noch nicht in der Mitte")
    }

    private func clamp(_ v: Double) -> Double { min(63, max(-63, v)) }
}

/// Half-circle gauge for an angle in degrees with the peak marked.
struct AngleGauge: View {
    var value: Double
    var peak: Double
    var target: Double?
    var color: Color
    var maxAngle = 90.0

    var body: some View {
        ZStack {
            Arc(fraction: 1).stroke(Theme.surface3, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Arc(fraction: min(1, max(0, value / maxAngle))).stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            if let target {
                Needle(fraction: min(1, target / maxAngle)).stroke(Theme.tin, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            Needle(fraction: min(1, max(0, peak / maxAngle))).stroke(Theme.text3, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            VStack(spacing: 0) {
                Text("\(Int(max(0, value)))°").font(.display(36)).monospacedDigit()
                Text("max. \(Int(peak))°").font(.caption).foregroundStyle(Theme.text3)
            }
            .offset(y: 20)
        }
        .frame(width: 220, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Winkel \(Int(value)) Grad, Maximum \(Int(peak)) Grad")
    }

    private struct Arc: Shape {
        var fraction: Double
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: r.midX, y: r.maxY - 10), radius: r.width / 2 - 10, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fraction), clockwise: false)
            return p
        }
    }

    private struct Needle: Shape {
        var fraction: Double
        func path(in r: CGRect) -> Path {
            let c = CGPoint(x: r.midX, y: r.maxY - 10)
            let a = Double.pi * (1 + fraction)
            let rad = r.width / 2 - 10
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * (rad - 16), y: c.y + sin(a) * (rad - 16)))
            p.addLine(to: CGPoint(x: c.x + cos(a) * (rad + 10), y: c.y + sin(a) * (rad + 10)))
            return p
        }
    }
}
