import Charts
import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// "Fluss": the day as one continuous story instead of a stack of tiles.
/// A sentence about today → the day's loudness wave (amber) with what you did beneath it (teal) →
/// a check-in right in place → a timeline from this morning through "jetzt" to what is still open.
struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \CheckIn.ts) private var checkins: [CheckIn]
    @Query(sort: \TherapySession.date) private var sessions: [TherapySession]
    @Query(sort: \MindExercise.date) private var mind: [MindExercise]
    @Query(sort: \BodySession.date) private var body_: [BodySession]
    @Query(sort: \JournalEntry.day) private var journal: [JournalEntry]
    @Query(sort: \WeeklyCheck.date) private var weekly: [WeeklyCheck]
    @Query private var settingsList: [AppSettings]
    @AppStorage(SharedStore.focusSleepKey, store: SharedStore.defaults) private var sleepFocus = false
    @State private var showAllAtNight = false
    @State private var editing: FlowEvent?

    private var settings: AppSettings? { settingsList.first }
    private var cal: Calendar { .current }

    var body: some View {
        let state = DataActions.programState(ctx)
        let tasks = Program.todayTasks(state)
        let todayCheckins = checkins.filter { cal.isDateInToday($0.ts) }
        let events = flowEvents()
        Screen {
            if sleepFocus && !showAllAtNight {
                NightView(showAll: { showAllAtNight = true })
            } else {
                headline(todayCheckins, day: Program.programDay(state), week: Program.programWeek(state))
                DayWave(today: todayCheckins.map { ($0.ts, $0.loudness) },
                        yesterday: checkins.filter { cal.isDateInYesterday($0.ts) }.map { ($0.ts, $0.loudness) },
                        activity: events.compactMap(\.span))
                    .padding(.top, 28)
                InlineCheckIn(last: checkins.last)
                alerts
                timeline(events: events, tasks: tasks)
                VStack(spacing: 6) {
                    Text(SafetyContent.disclaimer).font(.caption).foregroundStyle(Theme.text3)
                    Button("Was die Forschung sagt") { model.open(.learn) }.font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { EntrySheet(event: $0) }
        .refreshable {
            if settings?.useHealthKit == true { await HealthService.shared.sync(into: ctx, days: 14) }
        }
    }

    // MARK: Headline

    /// One sentence that interprets the day instead of a greeting and a progress ring.
    private func headline(_ today: [CheckIn], day: Int, week: Int) -> some View {
        let hour = cal.component(.hour, from: .now)
        let name = settings?.name ?? ""
        let recent = checkins.filter { !cal.isDateInToday($0.ts) && $0.ts > Day.daysAgo(8) }.map(\.loudness)
        let (title, lead): (String, String) = {
            guard !today.isEmpty else {
                let greet = hour < 11 ? "Guten Morgen" : hour < 18 ? "Hallo" : "Guten Abend"
                return (name.isEmpty ? "\(greet)." : "\(greet), \(name).", "Wie ist er gerade? Ein Tipp auf die Skala genügt – daraus entsteht deine Tageswelle.")
            }
            let mean = Stats.mean(today.map(\.loudness))
            guard recent.count >= 3 else { return ("Dein Tag nimmt Form an.", "Mit jedem Check-in wird sichtbar, wann er lauter und wann er leiser ist.") }
            let d = mean - Stats.mean(recent)
            if d <= -0.7 { return ("Leiser als sonst.", "Heute im Schnitt \(Format.decimal(mean)) – \(Format.decimal(-d)) Punkte unter deiner letzten Woche.") }
            if d >= 0.7 { return ("Ein lauterer Tag.", "Laute Tage gehören dazu und gehen vorbei. Sei heute nachsichtig mit dir.") }
            return ("Ein Tag wie meistens.", "Im Schnitt \(Format.decimal(mean)) von 10 – ähnlich wie deine letzte Woche.")
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Tag \(day) · Woche \(min(week, 8)) von 8")
            Text(title).font(.titleXL).foregroundStyle(Theme.text).contentTransition(.opacity)
            Text(lead).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Alerts

    @ViewBuilder
    private var alerts: some View {
        if let j = journal.last, j.redFlag, j.day >= Day.key(Day.daysAgo(3)) {
            Callout("Du hast ein Warnzeichen notiert. **Bitte lass das zeitnah HNO-ärztlich abklären** – bei plötzlichem Hörverlust oder Schwindel noch heute.", tone: .warn)
        }
        if Insights.persistentHighDistress(scores: weekly.map(\.score)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Die Belastung ist seit Wochen hoch").font(.titleM)
                Text("Das Kopf-Training ist Selbsthilfe, keine Psychotherapie. Sprich mit deiner Hausärztin oder deinem HNO über tinnitusspezifische Psychotherapie oder eine DiGA auf Rezept. Wenn es dir gerade sehr schlecht geht: Telefonseelsorge, kostenlos und rund um die Uhr.")
                    .font(.subheadline).foregroundStyle(Theme.text2)
                HStack {
                    ForEach(SafetyContent.crisisNumbers.prefix(2), id: \.self) { n in
                        Link(destination: URL(string: "tel:\(n.replacingOccurrences(of: " ", with: ""))")!) {
                            Label(n, systemImage: "phone").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.ghost(Theme.accent))
                    }
                }
            }
            .card(glow: Theme.warn)
        }
        if let msg = SessionController.shared.message {
            Callout(msg, tone: .warn)
        }
    }

    // MARK: Timeline

    private func flowEvents() -> [FlowEvent] {
        var out: [FlowEvent] = []
        for c in checkins where cal.isDateInToday(c.ts) {
            out.append(.checkIn(c))
        }
        for s in sessions where cal.isDateInToday(s.date) {
            let info = SoundContent.mode(s.mode)
            var detail = "\(max(1, Int((s.durationS / 60).rounded()))) min"
            if let pre = s.pre, let post = s.post { detail += " · danach \(post < pre ? "leiser" : post > pre ? "lauter" : "gleich")" }
            out.append(FlowEvent(id: s.uid, time: s.date, symbol: info.symbol, title: info.title, detail: detail, tint: Theme.accent,
                                 span: (s.date.addingTimeInterval(-s.durationS), s.date), route: .sound(s.mode), ref: .session(s)))
        }
        for m in mind where cal.isDateInToday(m.date) {
            let (title, symbol): (String, String) = {
                if m.kind.hasPrefix("lesson:"), let l = MindContent.lesson(String(m.kind.dropFirst(7))) { return ("Lektion \(l.n): \(l.title)", "book") }
                if let t = MindContent.tool(m.kind) { return (t.title, t.symbol) }
                return ("Kopf-Training", "brain.head.profile")
            }()
            out.append(FlowEvent(id: m.uid, time: m.date, symbol: symbol, title: title, detail: "\(max(1, Int((m.durationS / 60).rounded()))) min", tint: Theme.accent,
                                 span: (m.date.addingTimeInterval(-m.durationS), m.date), ref: .mind(m)))
        }
        for b in body_ where cal.isDateInToday(b.date) {
            let p = BodyContent.programs.first { $0.id == b.program }
            out.append(FlowEvent(id: b.uid, time: b.date, symbol: "figure.cooldown", title: p?.title ?? "Körper", detail: "\(b.completedExercises) Übungen",
                                 tint: Theme.accent, span: (b.date.addingTimeInterval(-b.durationS), b.date), route: .body(b.program), ref: .body(b)))
        }
        return out.sorted { $0.time < $1.time }
    }

    private func timeline(events: [FlowEvent], tasks: [DayTask]) -> some View {
        let pending = tasks.filter { !$0.done && $0.id != "checkin" }
        let done = tasks.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dein Tag").font(.titleL)
                Spacer()
                Text("\(done) von \(tasks.count) erledigt").font(.caption.weight(.semibold)).foregroundStyle(Theme.text3)
                    .contentTransition(.numericText())
            }
            .padding(.top, 18).padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)

            ForEach(events) { e in
                FlowRow(node: .past(e.tint), isFirst: e.id == events.first?.id) {
                    let row = HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(e.time.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(Theme.text3)
                            .frame(width: 44, alignment: .leading)
                        Label(e.title, systemImage: e.symbol).font(.subheadline).foregroundStyle(Theme.text).labelStyle(FlowLabelStyle(tint: e.tint))
                        Spacer(minLength: 0)
                        if let d = e.detail { Text(d).font(.caption).foregroundStyle(Theme.text2) }
                    }
                    Button { editing = e } label: { row.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Öffnet den Eintrag zum Ändern oder Löschen")
                        .contextMenu {
                            Button { editing = e } label: { Label(e.ref.map { if case .checkIn = $0 { "Ändern" } else { "Details" } } ?? "Details", systemImage: "pencil") }
                            if let ref = e.ref {
                                Button(role: .destructive) {
                                    DataActions.deleteEntry(ctx, ref.model)
                                    model.showToast("Eintrag gelöscht")
                                } label: { Label("Löschen", systemImage: "trash") }
                            }
                        }
                }
            }

            FlowRow(node: .now, isFirst: events.isEmpty, isLast: pending.isEmpty) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Jetzt").font(.caption.weight(.bold)).foregroundStyle(Theme.tin).textCase(.uppercase).tracking(0.8)
                    if let next = pending.first {
                        NextStep(task: next) { open(next.route) }
                    } else {
                        Label(tasks.isEmpty ? "Nichts geplant" : "Alles für heute geschafft", systemImage: "checkmark.seal")
                            .font(.headline).foregroundStyle(Theme.good)
                    }
                }
                .padding(.bottom, 6)
            }

            ForEach(pending.dropFirst()) { t in
                FlowRow(node: .upcoming, isLast: t.id == pending.last?.id) {
                    Button { open(t.route) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: t.symbol).font(.subheadline).foregroundStyle(Theme.text3).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2)
                                Text(t.sub).font(.caption).foregroundStyle(Theme.text3).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.text3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue("offen")
                }
            }
        }
    }

    private func open(_ r: AppRoute) {
        switch r {
        case .progress, .learn, .settings: model.push(r)
        default: model.open(r)
        }
    }
}

