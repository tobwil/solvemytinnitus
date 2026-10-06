import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Welcome → warning signs → headphones → volume anchor → profile & native extras.
struct OnboardingView: View {
    @Environment(\.modelContext) private var ctx
    @State private var step = 1
    private let total = 5

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                VStack(spacing: 0) {
                    ProgressDots(total: total, done: step, color: Theme.sound)
                        .padding(.horizontal, 20).padding(.top, 8)
                    Group {
                        switch step {
                        case 1: WelcomeStep { step = 2 }
                        case 2: RedFlagStep(next: { step = 3 }, back: { step = 1 })
                        case 3: HeadphonesStep(returning: false, next: { step = 4 }, back: { step = 2 })
                        case 4: VolumeStep(next: { step = 5 }, back: { step = 3 })
                        default: ProfileStep(back: { step = 4 })
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Scrollable content with pinned actions at the bottom.
struct StepFrame<Content: View, Actions: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(20)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            VStack(spacing: 4) { actions }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: 640)
        }
    }
}

private struct WelcomeStep: View {
    var next: () -> Void
    var body: some View {
        StepFrame {
            HeroWave().frame(height: 140).padding(.vertical, 8)
            Eyebrow("Willkommen")
            Text("Dein persönliches Tinnitus-Labor").font(.titleXL)
            Text("Statt irgendeinem Rauschen findest du hier heraus, welcher Klang deinen Tinnitus nachweislich leiser macht, und trainierst gezielt damit. Kombiniert mit dem Verfahren, das in Studien am besten gegen die Belastung wirkt: kognitivem Training.")
                .foregroundStyle(Theme.text2)
            VStack(spacing: 10) {
                FeatureRow(symbol: "flask", title: "Messen", sub: "Spektrum, Tonhöhe, Lautheit, Hörcheck, Somatik")
                FeatureRow(symbol: "eye.slash", title: "Experimentieren", sub: "Verblindete Tests, welcher Klang bei dir wirkt")
                FeatureRow(symbol: "waveform", title: "Trainieren", sub: "Klangprogramme, Kopf-Training, Nacken und Kiefer")
                FeatureRow(symbol: "chart.line.uptrend.xyaxis", title: "Auswerten", sub: "Was wirkt bei dir, belegt mit deinen Daten")
            }
            .card()
            Text(SafetyContent.disclaimer).font(.caption).foregroundStyle(Theme.text3)
        } actions: {
            Button("Los geht’s", action: next).buttonStyle(.primary())
        }
    }
}

private struct FeatureRow: View {
    var symbol: String
    var title: String
    var sub: String
    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: Theme.sound)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(sub).font(.caption).foregroundStyle(Theme.text2)
            }
            Spacer()
        }
    }
}

private struct RedFlagStep: View {
    var next: () -> Void
    var back: () -> Void
    @State private var answer: Bool?

    var body: some View {
        StepFrame {
            Eyebrow("Vorab")
            Text("Gibt es Warnzeichen?").font(.titleL)
            Text("Diese Zeichen gehören zeitnah zum HNO-Arzt, bevor du mit einem Selbst-Experiment beginnst:")
                .foregroundStyle(Theme.text2)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(SafetyContent.redFlags, id: \.self) { f in
                    Label(f, systemImage: "exclamationmark.circle").foregroundStyle(Theme.text)
                }
            }
            .card(glow: Theme.warn)
            ChoiceRow(title: "Nichts davon trifft zu", sub: nil, symbol: "checkmark", selected: answer == false, color: Theme.good) { answer = false }
            ChoiceRow(title: "Etwas davon trifft zu", sub: "Bitte lass das zuerst ärztlich abklären. Du kannst die App trotzdem nutzen.", symbol: "stethoscope", selected: answer == true, color: Theme.warn) { answer = true }
            if answer == true {
                Callout("Bei plötzlichem Hörverlust oder Schwindel: noch heute HNO-Praxis oder Notaufnahme. Pulsierender oder neu einseitiger Tinnitus sollte innerhalb weniger Tage abgeklärt werden.", tone: .warn)
            }
        } actions: {
            Button("Weiter", action: next).buttonStyle(.primary()).disabled(answer == nil)
            TextLinkButton("Zurück", action: back)
        }
    }
}

/// Headphone detection and left/right check (also used as lab step 1).
struct HeadphonesStep: View {
    var returning: Bool
    var next: () -> Void
    var back: () -> Void
    @Environment(\.modelContext) private var ctx
    @State private var engine = AudioEngine.shared
    @State private var okLeft = false
    @State private var okRight = false
    @State private var playing: Ear?

