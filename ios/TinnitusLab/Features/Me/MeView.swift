import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// "Ich": your tinnitus as a portrait — what it sounds like, how it moved over the weeks, what seems to
/// help — with measurements, history, knowledge and settings underneath.
struct MeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \TinnitusMatch.date) private var matches: [TinnitusMatch]
    @Query(sort: \CheckIn.ts) private var checkins: [CheckIn]
    @Query(sort: \JournalEntry.day) private var journal: [JournalEntry]
    @Query(sort: \TherapySession.date) private var sessions: [TherapySession]
    @Query(sort: \HealthSnapshot.day) private var health: [HealthSnapshot]
    @Query private var riTrials: [RITrial]
    @Query private var settingsList: [AppSettings]
    @State private var engine = AudioEngine.shared

    var body: some View {
        let state = DataActions.programState(ctx)
        let steps = Program.labSteps(state)
        let daily = Insights.daily(days: 28, checkins: checkins.map { .init(ts: $0.ts, loudness: $0.loudness, distress: $0.distress) },
                                   journal: journal.map { .init(day: $0.day, loudness: $0.loudness, distress: $0.distress, sleep: $0.sleep, stress: $0.stress, noise: $0.noiseExposure, caffeine: $0.caffeine, alcohol: $0.alcohol) })
        Screen {
            portrait
            weeks(daily)
            findings(daily)
            if settingsList.first?.useHealthKit == true { healthStrip }
            measurements(steps)
            Eyebrow("Mehr").padding(.top, 16)
            VStack(spacing: 0) {
                Button { model.push(.progress(.overview)) } label: { LibraryRow(symbol: "chart.xyaxis.line", title: "Verlauf und Tagebuch", sub: "Alle Werte, Tagesrückblick, Fragebogen, Bericht für die Ärztin") }
                    .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                Button { model.push(.learn) } label: { LibraryRow(symbol: "book", title: "Wissen", sub: "Was die Forschung sagt") }
                    .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                Button { model.push(.settings) } label: { LibraryRow(symbol: "gearshape", title: "Einstellungen", sub: "Erinnerungen, Health, iCloud, Daten") }
                    .buttonStyle(.plain)
            }
            .card(padding: 4)
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { engine.configureSession() }
    }

    // MARK: Portrait

    @ViewBuilder
    private var portrait: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Ich")
            Text("Dein Tinnitus").font(.titleXL)
        }
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
        if let m = matches.last {
            let (v, u) = Format.hzParts(m.freq)
            let best = RIAnalysis.best(riTrials.map { .init(stimulus: $0.stimulus, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) })
            let som = ctx.latestSomatic()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v).font(.display(52)).foregroundStyle(Theme.tin).monospacedDigit()
                    Text(u).font(.title3.weight(.semibold)).foregroundStyle(Theme.tin.opacity(0.7))
                    Spacer()
                }
                Text([m.timbre == .tone ? "Ton" : "Rauschen", m.ear == .both ? "beidseitig" : m.ear.label.lowercased(),
                      m.mmlDb.map { "maskierbar ab \(Int($0)) \(m.device.calibrated ? "dB FS" : "dB rel.")" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Theme.text2)
                HStack(spacing: 8) {
                    Chip(best.map { "RI: \(SoundContent.label($0.stimulus))" } ?? "RI offen", tone: best == nil ? .neutral : .tint(Theme.accent))
                    Chip(som.map { $0.somatic ? "somatisch" : "nicht somatisch" } ?? "Somatik offen", tone: som?.somatic == true ? .tint(Theme.accent) : .neutral)
                }
                TinnitusPreviewButton(match: m)
            }
            .padding(.top, 4)
        } else {
            Text("Noch nicht vermessen. Mit der Messung unten werden alle Klänge auf deine Frequenz zugeschnitten.")
                .foregroundStyle(Theme.text2)
        }
    }

    // MARK: Weeks

    @ViewBuilder
    private func weeks(_ daily: [Insights.DailyValue]) -> some View {
        let loud = daily.compactMap { d in d.loudness.map { (d.date, $0) } }
        let dist = daily.compactMap { d in d.distress.map { (d.date, $0) } }
        if loud.count >= 2 {
            Button { model.push(.progress(.overview)) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Vier Wochen").font(.titleM).foregroundStyle(Theme.text)
                        Spacer()
                        trendChip(loud.map(\.1))
                    }
                    SeriesChart(series: [
                        .init(name: "Lautheit", color: Theme.tin, points: loud, area: true),
                        .init(name: "Belastung", color: Theme.distress, points: dist),
                    ], yDomain: 0...10, height: 150)
                    TimeOfDayStrip(checkins: checkins.filter { $0.ts > Day.daysAgo(28) })
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet den ganzen Verlauf")
        }
    }

    private func trendChip(_ v: [Double]) -> Chip {
        switch Insights.trend(v) {
        case .insufficient: Chip("zu wenig Daten")
        case .down(let d): Chip("▼ \(Format.decimal(d))", tone: .good)
        case .up(let d): Chip("▲ +\(Format.decimal(d))", tone: .warn)
        case .stable: Chip("stabil")
        }
    }

    // MARK: Findings

    /// Plain-language sentences instead of more charts. Observational, never a promise.
    @ViewBuilder
    private func findings(_ daily: [Insights.DailyValue]) -> some View {
        let lines = findingLines(daily)
        if !lines.isEmpty {
            Eyebrow("Was sich zeigt").padding(.top, 8)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines, id: \.self) { l in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6).offset(y: -2)
                        Text(l).font(.subheadline).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Beobachtungen aus deinen Einträgen, kein Wirkungsnachweis.").font(.caption).foregroundStyle(Theme.text3)
            }
            .card()
        }
    }

    private func findingLines(_ daily: [Insights.DailyValue]) -> [String] {
        var out: [String] = []
        let effects = Insights.modeEffects(sessions.map { (mode: $0.mode, pre: $0.pre, post: $0.post) }).filter { $0.n >= 3 }
        if let best = effects.min(by: { $0.interval.mean < $1.interval.mean }), best.interval.mean < -0.3 {
            out.append("Nach \(SoundContent.mode(best.mode).title) war er im Schnitt \(Format.decimal(-best.interval.mean)) Punkte leiser (\(best.n) Sitzungen).")
        }
        let slots = Insights.timeOfDay(checkins.filter { $0.ts > Day.daysAgo(28) }.map { .init(ts: $0.ts, loudness: $0.loudness, distress: $0.distress) })
            .filter { $0.n >= 3 && $0.mean != nil }
        if let hi = slots.max(by: { $0.mean! < $1.mean! }), let lo = slots.min(by: { $0.mean! < $1.mean! }), hi.mean! - lo.mean! >= 1 {
            out.append("\(hi.label)s ist er meist am lautesten, \(lo.label.lowercased())s am leisesten.")
        }
        let active = Set(sessions.filter { $0.durationS >= 600 }.map { Day.key($0.date) })
        let ww = Insights.withVsWithout(daily: daily, activeDays: active)
        if ww.with.count >= 3, ww.without.count >= 3 {
            let d = Stats.mean(ww.with) - Stats.mean(ww.without)
            if abs(d) >= 0.5 {
                out.append("An Tagen mit mindestens 10 Minuten Klang lag die Lautheit \(Format.decimal(abs(d))) Punkte \(d < 0 ? "niedriger" : "höher").")
            }
        }
        return out
    }

    // MARK: Health

    private var healthStrip: some View {
        let today = Day.key()
        let yesterday = Day.key(Day.daysAgo(1))
        let byDay = Dictionary(health.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Aus Apple Health").padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Metric(label: "Schlaf letzte Nacht", value: byDay[today]?.sleepHours.map { Format.decimal($0) } ?? "–", unit: "h",
                       color: (byDay[today]?.sleepHours ?? 8) < 6 ? Theme.warn : Theme.text)
                Metric(label: "HRV", value: health.last?.hrvMs.map { "\(Int($0))" } ?? "–", unit: "ms")
                Metric(label: "Lärm gestern > 80 dB", value: byDay[yesterday]?.loudMinutes.map { "\(Int($0))" } ?? "–", unit: "min",
                       color: (byDay[yesterday]?.loudMinutes ?? 0) > 30 ? Theme.warn : Theme.text)
                Metric(label: "Hörschutz-Dosis heute", value: "\(Int(engine.doseToday * 100))", unit: "%",
                       color: engine.doseToday >= 0.5 ? Theme.warn : Theme.text)
            }
        }
    }

    // MARK: Measurements

    @ViewBuilder
    private func measurements(_ steps: [LabStep]) -> some View {
        let doneN = steps.filter(\.done).count
        let next = steps.firstIndex { !$0.done }
        HStack(alignment: .firstTextBaseline) {
            Eyebrow("Messungen")
            Spacer()
            Text("\(doneN) von \(steps.count)").font(.caption.weight(.semibold)).foregroundStyle(Theme.text3)
        }
        .padding(.top, 16)
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                Button { model.push(s.route) } label: { StepRow(index: i + 1, step: s, isNext: i == next) }
                    .buttonStyle(.plain)
                if i < steps.count - 1 { Divider().padding(.leading, 56) }
            }
            Divider().padding(.leading, 56)
            DeviceLine(engine: engine)
        }
        .card(padding: 6)
        if doneN == steps.count {
            Text("Wiederhole Spektrum und RI-Labor alle 4 Wochen, um Veränderungen zu sehen.").font(.caption).foregroundStyle(Theme.text3)
        }
    }
}

private struct DeviceLine: View {
    var engine: AudioEngine
    var body: some View {
        let kind = engine.deviceKind
        let p = DeviceProfile.profile(for: kind)
        HStack(spacing: 12) {
            Image(systemName: kind == .speaker ? "speaker.slash" : "headphones")
                .foregroundStyle(kind == .speaker ? Theme.warn : Theme.text2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.route.name.isEmpty ? kind.label : engine.route.name).font(.subheadline.weight(.semibold))
                Text(kind == .speaker ? "Lautsprecher: Messungen gesperrt" : p.calibrated ? "Kalibrierprofil \(kind.label) · Pegel geschätzt" : "Unkalibriert · Werte nur mit diesem Gerät vergleichbar")
                    .font(.caption).foregroundStyle(kind == .speaker ? Theme.warn : Theme.text2)
            }
            Spacer()
        }
        .padding(10)
    }
}
