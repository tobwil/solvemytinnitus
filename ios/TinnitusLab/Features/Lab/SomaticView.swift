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

/// Neck range of motion with AirPods: six movements, the peak angle of each is recorded.
struct MobilityTestView: View {
    var onDone: (NeckROM) -> Void
    var skip: () -> Void
    @State private var tracker = HeadTracker.shared
    @State private var index = -1
    @State private var peak = 0.0
    @State private var values: [Double] = []
    @State private var countdown = 6
    @State private var task: Task<Void, Never>?

    private let moves: [(String, MotionTarget.Axis, Double)] = [
        ("Kopf nach links drehen", .yaw, -1), ("Kopf nach rechts drehen", .yaw, 1),
        ("Ohr zur linken Schulter", .roll, -1), ("Ohr zur rechten Schulter", .roll, 1),
        ("Kinn zur Brust", .pitch, 1), ("Blick zur Decke", .pitch, -1),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nacken-Beweglichkeit").font(.titleL)
            if index < 0 {
                Text("Setz deine AirPods auf und sitz aufrecht. Bewege den Kopf langsam bis zur angenehmen Grenze, nicht darüber hinaus. Der Wert ist dein Ausgangspunkt fürs Körper-Modul.")
                    .foregroundStyle(Theme.text2)
                HStack {
                    Image(systemName: tracker.connected ? "checkmark.circle.fill" : "airpodspro").foregroundStyle(tracker.connected ? Theme.good : Theme.text3)
                    Text(tracker.connected ? "AirPods-Bewegungssensor verbunden" : "Warte auf AirPods-Bewegungsdaten …").font(.subheadline)
                }
                .card(padding: 12)
                Button("Messung starten") { begin() }.buttonStyle(.primary(Theme.body)).disabled(!tracker.connected)
                TextLinkButton("Überspringen", action: skip)
            } else if index < moves.count {
                let m = moves[index]
                ProgressDots(total: moves.count, done: index, color: Theme.body)
                VStack(spacing: 12) {
                    Text(m.0).font(.titleM)
                    AngleGauge(value: tracker.value(m.1) * m.2, peak: peak, color: Theme.body)
                    Text("\(countdown) s").font(.display(28)).monospacedDigit().foregroundStyle(Theme.text2)
                    if tracker.speed > 120 { Text("Langsamer bewegen").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn) }
                }
                .frame(maxWidth: .infinity)
                .card()
            }
        }
        .onAppear { tracker.start() }
        .onDisappear { task?.cancel(); tracker.stop() }
    }

    private func begin() {
        values = []
        task = Task {
            for i in moves.indices {
                index = i
                peak = 0
                tracker.recenter()
                try? await Task.sleep(for: .milliseconds(300))
                for s in stride(from: 6, through: 1, by: -1) {
                    countdown = s
                    for _ in 0..<10 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if Task.isCancelled { return }
                        peak = max(peak, tracker.value(moves[i].1) * moves[i].2)
                    }
                }
                values.append(peak)
                Haptics.tick()
                // back to neutral
                try? await Task.sleep(for: .seconds(1.5))
            }
            index = moves.count
            onDone(NeckROM(rotationLeft: values[0], rotationRight: values[1], tiltLeft: values[2], tiltRight: values[3], flexion: values[4], extensionDeg: values[5]))
        }
    }
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