    var body: some View {
        StepFrame {
            Eyebrow(returning ? "Messung · Schritt 1" : "Schritt 1")
            Text("Kopfhörer prüfen").font(.titleL)
            deviceCard
            Text("Tippe beide Seiten an und prüfe, ob der Ton auf dem richtigen Ohr ankommt. Für Töne über 10 kHz brauchst du gute In-Ear- oder Over-Ear-Kopfhörer.")
                .foregroundStyle(Theme.text2)
            HStack(spacing: 12) {
                earButton(.left, ok: okLeft)
                earButton(.right, ok: okRight)
            }
            if engine.deviceKind.isApple {
                Callout("AirPods: Schalte für Messungen „Adaptives Audio“, „Konversationserkennung“ und die Geräuschunterdrückung aus (Kontrollzentrum › Lautstärke gedrückt halten). Die App kann das nicht selbst steuern.")
            }
        } actions: {
            Button("Ja, links und rechts stimmen") {
                ctx.settings().headphonesOk = true
                try? ctx.save()
                next()
            }
            .buttonStyle(.primary())
            .disabled(!(okLeft && okRight))
            if !returning {
                TextLinkButton("Keine Kopfhörer zur Hand – später prüfen", action: next)
            }
            TextLinkButton(returning ? "Abbrechen" : "Zurück", action: back)
        }
        .onAppear { engine.configureSession() }
        .onDisappear { engine.stopAll() }
    }

    private var deviceCard: some View {
        let kind = engine.deviceKind
        let profile = DeviceProfile.profile(for: kind)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(symbol: kind == .speaker ? "speaker.wave.2" : kind.isApple ? "airpodspro" : "headphones", color: kind == .speaker ? Theme.warn : Theme.lab)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.route.name.isEmpty ? kind.label : engine.route.name).font(.body.weight(.semibold))
                    Text(kind == .speaker ? "Lautsprecher – Messungen gesperrt" : profile.calibrated ? "\(kind.label) · Kalibrierprofil geladen (Pegel geschätzt in dB SPL)" : "\(kind.label) · unkalibriert, Messungen werden als „relativ“ gespeichert")
                        .font(.caption).foregroundStyle(Theme.text2)
                }
            }
            if kind == .airPodsPro2 || kind == .airPodsPro3 {
                Picker("Modell", selection: Binding(get: { engine.deviceOverride ?? kind }, set: { engine.deviceOverride = $0 })) {
                    Text("AirPods Pro 2").tag(DeviceKind.airPodsPro2)
                    Text("AirPods Pro 3").tag(DeviceKind.airPodsPro3)
                }
                .pickerStyle(.segmented)
            }
            if kind == .speaker {
                Callout("Setz Kopfhörer auf. Über den Lautsprecher ist nur Klanganreicherung erlaubt, keine Messungen.", tone: .warn)
            }
        }
        .card()
    }

    private func earButton(_ ear: Ear, ok: Bool) -> some View {
        Button {
            guard engine.canMeasure else { return }
            playing = ear
            engine.stopAll()
            let v = engine.play(.tone(freq: 1000), ear: ear, levelDb: -26, purpose: .cue)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                v.stop(fadeMs: 60)
                playing = nil
                if ear == .left { okLeft = true } else { okRight = true }
                Haptics.tick()
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "headphones").font(.system(size: 30))
                    .foregroundStyle(ok ? Theme.good : playing == ear ? Theme.sound : Theme.text2)
                    .symbolEffect(.pulse, isActive: playing == ear)
                Text(ear == .left ? "Links" : "Rechts").font(.headline)
                Text("Tippen zum Abspielen").font(.caption).foregroundStyle(Theme.text3)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(playing == ear ? Theme.sound.opacity(0.12) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(ok ? Theme.good.opacity(0.5) : Theme.stroke))
        }
        .buttonStyle(.plain)
        .disabled(!engine.canMeasure)
        .accessibilityLabel("Testton \(ear == .left ? "links" : "rechts")")
        .accessibilityValue(ok ? "geprüft" : "")
    }
}

/// Volume anchor: system volume ~50 %, app volume set on a reference noise.
struct VolumeStep: View {
    var next: () -> Void
    var back: () -> Void
    @Environment(\.modelContext) private var ctx
    @State private var engine = AudioEngine.shared
    @State private var volume = 0.5
    @State private var voice: VoiceHandle?

    var body: some View {
        StepFrame {
            Eyebrow("Schritt 2")
            Text("Lautstärke festlegen").font(.titleL)
            Text("Stell die Lautstärke deines iPhones auf etwa 50 % und lass sie ab jetzt so. Regle dann hier, bis das Rauschen leise, aber klar hörbar ist, etwa so laut wie ein ruhiges Gespräch.")
                .foregroundStyle(Theme.text2)
            VStack(spacing: 12) {
                HStack {
                    Text("iPhone-Lautstärke").foregroundStyle(Theme.text2)
                    Spacer()
                    Text("\(Int(engine.systemVolume * 100)) %").monospacedDigit().foregroundStyle(abs(engine.systemVolume - 0.5) < 0.15 ? Theme.good : Theme.warn)
                }
                .font(.subheadline)
                Button(voice == nil ? "Referenzrauschen abspielen" : "Stopp") {
                    if let v = voice { v.stop(fadeMs: 200); voice = nil } else {
                        voice = engine.play(.noise(.pink), ear: .both, levelDb: -30, purpose: .cue)
                    }
                }
                .buttonStyle(.ghost(Theme.sound))
                LabeledSlider(label: "App-Lautstärke", value: $volume, range: 0.05...1, step: 0.01, color: Theme.sound, format: { "\(Int($0 * 100)) %" })
                    .onChange(of: volume) { _, v in engine.masterVolume = v }
            }
            .card()
            Callout("Kein Verfahren in dieser App wirkt besser, wenn es lauter ist. Leise ist sicher und meist wirksamer. Pegel sind gedeckelt (max. ca. 85 dB SPL, Messungen max. 80 dB SPL).", tone: .warn)
        } actions: {
            Button("Passt so") {
                voice?.stop(fadeMs: 200)
                ctx.settings().masterVolume = volume
                try? ctx.save()
                next()
            }
            .buttonStyle(.primary())
            TextLinkButton("Zurück") { voice?.stop(fadeMs: 100); back() }
        }
        .onAppear {
            volume = ctx.settings().masterVolume
            engine.configureSession()
        }
        .onDisappear { voice?.stop(fadeMs: 100) }
    }
}

