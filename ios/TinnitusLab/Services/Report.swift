import Charts
import SwiftData
import SwiftUI
import TinnitusCore

/// PDF report for the ENT appointment: hearing check, spectrum, MML, last 8 weeks (04-module "Verlauf").
struct ReportButton: View {
    @Environment(\.modelContext) private var ctx
    @State private var url: URL?
    @State private var busy = false

    var body: some View {
        if let url {
            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("PDF-Bericht teilen")
        } else {
            Button {
                busy = true
                url = ReportRenderer.render(ctx)
                busy = false
            } label: {
                if busy { ProgressView() } else { Label("PDF", systemImage: "doc.richtext") }
            }
            .accessibilityLabel("PDF-Bericht für den HNO-Termin erstellen")
        }
    }
}

@MainActor
enum ReportRenderer {
    static let page = CGSize(width: 595, height: 842)

    static func render(_ ctx: ModelContext) -> URL? {
        let data = ReportData(ctx)
        let pages: [AnyView] = [AnyView(ReportPage1(d: data)), AnyView(ReportPage2(d: data))]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tinnitus-Lab-Bericht-\(Day.key()).pdf")
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for p in pages {
            let r = ImageRenderer(content: p.frame(width: page.width, height: page.height).environment(\.colorScheme, .light))
            r.proposedSize = ProposedViewSize(page)
            pdf.beginPDFPage(nil)
            r.render { _, draw in draw(pdf) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return url
    }
}

@MainActor
struct ReportData {
    var name: String
    var hearing: HearingTest?
    var spectrum: TinnitusSpectrum?
    var match: TinnitusMatch?
    var mml: [(Date, Double)]
    var daily: [Insights.DailyValue]
    var weekly: [WeeklyCheck]
    var effects: [Insights.ModeEffect]
    var ri: [RISummary]
    var somatic: SomaticTest?
    var triggers: [Insights.Trigger]

    init(_ ctx: ModelContext) {
        let s = ctx.settings()
        name = s.name
        hearing = ctx.latestHearing()
        spectrum = ctx.latestSpectrum()
        match = ctx.latestMatch()
        mml = ctx.all(TinnitusMatch.self, sortBy: [SortDescriptor(\.date)]).compactMap { m in m.mmlDb.map { (m.date, $0) } }
        let ratings = ctx.all(CheckIn.self).map { Insights.Rating(ts: $0.ts, loudness: $0.loudness, distress: $0.distress) }
        let jv = ctx.all(JournalEntry.self).map { Insights.JournalValues(day: $0.day, loudness: $0.loudness, distress: $0.distress, sleep: $0.sleep, stress: $0.stress, noise: $0.noiseExposure, caffeine: $0.caffeine, alcohol: $0.alcohol) }
        daily = Insights.daily(days: 56, checkins: ratings, journal: jv)
        weekly = ctx.all(WeeklyCheck.self, sortBy: [SortDescriptor(\.date)])
        effects = Insights.modeEffects(ctx.all(TherapySession.self).map { ($0.mode, $0.pre, $0.post) })
        ri = RIAnalysis.summarize(ctx.all(RITrial.self).map { .init(stimulus: $0.stimulus, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) })
        somatic = ctx.latestSomatic()
        let hd = ctx.all(HealthSnapshot.self).map { Insights.HealthDay(day: $0.day, sleepHours: $0.sleepHours, hrvMs: $0.hrvMs, loudMinutes: $0.loudMinutes, headphoneDbA: $0.headphoneDbA, restingHR: $0.restingHR) }
        triggers = Insights.triggers(journal: jv, daily: daily, health: hd)
    }
}

private struct ReportHeader: View {
    var title: String
    var page: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tinnitus Lab · \(title)").font(.system(size: 18, weight: .bold))
                Text("Erstellt am \(Date.now.formatted(date: .long, time: .omitted)) · Selbstmessungen, keine klinische Diagnostik").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Seite \(page)/2").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

private struct ReportBox<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold))
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.35)))
    }
}