// MARK: - Flow parts

struct FlowEvent: Identifiable {
    var id: String
    var time: Date
    var symbol: String
    var title: String
    var detail: String?
    var tint: Color
    /// Start/end for activity bars beneath the wave.
    var span: (Date, Date)?
    var route: AppRoute?
    var ref: EntryRef?
}

private struct FlowLabelStyle: LabelStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint).font(.caption.weight(.semibold))
            configuration.title.lineLimit(1)
        }
    }
}

/// One row of the day line: a node on a continuous vertical line, content to the right.
private struct FlowRow<Content: View>: View {
    enum Node { case past(Color), now, upcoming }
    var node: Node
    var isFirst = false
    var isLast = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(isFirst ? .clear : Theme.stroke2).frame(width: 2, height: nodeY)
                    Rectangle().fill(isLast ? .clear : Theme.stroke2).frame(width: 2).frame(maxHeight: .infinity)
                }
                dot.offset(y: nodeY - dotSize / 2)
            }
            .frame(width: 20)
            content
                .padding(.vertical, isNow ? 10 : 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isNow: Bool { if case .now = node { true } else { false } }
    private var dotSize: CGFloat { isNow ? 18 : 10 }
    private var nodeY: CGFloat { isNow ? 20 : 17 }

    @ViewBuilder private var dot: some View {
        switch node {
        case .past(let c):
            Circle().fill(c).frame(width: 10, height: 10)
        case .now:
            NowPulse()
        case .upcoming:
            Circle().strokeBorder(Theme.text3, lineWidth: 1.5).frame(width: 10, height: 10).background(Circle().fill(Theme.bg))
        }
    }
}

