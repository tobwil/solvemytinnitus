import Charts
import SwiftData
import SwiftUI
import TinnitusCore

struct ProgressScreen: View {
    var initialTab: AppRoute.ProgressTab
    @State private var tab: AppRoute.ProgressTab = .overview

    var body: some View {
        Screen {
            ScreenHeader(eyebrow: "Verlauf", title: "Was sich verändert", lead: nil)
            Picker("Ansicht", selection: $tab) {
                Text("Übersicht").tag(AppRoute.ProgressTab.overview)
                Text("Tag").tag(AppRoute.ProgressTab.journal)
                Text("Woche").tag(AppRoute.ProgressTab.weekly)
            }
            .pickerStyle(.segmented)
            switch tab {
            case .overview: OverviewSection()
            case .journal: JournalSection { tab = .overview }
            case .weekly: WeeklySection()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tab = initialTab }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ReportButton() }
        }
    }
}

// MARK: - Overview

private struct OverviewSection: View {
    @Query(sort: \CheckIn.ts) private var checkins: [CheckIn]
    @Query(sort: \JournalEntry.day) private var journal: [JournalEntry]
    @Query(sort: \TherapySession.date) private var sessions: [TherapySession]
    @Query(sort: \TinnitusMatch.date) private var matches: [TinnitusMatch]
    @Query(sort: \HealthSnapshot.day) private var health: [HealthSnapshot]
    @Query(sort: \BodySession.date) private var bodySessions: [BodySession]
    @Query(sort: \SomaticTest.date) private var somatic: [SomaticTest]

