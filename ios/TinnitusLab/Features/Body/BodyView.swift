import Charts
import SwiftData
import SwiftUI
import TinnitusCore

/// Körper: neck/shoulder and jaw programmes. For everyone as relaxation, a daily task for users with a
/// positive somatic check (06-koerper-dehnung).
struct BodyView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \BodySession.date) private var sessions: [BodySession]
    @Query(sort: \SomaticTest.date) private var somatic: [SomaticTest]
    @Query private var settingsList: [AppSettings]
    @State private var showContra = false
    @State private var tracker = HeadTracker.shared
    @Environment(\.zoomNamespace) private var zoom

    private var contra: Set<Contraindication> {
        Set((settingsList.first?.contraindications ?? []).compactMap(Contraindication.init(rawValue:)))
    }

    var body: some View {
        let som = somatic.last
        Screen {
            ScreenHeader(eyebrow: "Körper", title: "Nacken und Kiefer lösen", lead: BodyContent.intro)
            SourceLinks(refs: BodyContent.refs, compact: true)
            HStack(spacing: 8) {
                if let som {
                    Chip(som.somatic ? "Somatisch modulierbar · tägliche Aufgabe" : "Als Entspannung", tone: som.somatic ? .tint(Theme.tin) : .neutral, symbol: som.somatic ? "star.fill" : nil)
                } else {
                    Button { model.open(.somatic) } label: { Chip("Somatik-Check noch offen", tone: .tint(Theme.lab), symbol: "flask") }
                }
                if !contra.isEmpty { Chip("nur sanfte Übungen", tone: .warn) }
            }
            if settingsList.first?.contraindications == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vor dem ersten Start").font(.titleM)
                    Text("Ein paar Fragen zu Beschwerden, damit nur passende Übungen vorkommen.").font(.subheadline).foregroundStyle(Theme.text2)
                    Button("Fragen beantworten") { showContra = true }.buttonStyle(.primary(Theme.body, large: false))
                }
                .card(glow: Theme.body)
            }
            ForEach(BodyContent.programs) { p in
                Button {
                    if settingsList.first?.contraindications == nil { showContra = true } else { model.push(.body(p.id)) }
                } label: { ProgramCard(program: p, contra: contra, lastDone: sessions.last { $0.program == p.id }?.date) }
                    .buttonStyle(.plain)
                    .zoomSource("body-\(p.id.rawValue)", in: zoom)
            }
            if som?.somatic == true {
                Callout("Dein Tinnitus reagiert auf Kiefer oder Nacken. **Die App ersetzt keine Physiotherapie:** Lass eine physiotherapeutische Untersuchung (Halswirbelsäule) oder eine zahnärztliche CMD-Abklärung machen; in Deutschland auf Rezept möglich.")
            }
            mobility
            jawTension
            headTrackingInfo
            if !contra.isEmpty || settingsList.first?.contraindications != nil {
                TextLinkButton("Beschwerden-Fragen ändern", symbol: "list.bullet.clipboard") { showContra = true }
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showContra) { ContraindicationSheet() }
    }

    @ViewBuilder
    private var mobility: some View {
        let points: [(Date, Double)] = (somatic.compactMap { s in s.rom.map { (s.date, $0.total) } } + sessions.compactMap { s in s.rom.map { (s.date, $0.total) } })
            .sorted { $0.0 < $1.0 }
        if !points.isEmpty {
            SectionHeader("Beweglichkeit")
            VStack(alignment: .leading, spacing: 6) {
                Text("Summe aller Bewegungsrichtungen in Grad (AirPods-Messung)").font(.caption).foregroundStyle(Theme.text2)
                Chart(Array(points.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Datum", p.0), y: .value("Grad", p.1)).foregroundStyle(Theme.body)
                    PointMark(x: .value("Datum", p.0), y: .value("Grad", p.1)).foregroundStyle(Theme.body)
                }
                .frame(height: 150)
                Text("Im Verlauf siehst du, ob dein Tinnitus leiser wird, wenn der Nacken beweglicher wird.").font(.caption).foregroundStyle(Theme.text3)
            }
            .card()
        }
    }

    @ViewBuilder
    private var jawTension: some View {
        let pts = sessions.compactMap { s in s.jawTension.map { (s.date, $0) } }
        if pts.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Kieferanspannung nach dem Programm").font(.titleM)
                Text("Selbsteinschätzung 0–10, niedriger ist lockerer").font(.caption).foregroundStyle(Theme.text2)
                SeriesChart(series: [.init(name: "Kiefer", color: Theme.body, points: pts, area: true)], yDomain: 0...10, height: 140)
            }
            .card()
        }
    }

    private var headTrackingInfo: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "airpodspro", color: Theme.body, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(tracker.isAvailable ? "Mit AirPods: geführte Dehnung" : "Kopftracking nicht verfügbar").font(.subheadline.weight(.semibold))
                Text("AirPods Pro, Max, 3. und 4. Generation messen die Kopfbewegung. Die Figur zeigt die Zielposition, ein Ring füllt sich beim Halten. Ohne AirPods läuft alles mit Timer.")
                    .font(.caption).foregroundStyle(Theme.text2)
            }
        }
        .card(padding: 12)
    }
}

