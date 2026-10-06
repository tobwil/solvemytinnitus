import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Guided exercise: breath orb with haptic pacing (works with closed eyes), soft bell per step,
/// optional spoken instructions. Logs mindful minutes to Health.
struct GuidedExerciseView: View {
    var tool: MindTool
    var steps: [GuidedStep]
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var running = false
    @State private var index = 0
    @State private var stepLeft = 0.0
    @State private var elapsed = 0.0
    @State private var finished = false
    @State private var task: Task<Void, Never>?
    @State private var speak = false
    @State private var haptics = true
    @State private var rating: Int?

    private var total: Double { steps.reduce(0) { $0 + $1.seconds } }
    private var isBreath: Bool { tool.id == "breath" }

    var body: some View {
        Screen {
            if finished {
                doneView
            } else {
                VStack(spacing: 16) {
                    Eyebrow("Übung · \(tool.minutes) min", color: Theme.mind)
                    Text(tool.title).font(.titleL)
                    if isBreath {
                        BreathOrb(phase: running ? steps[index].breath : nil, seconds: steps[index].seconds, reduceMotion: reduceMotion)
                            .frame(height: 260)
                    } else {
                        RingView(progress: elapsed / total, color: Theme.mind, lineWidth: 8) {
                            VStack(spacing: 4) {
                                Text(Format.duration(total - elapsed)).font(.display(40)).monospacedDigit()
                                Text("Schritt \(index + 1) von \(steps.count)").font(.caption).foregroundStyle(Theme.text2)
                            }
                        }
                        .frame(width: 220, height: 220)
                    }
                    Text(steps[index].text).font(.titleM).multilineTextAlignment(.center)
                        .frame(minHeight: 70).frame(maxWidth: 340)
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: index)
                    PlayButton(playing: running, color: Theme.mind) { toggle() }
                    Text(isBreath ? "Im Rhythmus der Kugel atmen: größer werden = einatmen. Die Vibration führt dich auch mit geschlossenen Augen." : "Ein leiser Glockenton markiert jeden neuen Schritt. Du kannst die Augen schließen.")
                        .font(.caption).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    Toggle("Anleitung vorlesen", isOn: $speak).onChange(of: speak) { _, v in ctx.settings().speakTTS = v }
                    if isBreath { Toggle("Atem-Vibration", isOn: $haptics) }
                }
                .tint(Theme.mind)
                .font(.subheadline)
                .card()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(running ? .hidden : .visible, for: .tabBar)
        .animation(.easeInOut, value: running)
        .onAppear {
            stepLeft = steps[0].seconds
            speak = ctx.settings().speakTTS
        }
        .onDisappear {
            task?.cancel()
            Speech.shared.stop()
            Haptics.stopAll()
            if !finished && elapsed >= 30 { DataActions.logMind(ctx, kind: tool.id, durationS: elapsed, mindful: true) }
        }
    }

    private func toggle() {
        if running {
            running = false
            task?.cancel()
            Speech.shared.stop()
            return
        }
        running = true
        AudioEngine.shared.configureSession(mixWithOthers: true)
        apply()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                elapsed += 1
                stepLeft -= 1
                if stepLeft <= 0 {
                    index += 1
                    if index >= steps.count {
                        index = steps.count - 1
                        complete()
                        return
                    }
                    stepLeft = steps[index].seconds
                    apply()
                }
            }
        }
    }

    private func apply() {
        let s = steps[index]
        if isBreath {
            if haptics, let b = s.breath { Haptics.breath(inhale: b == .inhale, seconds: s.seconds) }
            if speak, index == 0 || s.breath == nil { Speech.shared.say(s.text) }
            else if speak, let b = s.breath, index < 4 { Speech.shared.say(b == .inhale ? "Ein" : "Aus") }
        } else {
            if index > 0 { AudioEngine.shared.chime(levelDb: -32) }
            if speak { Speech.shared.say(s.text) }
        }
    }

    private func complete() {
        running = false
        AudioEngine.shared.chime(levelDb: -28)
        DataActions.logMind(ctx, kind: tool.id, durationS: elapsed, mindful: true)
        finished = true
    }

    private var doneView: some View {
        CompletionCard(title: "Gut gemacht", subtitle: "\(tool.title) – Regelmäßigkeit ist wichtiger als Länge.", color: Theme.mind,
                       stats: [("Minuten", Format.duration(elapsed))]) {
            VStack(spacing: 8) {
                Text("Wie belastend ist der Tinnitus gerade?").font(.titleM).padding(.top, 6)
                Scale10(value: $rating, labels: ("gar nicht", "extrem"), color: Theme.mind) { v in
                    DataActions.addCheckIn(ctx, loudness: Double(v), distress: Double(v))
                    model.showToast("Notiert")
                    model.pop()
                }
            }
        }
    }
}

struct BreathOrb: View {
    var phase: GuidedStep.Breath?
    var seconds: Double
    var reduceMotion: Bool

    var body: some View {
        let scale: CGFloat = phase == .inhale ? 1 : phase == .exhale ? 0.55 : 0.7
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.mind.opacity(0.55), Theme.sound.opacity(0.25), .clear], center: .center, startRadius: 10, endRadius: 140))
                .frame(width: 250, height: 250)
                .scaleEffect(scale)
                .animation(reduceMotion ? nil : .easeInOut(duration: seconds), value: phase)
            Circle().strokeBorder(Theme.mind.opacity(0.5), lineWidth: 2).frame(width: 250, height: 250).scaleEffect(scale)
                .animation(reduceMotion ? nil : .easeInOut(duration: seconds), value: phase)
            Text(phase == .inhale ? "Ein" : phase == .exhale ? "Aus" : "Bereit").font(.display(28)).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .inhale ? "Einatmen" : phase == .exhale ? "Ausatmen" : "Bereit")
    }
}