/// The "jetzt" node breathes slowly – the only moving thing on the line.
private struct NowPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.tin.opacity(0.25)).frame(width: 18, height: 18).scaleEffect(on ? 1.5 : 1).opacity(on ? 0 : 1)
            Circle().strokeBorder(Theme.tin, lineWidth: 3).background(Circle().fill(Theme.bg)).frame(width: 18, height: 18)
        }
        .onAppear {
            guard !reduceMotion, !AppEnv.isUITest else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

/// The one suggested step, inline on the line instead of in its own tile.
private struct NextStep: View {
    var task: DayTask
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: task.symbol).font(.title3.weight(.semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title).font(.headline).foregroundStyle(Theme.text)
                    Text(task.sub).font(.caption).foregroundStyle(Theme.text2).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.headline).foregroundStyle(Theme.accent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.accent.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Als Nächstes: \(task.title)")
        .accessibilityHint(task.sub)
    }
}

// MARK: - Day wave

/// Today's loudness as a wave over the waking day (amber), yesterday as a faint dashed line,
/// what you did as teal bars on the floor and a "jetzt" marker.
struct DayWave: View {
    var today: [(Date, Double)]
    var yesterday: [(Date, Double)]
    var activity: [(Date, Date)]

    private var cal: Calendar { .current }
    private var dayStart: Date {
        let six = cal.date(bySettingHour: 6, minute: 0, second: 0, of: .now)!
        return min(six, today.map(\.0).min() ?? six)
    }
    private var dayEnd: Date { cal.date(bySettingHour: 23, minute: 30, second: 0, of: .now)! }