private struct ReportPage1: View {
    var d: ReportData
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportHeader(title: d.name.isEmpty ? "Bericht für den HNO-Termin" : "Bericht · \(d.name)", page: 1)
            HStack(alignment: .top, spacing: 12) {
                ReportBox(title: "Tinnitus-Profil") {
                    if let m = d.match {
                        Text("Frequenz (Median aus \(m.trials.count) Matches): \(Format.hz(m.freq))").font(.system(size: 10))
                        Text("Streuung: \(Format.decimal(m.spreadOctaves * 12)) Halbtöne · Ohr: \(m.ear.label) · Klang: \(m.timbre == .tone ? "tonal" : "Rauschen")").font(.system(size: 10))
                        Text("Lautheit-Match: \(Int(m.loudnessDb)) dB · MML: \(m.mmlDb.map { "\(Int($0)) dB" } ?? "nicht maskierbar") (relativ, \(m.device.kind.label))").font(.system(size: 10))
                    } else {
                        Text("Noch nicht gemessen").font(.system(size: 10))
                    }
                    if let s = d.somatic {
                        Text("Somatisch modulierbar: \(s.somatic ? "ja" : "nein")").font(.system(size: 10))
                    }
                }
                ReportBox(title: "Bester Klang im RI-Labor (verblindet)") {
                    ForEach(d.ri.prefix(3)) { r in
                        Text("\(SoundContent.label(r.stimulus)): −\(Format.decimal(r.depth)) Punkte, \(Int(r.duration)) s (n=\(r.n))").font(.system(size: 10))
                    }
                    if d.ri.isEmpty { Text("Keine Durchgänge").font(.system(size: 10)) }
                }
            }
            if let h = d.hearing {
                ReportBox(title: "Hörcheck (\(h.source == .app ? "eigene Messung, relativ" : h.source == .healthKit ? "Apple Hörtest, dB HL" : "Apple Hörtest + eigene Messung > 8 kHz"))") {
                    HearingChart(left: h.left, right: h.right, tinnitusHz: d.match?.freq, unit: h.source == .app ? "dB rel." : "dB HL", height: 200)
                }
            }
            if let s = d.spectrum {
                ReportBox(title: "Tinnitus-Spektrum (Ähnlichkeit 0–10, Noreña-Methode)") {
                    SpectrumBars(points: s.points, peak: s.peak, height: 130)
                }
            }
            Spacer()
            Text(SafetyContent.disclaimer + " Pegel sind geschätzt bzw. relativ zum verwendeten Kopfhörer.").font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}

private struct ReportPage2: View {
    var d: ReportData
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportHeader(title: "Verlauf der letzten 8 Wochen", page: 2)
            ReportBox(title: "Lautheit (amber) und Belastung (violett), Tagesmittel 0–10") {
                SeriesChart(series: [
                    .init(name: "Lautheit", color: .orange, points: d.daily.compactMap { x in x.loudness.map { (x.date, $0) } }),
                    .init(name: "Belastung", color: .purple, points: d.daily.compactMap { x in x.distress.map { (x.date, $0) } }),
                ], height: 170)
            }
            HStack(alignment: .top, spacing: 12) {
                if d.mml.count >= 2 {
                    ReportBox(title: "Maskierungsschwelle (MML)") {
                        SeriesChart(series: [.init(name: "MML", color: .blue, points: d.mml)], yDomain: ((d.mml.map(\.1).min() ?? -60) - 5)...((d.mml.map(\.1).max() ?? -20) + 5), height: 120)
                    }
                }
                if d.weekly.count >= 1 {
                    ReportBox(title: "Wochen-Check (0–100, nicht validiert)") {
                        SeriesChart(series: [.init(name: "Score", color: .purple, points: d.weekly.map { ($0.date, Double($0.score)) })], yDomain: 0...100, height: 120)
                    }
                }
            }
            ReportBox(title: "Kurzfristige Wirkung je Klangprogramm (nachher − vorher, 95-%-Bereich)") {
                ForEach(d.effects) { e in
                    Text("\(SoundContent.mode(e.mode).title): \(Format.signed(e.interval.mean)) (\(Format.decimal(e.interval.lo)) bis \(Format.decimal(e.interval.hi)), n=\(e.n))\(e.reliable ? " – verlässlich" : "")").font(.system(size: 10))
                }
                if d.effects.isEmpty { Text("Keine bewerteten Sitzungen").font(.system(size: 10)) }
            }
            if !d.triggers.isEmpty {
                ReportBox(title: "Mögliche Auslöser (eigene Daten)") {
                    ForEach(d.triggers) { t in
                        Text("\(t.label): \(t.kind == .correlation ? "r = \(Format.decimal(t.value, digits: 2))" : Format.signed(t.value) + " Punkte") (\(t.detail))").font(.system(size: 10))
                    }
                }
            }
            Spacer()
            Text("Erstellt mit Tinnitus Lab. Die App dient der Selbstbeobachtung und stellt keine Diagnose.").font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}
