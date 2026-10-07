import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Runs one body programme as a guided, step-by-step instruction: big cue, numbered steps, timer per
/// side, rhythm phases with haptics, mistakes to avoid, optional speech and AirPods guidance
/// (target angle with hold ring, haptic at the target, warning on jerky movement).
struct BodyProgramView: View {
    var program: BodyProgramID
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var tracker = HeadTracker.shared
    @State private var index = 0
    @State private var side = 0
    @State private var left = 0.0
    @State private var running = false
    @State private var started = false
    @State private var finished = false
    @State private var startDate = Date.now
    @State private var sessionStart = Date.now
    @State private var completed = 0
    @State private var task: Task<Void, Never>?
    @State private var holdProgress = 0.0
    @State private var reached = false
    @State private var useTracking = true
    @State private var jawTension: Int?
    @State private var measureROM = false
    @State private var rom: NeckROM?
    @State private var saved = false
    @State private var finishedDuration = 0.0
    @State private var phaseIndex = -1
    @State private var sideBanner = false

    private var contra: Set<Contraindication> { Set((ctx.settings().contraindications ?? []).compactMap(Contraindication.init(rawValue:))) }
    private var prog: BodyProgram { BodyContent.program(program) }
    private var exercises: [BodyExercise] { prog.exercises(excluding: contra) }
    private var ex: BodyExercise { exercises[min(index, exercises.count - 1)] }
    private var tracking: Bool { useTracking && tracker.connected && ex.motion != nil }