    var body: some View {
        let shifted = yesterday.map { ($0.0.addingTimeInterval(86400), $0.1) }.filter { $0.0 >= dayStart && $0.0 <= dayEnd }
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(Array(shifted.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Zeit", p.0), y: .value("Lautheit", p.1), series: .value("Tag", "gestern"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.text3)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
                ForEach(Array(today.enumerated()), id: \.offset) { i, p in
                    LineMark(x: .value("Zeit", p.0), y: .value("Lautheit", p.1), series: .value("Tag", "heute"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.tin)
                        .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Zeit", p.0), y: .value("Lautheit", p.1))
                        .foregroundStyle(Theme.tin)
                        .symbolSize(i == today.count - 1 ? 110 : 36)
                        .annotation(position: .top, spacing: 6) {
                            if i == today.count - 1 {
                                Text("\(Int(p.1))").font(.caption.weight(.bold)).foregroundStyle(Theme.tin)
                            }
                        }
                }
                ForEach(Array(activity.filter { $0.1 > dayStart }.enumerated()), id: \.offset) { _, a in
                    RectangleMark(xStart: .value("Start", max(a.0, dayStart)), xEnd: .value("Ende", max(a.1, a.0.addingTimeInterval(600))),
                                  yStart: .value("", 0), yEnd: .value("", 0.55))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                        .clipShape(Capsule())
                }
                RuleMark(x: .value("Jetzt", Date.now))
                    .foregroundStyle(Theme.tin.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("jetzt").font(.caption2.weight(.bold)).foregroundStyle(Theme.tin)
                    }
            }
            .chartXScale(domain: dayStart...dayEnd)
            .chartYScale(domain: 0...10)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [6, 12, 18].compactMap { cal.date(bySettingHour: $0, minute: 0, second: 0, of: .now) }) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 150)
            .overlay {
                if today.isEmpty && shifted.isEmpty {
                    Text("Deine Tageswelle entsteht mit jedem Check-in").font(.caption).foregroundStyle(Theme.text2)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.regularMaterial))
                }
            }
            HStack(spacing: 14) {
                legend(Capsule().fill(Theme.tin).frame(width: 14, height: 3), "Lautheit")
                if !shifted.isEmpty { legend(Capsule().fill(Theme.text3).frame(width: 14, height: 2), "gestern") }
                legend(Capsule().fill(Theme.accent.opacity(0.7)).frame(width: 14, height: 6), "geübt")
            }
            .font(.caption2).foregroundStyle(Theme.text3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tageswelle")
        .accessibilityValue(today.isEmpty ? "Heute noch kein Check-in" : "Heute \(today.count) Check-ins, zuletzt \(Int(today.last!.1)) von 10")
    }

    private func legend(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 5) { mark; Text(text) }
    }
}