private struct ProgramCard: View {
    var program: BodyProgram
    var contra: Set<Contraindication>
    var lastDone: Date?

    var body: some View {
        let all = program.exercises.count
        let allowed = program.exercises(excluding: contra).count
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(program.title).font(.titleL).foregroundStyle(Theme.text)
                Text(program.id == .neck ? "Trapezius · Levator · SCM · tiefe Nackenbeuger" : "Kaumuskel · Schläfenmuskel · Mimik")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .bottomLeading)
            .padding(16)
            .background(ProgramArt(program: program.id))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.radius, topTrailingRadius: Theme.radius, style: .continuous))
            HStack(spacing: 6) {
                Chip("\(program.minutes(excluding: contra)) min", symbol: "clock")
                Chip("\(allowed) Übungen", symbol: "list.bullet")
                if allowed < all { Chip("sanft", tone: .warn, symbol: "leaf") }
                Spacer()
                if let lastDone { Text("zuletzt \(lastDone.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(Theme.text3) }
                Image(systemName: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.body))
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Startet das Programm")
    }
}

/// Calm, slowly drifting gradient in the app palette (body rose with mind violet and sound teal or
/// the tinnitus amber) – no figure, no symbol.
struct ProgramArt: View {
    var program: BodyProgramID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] {
        let accent = program == .neck ? Theme.sound : Theme.tin
        return [
            Theme.body.opacity(0.32), Theme.mind.opacity(0.22), accent.opacity(0.20),
            Theme.body.opacity(0.18), Theme.mind.opacity(0.14), accent.opacity(0.14),
            Theme.mind.opacity(0.10), Theme.body.opacity(0.08), accent.opacity(0.10),
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || AppEnv.isUITest)) { tl in
            let t = reduceMotion || AppEnv.isUITest ? 0 : tl.date.timeIntervalSinceReferenceDate
            let w = Float(sin(t * 0.3)) * 0.12, v = Float(cos(t * 0.23)) * 0.12
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + w, 0], [1, 0],
                [0, 0.5 + v], [0.5 - w, 0.5 + v], [1, 0.5 - v],
                [0, 1], [0.5 + v, 1], [1, 1],
            ], colors: colors)
        }
        .background(Theme.surface)
        .accessibilityHidden(true)
    }
}

struct ContraindicationSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Contraindication> = []

    var body: some View {
        NavigationStack {
            Screen {
                ScreenHeader(eyebrow: "Körper", title: "Hast du gerade eine dieser Beschwerden?", lead: "Dann zeigt die App nur sanfte Übungen. Bei Schmerzen während einer Übung sofort aufhören.")
                ForEach(Contraindication.allCases) { c in
                    Button {
                        if selected.contains(c) { selected.remove(c) } else { selected.insert(c) }
                        Haptics.selection()
                    } label: {
                        HStack {
                            Text(c.label).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: selected.contains(c) ? "checkmark.square.fill" : "square").foregroundStyle(selected.contains(c) ? Theme.body : Theme.text3).font(.title3)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    }
                    .buttonStyle(.plain)
                }
                Button(selected.isEmpty ? "Nichts davon" : "Weiter mit sanften Übungen") {
                    ctx.settings().contraindications = selected.map(\.rawValue).sorted()
                    try? ctx.save()
                    dismiss()
                }
                .buttonStyle(.primary(Theme.body))
                if !selected.isEmpty {
                    Callout("Lass akute Beschwerden ärztlich oder physiotherapeutisch abklären, bevor du die Dehnungen machst.", tone: .warn)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear {
                selected = Set((ctx.settings().contraindications ?? []).compactMap(Contraindication.init(rawValue:)))
            }
        }
    }
}