    var body: some View {
        Screen {
            if finished {
                doneView
            } else if !started {
                intro
            } else {
                runner
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(started && !finished ? .hidden : .visible, for: .tabBar)
        .animation(.easeInOut, value: started)
        .onAppear {
            #if DEBUG
            // screenshots/UI tests: -autostart [-exercise n3] [-side 1]
            let args = ProcessInfo.processInfo.arguments
            if !started, args.contains("-autostart") {
                begin()
                if let i = args.firstIndex(of: "-exercise"), i + 1 < args.count, let idx = exercises.firstIndex(where: { $0.id == args[i + 1] }) {
                    index = idx
                    if let j = args.firstIndex(of: "-side"), j + 1 < args.count, let sv = Int(args[j + 1]) { side = sv }
                    enterExercise()
                }
                if args.contains("-finish") {
                    completed = exercises.count
                    finish()
                }
            }
            #endif
        }
        .onDisappear {
            task?.cancel()
            tracker.stop()
            Speech.shared.stop()
            if started && completed > 0 && !saved { save() }
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(eyebrow: "Körper", title: prog.title, lead: "\(exercises.count) Übungen, ca. \(prog.minutes(excluding: contra)) Minuten. Langsam, ohne Schmerz, ruhig weiteratmen. Ein Glockenton und eine leichte Vibration markieren jeden Wechsel – du kannst die Augen schließen.")
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { i, e in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.body).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.subheadline.weight(.semibold))
                            Text(e.target).font(.caption).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Text(e.sides == 2 ? "2 × \(Int(e.seconds)) s" : "\(Int(e.seconds)) s").font(.caption).monospacedDigit().foregroundStyle(Theme.text3)
                    }
                    .padding(.vertical, 8)
                }
            }
            .card()
            if !contra.isEmpty {
                Callout("Wegen deiner Angaben (\(contra.map(\.label).joined(separator: ", "))) sind nur die sanften Übungen enthalten.", tone: .warn)
            }
            if tracker.isAvailable && exercises.contains(where: { $0.motion != nil }) {
                Toggle("AirPods-Kopftracking verwenden", isOn: $useTracking).tint(Theme.body).card(padding: 12)
            }
            Button("Starten") { begin() }.buttonStyle(.primary(Theme.body))
        }
    }

    private func begin() {
        started = true
        sessionStart = .now
        index = 0
        side = 0
        completed = 0
        if useTracking { tracker.start() }
        AudioEngine.shared.configureSession(mixWithOthers: true)
        enterExercise()
        running = true
        runClock()
    }

    // MARK: Runner

    private var runner: some View {
        let elapsed = ex.seconds - left
        let phase = ex.rhythm.map { $0.phase(at: elapsed) }
        return VStack(spacing: 14) {
            ProgressDots(total: exercises.count, done: index, color: Theme.body)
            HStack {
                Eyebrow("Übung \(index + 1) von \(exercises.count)", color: Theme.body)
                Spacer()
                if ex.sides == 2 {
                    Chip(side == 0 ? "Linke Seite" : "Rechte Seite", tone: .tint(Theme.body), symbol: side == 0 ? "arrow.left" : "arrow.right")
                }
            }
            VStack(spacing: 16) {
                RingView(progress: ex.seconds > 0 ? elapsed / ex.seconds : 0, color: Theme.body, lineWidth: 10) {
                    VStack(spacing: 2) {
                        Text(Format.duration(left)).font(.display(40)).monospacedDigit().contentTransition(.numericText(countsDown: true))
                        if let phase, let r = ex.rhythm {
                            Text(r.phases[phase.index].label)
                                .font(.headline).foregroundStyle(Theme.body)
                                .id(phase.index)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: phase?.index)
                }
                .frame(width: 190, height: 190)
                .overlay(alignment: .top) {
                    if sideBanner {
                        Text("Seitenwechsel").font(.caption.weight(.bold)).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.body))
                            .offset(y: -14)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                Text(ex.cue).font(.titleL).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .id(ex.id)
                    .transition(.opacity)
                HStack(spacing: 10) {
                    Button { previous() } label: { Image(systemName: "backward.fill").frame(maxWidth: .infinity) }.buttonStyle(.ghost(Theme.body, large: true))
                        .accessibilityLabel("Vorherige Übung").disabled(index == 0 && side == 0)
                    Button { running.toggle(); if running { runClock() } else { task?.cancel() } } label: {
                        Image(systemName: running ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary(Theme.body))
                    .accessibilityLabel(running ? "Pause" : "Weiter")
                    Button { advance() } label: { Image(systemName: "forward.fill").frame(maxWidth: .infinity) }.buttonStyle(.ghost(Theme.body, large: true))
                        .accessibilityLabel("Nächste Übung")
                }
                if tracking, let m = ex.motion {
                    let target = abs(m.degrees)
                    let value = abs(tracker.value(m.axis))
                    VStack(spacing: 6) {
                        AngleGauge(value: value, peak: value, target: target, color: reached ? Theme.good : Theme.body)
                        Text(reached ? "Ziel erreicht – locker halten" : "Ziel \(Int(target))° · halten bis der Balken voll ist").font(.caption).foregroundStyle(Theme.text2)
                        ProgressView(value: holdProgress).tint(reached ? Theme.good : Theme.tin).frame(maxWidth: 220)
                        if tracker.speed > 120 { Text("Langsamer – keine ruckartigen Bewegungen").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .card(glow: Theme.body, padding: 20)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ex.title).font(.titleM)
                    Spacer()
                    Text(ex.target).font(.caption.weight(.semibold)).foregroundStyle(Theme.body).multilineTextAlignment(.trailing)
                }
                ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 22, height: 22).background(Circle().fill(Theme.body.opacity(0.85)))
                        Text(step).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !ex.mistake.isEmpty {
                    Label(ex.mistake, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.warn)
                }
            }
            .card()
            if index + 1 < exercises.count {
                HStack(spacing: 6) {
                    Text("Als Nächstes").font(.caption).foregroundStyle(Theme.text3)
                    Text(exercises[index + 1].title).font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: ex.id)
        .animation(.spring(duration: 0.4), value: sideBanner)
    }

    private func enterExercise() {
        left = ex.seconds
        startDate = .now
        holdProgress = 0
        reached = false
        phaseIndex = -1
        tracker.recenterIfNeutral()
        AudioEngine.shared.chime(levelDb: -32)
        Haptics.soft()
        if ctx.settings().speakTTS { Speech.shared.say(ex.cue(side: side)) }
    }

    /// Haptic tick (and spoken label) when the rhythm phase changes.
    private func tickRhythm() {
        guard let r = ex.rhythm else { return }
        let p = r.phase(at: ex.seconds - left).index
        if p != phaseIndex {
            if phaseIndex >= 0 {
                Haptics.tick()
                if ctx.settings().speakTTS { Speech.shared.say(r.phases[p].label) }
            }
            phaseIndex = p
        }
    }

    private func runClock() {
        task?.cancel()
        task = Task {
            while !Task.isCancelled && running {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled || !running { return }
                withAnimation(.linear(duration: 0.25)) { left -= 0.25 }
                tickRhythm()
                trackHold(dt: 0.25)
                if left <= 0 { advance() }
            }
        }
    }

    /// Fills the ring while the head is within ±8° of the target (signed per side).
    private func trackHold(dt: Double) {
        guard tracking, let m = ex.motion else { return }
        let target = side == 1 ? -m.degrees : m.degrees
        let v = tracker.value(m.axis)
        if abs(v - target) <= 8 || (abs(v) >= abs(target) && v.sign == target.sign) {
            holdProgress = min(1, holdProgress + dt / m.holdS)
            if holdProgress >= 1 && !reached {
                reached = true
                Haptics.success()
            }
        }
    }

    private func advance() {
        if ex.sides == 2 && side == 0 {
            side = 1
            sideBanner = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                sideBanner = false
            }
            enterExercise()
            return
        }
        completed = max(completed, index + 1)
        if index + 1 >= exercises.count {
            finish()
            return
        }
        index += 1
        side = 0
        enterExercise()
    }

    private func previous() {
        if side == 1 { side = 0 } else if index > 0 { index -= 1; side = 0 }
        enterExercise()
    }

    private func finish() {
        running = false
        task?.cancel()
        AudioEngine.shared.chime(levelDb: -28)
        finishedDuration = Date.now.timeIntervalSince(sessionStart)
        finished = true
    }

    private func save() {
        guard !saved else { return }
        saved = true
        let s = BodySession(program: program, durationS: Date.now.timeIntervalSince(sessionStart), completedExercises: completed,
                            gentleOnly: !contra.isEmpty, rom: rom, jawTension: jawTension.map(Double.init))
        DataActions.saveBody(ctx, s)
    }

    // MARK: Done

    @ViewBuilder
    private var doneView: some View {
        if measureROM {
            MobilityTestView { r in
                rom = r
                measureROM = false
            } skip: { measureROM = false }
        } else {
            CompletionCard(title: "Geschafft", subtitle: program == .neck ? "Nacken und Schultern – schön locker bleiben." : "Kiefer und Gesicht – Zähne auseinander, Zunge am Gaumen.", color: Theme.body,
                           stats: [("Minuten", Format.duration(finishedDuration)), ("Übungen", "\(completed)/\(exercises.count)")] + (rom.map { [("Beweglichkeit", "\(Int($0.total))°")] } ?? []))
            if program == .jaw {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wie angespannt ist dein Kiefer jetzt?").font(.titleM)
                    Scale10(value: $jawTension, labels: ("ganz locker", "sehr angespannt"), color: Theme.body)
                }
                .card()
            }
            if program == .neck && tracker.isAvailable && rom == nil {
                Button { measureROM = true } label: { Label("Beweglichkeit mit AirPods messen", systemImage: "airpodspro") }
                    .buttonStyle(.ghost(Theme.body, large: true))
            }
            Button("Speichern") {
                save()
                model.showToast("Körper-Programm gespeichert")
                model.pop()
            }
            .buttonStyle(.primary(Theme.body))
        }
    }
}