    var body: some View {
        let ratings = checkins.map { Insights.Rating(ts: $0.ts, loudness: $0.loudness, distress: $0.distress) }
        let jv = journal.map { Insights.JournalValues(day: $0.day, loudness: $0.loudness, distress: $0.distress, sleep: $0.sleep, stress: $0.stress, noise: $0.noiseExposure, caffeine: $0.caffeine, alcohol: $0.alcohol) }
        let days = Insights.daily(days: 30, checkins: ratings, journal: jv)
        let last7 = days.suffix(7).compactMap(\.loudness)
        let prev7 = days.dropLast(7).suffix(7).compactMap(\.loudness)
        let weekMin = Int(sessions.filter { $0.date > Day.daysAgo(7) }.reduce(0) { $0 + $1.durationS } / 60)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Metric(label: "Ø 7 Tage", value: last7.isEmpty ? "–" : Format.decimal(Stats.mean(last7)), color: Theme.tin)
                Metric(label: "Vorwoche", value: prev7.isEmpty ? "–" : Format.decimal(Stats.mean(prev7)))
                Metric(label: "Klang", value: "\(weekMin)", unit: "min")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Lautheit und Belastung, 30 Tage").font(.titleM)
                if days.contains(where: { $0.loudness != nil }) {
                    SeriesChart(series: [
                        .init(name: "Lautheit", color: Theme.tin, points: days.compactMap { d in d.loudness.map { (d.date, $0) } }, area: true),
                        .init(name: "Belastung", color: Theme.distress, points: days.compactMap { d in d.distress.map { (d.date, $0) } }),
                    ])
                } else {
                    Text("Noch keine Daten. Mach Check-ins über den Tag und einen Tagesrückblick am Abend.").font(.subheadline).foregroundStyle(Theme.text2)
                }
            }
            .card()
            mml
            whatWorks(days: days)
            timeOfDay(ratings)
            triggers(jv: jv, days: days)
            bodyCorrelation(days: days)
            CheckInHistory()
        }
    }

    @ViewBuilder
    private var mml: some View {
        let pts = matches.compactMap { m in m.mmlDb.map { (m.date, $0) } }
        if pts.count >= 2 {
            let lo = (pts.map(\.1).min() ?? -60) - 5, hi = (pts.map(\.1).max() ?? -20) + 5
            VStack(alignment: .leading, spacing: 6) {
                Text("Maskierungsschwelle (MML)").font(.titleM)
                Text("Niedriger = Tinnitus lässt sich leichter verdecken. Wiederhole die Messung alle 2–4 Wochen, möglichst mit denselben Kopfhörern.").font(.caption).foregroundStyle(Theme.text2)
                SeriesChart(series: [.init(name: "MML", color: Theme.lab, points: pts)], yDomain: lo...hi, height: 160)
            }
            .card()
        }
    }

    @ViewBuilder
    private func whatWorks(days: [Insights.DailyValue]) -> some View {
        let effects = Insights.modeEffects(sessions.map { ($0.mode, $0.pre, $0.post) })
        SectionHeader("Was wirkt bei dir?")
        if effects.isEmpty {
            Callout("Sobald du Sitzungen mit Vorher-/Nachher-Bewertung machst, siehst du hier, welcher Klang bei dir kurzfristig wirkt.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Veränderung der Lautheit direkt nach der Sitzung (nachher − vorher). Grün = bei dir verlässlich wirksam (mindestens 5 Sitzungen, ganzer 95-%-Bereich unter 0).")
                    .font(.caption).foregroundStyle(Theme.text2)
                ForEach(effects) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(SoundContent.mode(e.mode).title).font(.subheadline.weight(.semibold))
                                Text(e.n >= 3 ? "\(e.n) Sitzungen · 95 %-Bereich \(Format.decimal(e.interval.lo)) bis \(Format.decimal(e.interval.hi))" : "\(e.n) \(e.n == 1 ? "Sitzung" : "Sitzungen") · noch zu wenig für eine Aussage")
                                    .font(.caption).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Chip(Format.signed(e.interval.mean), tone: e.reliable ? .good : e.interval.mean > 0.5 ? .warn : .neutral)
                        }
                        CIBar(interval: e.interval, reliable: e.reliable)
                    }
                }
            }
            .card()
        }
        let active = Set(sessions.filter { $0.durationS >= 600 }.map { Day.key($0.date) })
        let split = Insights.withVsWithout(daily: days, activeDays: active)
        if split.with.count >= 3 && split.without.count >= 3 {
            let diff = Stats.mean(split.with) - Stats.mean(split.without)
            VStack(alignment: .leading, spacing: 8) {
                Text("Tage mit vs. ohne Klangprogramm").font(.titleM)
                HStack(spacing: 10) {
                    Metric(label: "Mit (\(split.with.count) T.)", value: Format.decimal(Stats.mean(split.with)))
                    Metric(label: "Ohne (\(split.without.count) T.)", value: Format.decimal(Stats.mean(split.without)))
                }
                Text("Unterschied \(Format.signed(diff)) Punkte. Achtung: Das ist eine Beobachtung, kein Experiment. Vielleicht machst du an guten Tagen einfach mehr.")
                    .font(.caption).foregroundStyle(Theme.text2)
            }
            .card()
        }
    }

    @ViewBuilder
    private func timeOfDay(_ ratings: [Insights.Rating]) -> some View {
        if ratings.count >= 8 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tageszeit").font(.titleM)
                Text("Studien mit Alltagsmessungen zeigen: Tinnitus wirkt nachts und frühmorgens meist lauter. Wie ist es bei dir?").font(.caption).foregroundStyle(Theme.text2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Insights.timeOfDay(ratings)) { s in
                        Metric(label: s.label, value: s.mean.map { Format.decimal($0) } ?? "–", unit: s.n > 0 ? "n=\(s.n)" : nil)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func triggers(jv: [Insights.JournalValues], days: [Insights.DailyValue]) -> some View {
        let hd = health.map { Insights.HealthDay(day: $0.day, sleepHours: $0.sleepHours, hrvMs: $0.hrvMs, loudMinutes: $0.loudMinutes, headphoneDbA: $0.headphoneDbA, restingHR: $0.restingHR) }
        let list = Insights.triggers(journal: jv, daily: days, health: hd)
        if !list.isEmpty {
            SectionHeader("Auslöser")
            VStack(alignment: .leading, spacing: 10) {
                Text("Unterschied der Lautheit an Tagen mit gegenüber ohne Faktor, bzw. Korrelation. Auslöser sind sehr individuell; deshalb zählen hier nur deine Daten.")
                    .font(.caption).foregroundStyle(Theme.text2)
                ForEach(list) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(t.label).font(.subheadline.weight(.semibold))
                                if t.automatic { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(Theme.bad).accessibilityLabel("aus Health") }
                            }
                            Text(t.detail).font(.caption).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Chip(t.kind == .correlation ? "r = \(Format.decimal(t.value, digits: 2))" : Format.signed(t.value), tone: t.isWarning ? .warn : t.isGood ? .good : .neutral)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func bodyCorrelation(days: [Insights.DailyValue]) -> some View {
        let rom = (somatic.compactMap { s in s.rom.map { (Day.key(s.date), $0.total) } } + bodySessions.compactMap { s in s.rom.map { (Day.key(s.date), $0.total) } })
        if let t = Insights.mobilityVsLoudness(rom: rom.map { (day: $0.0, total: $0.1) }, daily: days) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Körper").font(.titleM)
                HStack {
                    Text("Wird der Tinnitus leiser, wenn der Nacken beweglicher wird?").font(.subheadline)
                    Spacer()
                    Chip("r = \(Format.decimal(t.value, digits: 2))", tone: t.isGood ? .good : .neutral)
                }
                Text(t.detail).font(.caption).foregroundStyle(Theme.text2)
            }
            .card()
        }
    }
}

/// Horizontal confidence interval around 0 on a −5…+5 scale.
private struct CIBar: View {
    var interval: Stats.Interval
    var reliable: Bool
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = { (v: Double) in CGFloat((min(5, max(-5, v)) + 5) / 10) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2).frame(height: 6)
                Rectangle().fill(Theme.text3).frame(width: 1, height: 14).position(x: x(0), y: 7)
                Capsule().fill((reliable ? Theme.good : Theme.lab).opacity(0.5))
                    .frame(width: max(4, x(interval.hi) - x(interval.lo)), height: 6)
                    .position(x: (x(interval.lo) + x(interval.hi)) / 2, y: 7)
                Circle().fill(reliable ? Theme.good : Theme.lab).frame(width: 10, height: 10).position(x: x(interval.mean), y: 7)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Journal

/// Editable copy of a daily review, shared by "today" and the edit sheet for older days.
struct JournalDraft: Equatable {
    var loudness = 5.0, distress = 5.0, sleep = 5.0, stress = 5.0
    var noise = false, caffeine = false, alcohol = false, redFlag = false
    var notes = ""

    init() {}
    init(_ e: JournalEntry) {
        loudness = e.loudness; distress = e.distress; sleep = e.sleep; stress = e.stress
        noise = e.noiseExposure; caffeine = e.caffeine; alcohol = e.alcohol; redFlag = e.redFlag; notes = e.notes
    }

    func apply(to e: JournalEntry, noiseValue: Bool) {
        e.loudness = loudness; e.distress = distress; e.sleep = sleep; e.stress = stress
        e.noiseExposure = noiseValue; e.caffeine = caffeine; e.alcohol = alcohol; e.redFlag = redFlag; e.notes = notes
    }
}

/// The form itself: four sliders, flags, notes.
private struct JournalFields: View {
    @Binding var d: JournalDraft
    var snap: HealthSnapshot?
    var auto: Bool

    var body: some View {
        VStack(spacing: 6) {
            LabeledSlider(label: "Lautheit im Schnitt", value: $d.loudness, range: 0...10, color: Theme.tin, scale: ("still", "extrem"))
            LabeledSlider(label: "Belastung", value: $d.distress, range: 0...10, color: Theme.distress, scale: ("gar nicht", "extrem"))
            LabeledSlider(label: "Schlaf letzte Nacht", value: $d.sleep, range: 0...10, color: Theme.accent, scale: ("sehr schlecht", "sehr gut"))
            if let h = snap?.sleepHours { Text("Health: \(Format.decimal(h)) h geschlafen").font(.caption).foregroundStyle(Theme.text3).frame(maxWidth: .infinity, alignment: .leading) }
            LabeledSlider(label: "Stress", value: $d.stress, range: 0...10, color: Theme.warn, scale: ("entspannt", "sehr gestresst"))
        }
        .card()
        VStack(spacing: 4) {
            if !auto || snap?.loudMinutes == nil {
                Toggle("Lärm ausgesetzt", isOn: $d.noise)
            } else {
                HStack {
                    Text("Lärm")
                    Spacer()
                    Text("automatisch aus Health: \(Int(snap?.loudMinutes ?? 0)) min > 80 dB").font(.caption).foregroundStyle(Theme.text2)
                }
                .frame(minHeight: 32)
            }
            Toggle("Koffein", isOn: $d.caffeine)
            Toggle("Alkohol", isOn: $d.alcohol)
            Toggle("Warnzeichen (plötzlich anders, einseitig neu, pulsierend, Hörverlust, Schwindel)", isOn: $d.redFlag)
                .tint(Theme.warn)
        }
        .tint(Theme.accent)
        .card()
        if d.redFlag { Callout(SafetyContent.redFlagCallout, tone: .warn) }
        TextField("Notizen: Besonderheiten, Auslöser, was gut war …", text: $d.notes, axis: .vertical)
            .lineLimit(3...8)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
    }
}

private struct JournalSection: View {
    var onSaved: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \JournalEntry.day, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \HealthSnapshot.day) private var health: [HealthSnapshot]
    @Query private var settingsList: [AppSettings]
    @State private var draft = JournalDraft()
    @State private var loaded = false
    @State private var editing: JournalEntry?
    @State private var confirmDeleteToday = false
    @State private var showAll = false

    var body: some View {
        let today = Day.key()
        let existing = entries.first { $0.day == today }
        let snap = health.last { $0.day == today }
        let auto = settingsList.first?.useHealthKit == true
        let past = entries.filter { $0.day != today }
        VStack(alignment: .leading, spacing: 14) {
            Text(existing != nil ? "Heutiger Eintrag, du kannst ihn bearbeiten." : "Einmal am Abend, eine Minute. Daraus werden später deine Auslöser-Analysen.")
                .foregroundStyle(Theme.text2)
            JournalFields(d: $draft, snap: snap, auto: auto)
            Button("Speichern") { save(existing) }.buttonStyle(.primary())
            if existing != nil {
                Button(role: .destructive) { confirmDeleteToday = true } label: {
                    Label("Heutigen Eintrag löschen", systemImage: "trash").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(Theme.bad)
            }
            if !past.isEmpty {
                HStack {
                    Text("Letzte Tage").font(.titleM)
                    Spacer()
                    Text("Tippen zum Ändern").font(.caption).foregroundStyle(Theme.text3)
                }
                .padding(.top, 12)
                let shown = Array(past.prefix(showAll ? 400 : 7))
                VStack(spacing: 0) {
                    ForEach(shown) { j in
                        Button { editing = j } label: { JournalRow(j: j) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editing = j } label: { Label("Ändern", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    DataActions.deleteEntry(ctx, j)
                                    model.showToast("Tagesrückblick gelöscht")
                                } label: { Label("Löschen", systemImage: "trash") }
                            }
                        if j.id != shown.last?.id { Divider() }
                    }
                    if past.count > 7 {
                        TextLinkButton(showAll ? "Weniger anzeigen" : "Alle \(past.count) anzeigen") { withAnimation { showAll.toggle() } }
                    }
                }
                .card(padding: 10)
            }
        }
        .tint(Theme.accent)
        .sheet(item: $editing) { JournalEditSheet(entry: $0) }
        .alert("Heutigen Tagesrückblick löschen?", isPresented: $confirmDeleteToday) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                if let existing { DataActions.deleteEntry(ctx, existing) }
                draft = JournalDraft()
                model.showToast("Tagesrückblick gelöscht")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing { draft = JournalDraft(e) }
        }
    }

    private func save(_ existing: JournalEntry?) {
        let snap = health.last { $0.day == Day.key() }
        let noiseValue = snap?.loudMinutes.map { $0 > 30 } ?? draft.noise
        if let e = existing {
            draft.apply(to: e, noiseValue: noiseValue)
        } else {
            let e = JournalEntry(day: Day.key())
            draft.apply(to: e, noiseValue: noiseValue)
            ctx.insert(e)
        }
        try? ctx.save()
        DataActions.refreshSnapshot(ctx)
        model.showToast("Tagesrückblick gespeichert")
        onSaved()
    }
}

private struct JournalRow: View {
    var j: JournalEntry
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Day.date(fromKey: j.day)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? j.day).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text([j.noiseExposure ? "Lärm" : nil, j.caffeine ? "Koffein" : nil, j.alcohol ? "Alkohol" : nil, j.redFlag ? "Warnzeichen" : nil].compactMap { $0 }.joined(separator: " · ").ifEmpty(String(j.notes.prefix(40))).ifEmpty("–"))
                    .font(.caption).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            Chip("\(Int(j.loudness))", tone: .tint(Theme.tin))
            Chip("\(Int(j.distress))", tone: .tint(Theme.distress))
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet den Tagesrückblick zum Ändern oder Löschen")
    }
}