private struct ProfileStep: View {
    var back: () -> Void
    @Environment(\.modelContext) private var ctx
    @State private var ear: Ear = .both
    @State private var name = ""
    @State private var reminders = true
    @State private var health = false

    var body: some View {
        StepFrame {
            Eyebrow("Schritt 3")
            Text("Wo hörst du ihn?").font(.titleL)
            Text("Wir messen jedes Ohr getrennt, wenn sich der Tinnitus unterscheidet. Bei beidseitig gleichem Ton reicht „beide“.")
                .foregroundStyle(Theme.text2)
            ChoiceRow(title: "Beide Ohren, etwa gleich", sub: "Messung und Klang binaural", selected: ear == .both) { ear = .both }
            ChoiceRow(title: "Links lauter", sub: "Wir beginnen links", selected: ear == .left) { ear = .left }
            ChoiceRow(title: "Rechts lauter", sub: "Wir beginnen rechts", selected: ear == .right) { ear = .right }
            TextField("Wie dürfen wir dich nennen? (optional)", text: $name)
                .textContentType(.givenName)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
            VStack(spacing: 4) {
                Toggle(isOn: $reminders) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check-in-Erinnerungen").font(.body.weight(.semibold))
                        Text("3× täglich zu zufälligen Zeiten morgens, mittags, abends. Nie nachts.").font(.caption).foregroundStyle(Theme.text2)
                    }
                }
                Divider().padding(.vertical, 6)
                Toggle(isOn: $health) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health verbinden").font(.body.weight(.semibold))
                        Text("Hörtest-Audiogramm, Schlaf, HRV und Lärm als automatische Auslöser. Bleibt auf deinem Gerät.").font(.caption).foregroundStyle(Theme.text2)
                    }
                }
                .disabled(!HealthService.shared.isAvailable)
            }
            .tint(Theme.sound)
            .card()
            Callout("**Ehrlich vorab:** Chronischer Tinnitus nach Lärm ist heute nicht heilbar. Realistisch ist, die Lautheit bei einem Teil der Betroffenen messbar zu senken und die Belastung deutlich zu verringern. Diese App hilft dir, herauszufinden, was davon bei dir funktioniert.")
        } actions: {
            Button("Programm starten") { Task { await finish() } }.buttonStyle(.primary(Theme.sound))
            TextLinkButton("Zurück", action: back)
        }
        .onAppear { ear = ctx.settings().preferredEar }
    }

    private func finish() async {
        let s = ctx.settings()
        s.preferredEar = ear
        s.name = name.trimmingCharacters(in: .whitespaces)
        s.programStart = s.programStart ?? .now
        if reminders, await ReminderService.shared.requestPermission() {
            s.remindersOn = true
            await ReminderService.shared.reschedule(checkins: true, windows: s.reminderWindows, sessions: false)
        }
        if health, await HealthService.shared.requestAuthorization() {
            s.useHealthKit = true
            Task { await HealthService.shared.sync(into: ctx) }
        }
        s.onboarded = true
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
    }
}

/// Animated wave with the amber tinnitus dot (onboarding hero).
struct HeroWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || AppEnv.isUITest)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                for k in 0..<6 {
                    var p = Path()
                    for xi in stride(from: 0.0, through: Double(w), by: 3) {
                        let x = xi / Double(w) * 320
                        let env = exp(-pow((x - 160) / (60 + Double(k) * 14), 2))
                        let y = 70 + sin(x / (9 + Double(k) * 2.5) + Double(k) + t * 0.6) * (46 - Double(k) * 6) * env
                        let pt = CGPoint(x: xi, y: y / 140 * Double(h))
                        if xi == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    ctx.stroke(p, with: .linearGradient(Gradient(colors: [Theme.sound.opacity(0), Theme.sound, Theme.mind, Theme.mind.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)), style: StrokeStyle(lineWidth: 2.4 - Double(k) * 0.3, lineCap: .round))
                }
                let r = 4 + 1.5 * sin(t * 2.6)
                ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - r, y: h / 2 - r, width: 2 * r, height: 2 * r)), with: .color(Theme.tin))
            }
        }
        .accessibilityHidden(true)
    }
}