// MARK: - Inline check-in

/// The check-in lives in the flow: loudness first, then distress unfolds, then one tap to save.
/// Right after a check-in it folds into a single line.
struct InlineCheckIn: View {
    var last: CheckIn?
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var loudness: Int?
    @State private var distress: Int?
    @State private var reopen = false
    @State private var editing: FlowEvent?

    private var recent: Bool { last.map { Date.now.timeIntervalSince($0.ts) < 45 * 60 } ?? false }

    var body: some View {
        Group {
            if recent && !reopen, let last {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    Text("Erfasst um \(last.ts.formatted(date: .omitted, time: .shortened)) · \(Int(last.loudness))/10")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button("Ändern") { editing = .checkIn(last) }
                        .font(.subheadline.weight(.semibold)).tint(Theme.text2)
                    Button("Neu") { withAnimation(.snappy) { reopen = true } }
                        .font(.subheadline.weight(.semibold)).tint(Theme.tin)
                        .padding(.leading, 8)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Wie laut ist er gerade?").font(.titleM)
                    LoudnessDial(value: $loudness, kind: .loudness, color: Theme.tin)
                    if loudness != nil {
                        Text("Und wie sehr belastet er dich?").font(.titleM)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        LoudnessDial(value: $distress, kind: .distress, color: Theme.distress)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let l = loudness, let d = distress {
                        Button("Eintragen") { save(l, d) }
                            .buttonStyle(.primary(Theme.tin))
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .card()
                .animation(.snappy(duration: 0.3), value: loudness != nil)
                .animation(.snappy(duration: 0.3), value: distress != nil)
            }
        }
        .animation(.snappy, value: recent && !reopen)
        .sheet(item: $editing) { EntrySheet(event: $0) }
    }

    private func save(_ l: Int, _ d: Int) {
        DataActions.addCheckIn(ctx, loudness: Double(l), distress: Double(d))
        model.showToast("Check-in gespeichert")
        withAnimation(.snappy) {
            loudness = nil
            distress = nil
            reopen = false
        }
    }
}

// MARK: - Helpers kept from the old Today screen

/// Mean loudness per time-of-day slot as a coloured strip.
struct TimeOfDayStrip: View {
    var checkins: [CheckIn]
    var body: some View {
        let slots = Insights.timeOfDay(checkins.map { .init(ts: $0.ts, loudness: $0.loudness, distress: $0.distress) })
        HStack(spacing: 4) {
            ForEach(slots) { s in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(s.mean.map { Theme.tin.opacity(0.15 + 0.85 * $0 / 10) } ?? Theme.surface2)
                        .frame(height: 10)
                    Text(s.label).font(.caption2).foregroundStyle(Theme.text3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(s.label): \(s.mean.map { Format.decimal($0) } ?? "keine Daten")")
            }
        }
    }
}

/// Shown while the "Schlafen" focus filter is active: only enrichment and breathing.
struct NightView: View {
    var showAll: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(eyebrow: "Schlafen-Fokus", title: "Gute Nacht", lead: "Nur das Nötigste: ein leiser Klang gegen die Stille und eine ruhige Atemübung.")
            Button { model.open(.play(.enrichment, minutes: 480)) } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "cloud.rain", color: Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nachtklang").font(.titleM).foregroundStyle(Theme.text)
                        Text("Bis zum Morgen, klingt sanft aus").font(.caption).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                }
                .card()
            }
            .buttonStyle(.plain)
            Button { model.open(.tool("breath")) } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "wind", color: Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ruhiger Atem").font(.titleM).foregroundStyle(Theme.text)
                        Text("3 Minuten, mit Vibration auch bei geschlossenen Augen").font(.caption).foregroundStyle(Theme.text2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
                }
                .card()
            }
            .buttonStyle(.plain)
            TextLinkButton("Alle Funktionen anzeigen", action: showAll)
        }
    }
}