/// Correct or delete the review of an earlier day.
private struct JournalEditSheet: View {
    var entry: JournalEntry
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: \HealthSnapshot.day) private var health: [HealthSnapshot]
    @State private var draft = JournalDraft()
    @State private var original = JournalDraft()
    @State private var confirmDelete = false

    var body: some View {
        let snap = health.last { $0.day == entry.day }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Tagesrückblick")
                        Text(Day.date(fromKey: entry.day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? entry.day).font(.titleL)
                    }
                    JournalFields(d: $draft, snap: snap, auto: false)
                    Button("Änderung speichern") {
                        draft.apply(to: entry, noiseValue: draft.noise)
                        try? ctx.save()
                        DataActions.refreshSnapshot(ctx)
                        model.showToast("Tagesrückblick geändert")
                        dismiss()
                    }
                    .buttonStyle(.primary())
                    .disabled(draft == original)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Eintrag löschen", systemImage: "trash").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .tint(Theme.bad)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .alert("Tagesrückblick löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    DataActions.deleteEntry(ctx, entry)
                    model.showToast("Tagesrückblick gelöscht")
                    dismiss()
                }
            } message: {
                Text("Der Tag verschwindet aus Verlauf und Auslöser-Analysen.")
            }
        }
        .presentationBackground(Theme.bgElevated)
        .onAppear {
            draft = JournalDraft(entry)
            original = draft
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Weekly

private struct WeeklySection: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \WeeklyCheck.date) private var checks: [WeeklyCheck]
    @State private var answers = Array(repeating: -1, count: WeeklyContent.questions.count)

    var body: some View {
        let last = checks.last
        let due = last.map { Date.now.timeIntervalSince($0.date) > 6 * 86400 } ?? true
        VStack(alignment: .leading, spacing: 14) {
            Text("Acht Fragen zur Belastung der letzten 7 Tage, 0–100 Punkte, niedriger ist besser. Kein klinisch validierter Fragebogen, aber gut für deinen eigenen Verlauf. Für eine offizielle Einstufung frag beim HNO nach dem Mini-TQ oder THI.")
                .font(.subheadline).foregroundStyle(Theme.text2)
            if checks.count > 1 {
                SeriesChart(series: [.init(name: "Score", color: Theme.distress, points: checks.map { ($0.date, Double($0.score)) }, area: true)], yDomain: 0...100, height: 170)
                    .card()
            }
            if let last {
                HStack {
                    Text("Letzter Check \(last.date.formatted(date: .abbreviated, time: .omitted))")
                    Spacer()
                    Chip("\(last.score) Punkte", tone: .tint(Theme.distress))
                }
                .card(padding: 12)
            }
            if Insights.persistentHighDistress(scores: checks.map(\.score)) {
                Callout("Deine Belastung ist seit mindestens zwei Wochen hoch. Das Kopf-Training ist Selbsthilfe, keine Psychotherapie. Sprich mit Ärztin oder Arzt über tinnitusspezifische Psychotherapie oder eine DiGA auf Rezept. Telefonseelsorge rund um die Uhr: \(SafetyContent.crisisNumbers.joined(separator: " · ")).", tone: .warn)
            }
            if !due {
                Callout("Der nächste Wochen-Check ist in ein paar Tagen fällig.", tone: .good)
            } else {
                ForEach(Array(WeeklyContent.questions.enumerated()), id: \.offset) { i, q in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(i + 1). \(q)").font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            ForEach(Array(WeeklyContent.scale.enumerated()), id: \.offset) { v, label in
                                Button {
                                    answers[i] = v
                                    Haptics.selection()
                                } label: {
                                    Text(label).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .foregroundStyle(answers[i] == v ? Theme.onAccent : Theme.text)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(answers[i] == v ? Theme.distress : Theme.surface2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(answers[i] == v ? .isSelected : [])
                            }
                        }
                    }
                    .card(padding: 12)
                }
                Button("Wochen-Check speichern") {
                    let score = WeeklyContent.score(answers)
                    ctx.insert(WeeklyCheck(answers: answers, score: score))
                    try? ctx.save()
                    model.showToast("Gespeichert: \(score) Punkte")
                    answers = Array(repeating: -1, count: WeeklyContent.questions.count)
                }
                .buttonStyle(.primary(Theme.distress))
                .disabled(answers.contains(-1))
            }
        }
    }
}
