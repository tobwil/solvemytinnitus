import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

struct SoundListView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \TinnitusMatch.date) private var matches: [TinnitusMatch]
    @Query private var ri: [RITrial]
    @State private var engine = AudioEngine.shared
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        Screen {
            if let m = matches.last {
                let best = RIAnalysis.best(ri.map { .init(stimulus: $0.stimulus, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) })
                ScreenHeader(eyebrow: "Klang", title: "Klangprogramme",
                             lead: "Zum Ausprobieren, zugeschnitten auf \(Format.hz(m.freq))\(best.map { " · bester RI-Klang: \(SoundContent.label($0.stimulus))" } ?? "") – ob sie bei dir wirken, zeigt der Verlauf.")
                Button { model.open(.mind) } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "brain.head.profile", color: Theme.mind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Am besten belegt: Kopf-Training").font(.titleM).foregroundStyle(Theme.text)
                            Text("Kognitive Verhaltenstherapie senkt die Belastung zuverlässiger als jeder Klang. Kombiniere beides.").font(.caption).foregroundStyle(Theme.text2)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
                    }
                    .card(glow: Theme.mind)
                }
                .buttonStyle(.plain)
                SectionHeader("Klänge")
                ForEach(SoundContent.modes) { info in
                    Button { model.push(.sound(info.mode)) } label: { ModeCard(info: info) }.buttonStyle(.plain)
                        .zoomSource("sound-\(info.mode.rawValue)", in: zoom)
                }
                SectionHeader("Hörschutz")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tagesdosis eigener Klänge").font(.subheadline)
                        Spacer()
                        Text("\(Int(engine.doseToday * 100)) %").font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(engine.doseToday >= DoseMeter.warnAt ? Theme.warn : Theme.good)
                    }
                    ProgressView(value: min(1, engine.doseToday)).tint(engine.doseToday >= DoseMeter.warnAt ? Theme.warn : Theme.good)
                    Text("Bezogen auf die WHO-Empfehlung (80 dB(A), 40 h pro Woche). Pegel sind gedeckelt: Klänge max. ca. 85 dB SPL, Messsignale max. 80 dB SPL. Werte sind Schätzungen.")
                        .font(.caption).foregroundStyle(Theme.text3)
                }
                .card()
                Callout("**Automatisch zum Schlafen:** In der Kurzbefehle-App › Automation › „Schlafen“-Fokus › Aktion „Klangprogramm starten“ (Tinnitus Lab) mit Schlafmodus. Dann startet die Klanganreicherung beim Zubettgehen, ohne Bewertung, mit Sleep-Timer.")
            } else {
                ScreenHeader(eyebrow: "Klang", title: "Klangprogramme", lead: nil)
                Callout("Alle Klänge werden auf deine Tinnitus-Frequenz zugeschnitten. Dafür brauchen wir zuerst eine Messung.", tone: .warn)
                Button("Zur Messung") { model.open(.spectrum) }.buttonStyle(.primary(Theme.lab))
                SectionHeader("Ohne Messung")
                Button { startPlainEnrichment() } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "cloud.rain", color: Theme.sound)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Regen, 30 Minuten").font(.titleM).foregroundStyle(Theme.text)
                            Text("Allgemeine Klanganreicherung, auch über den Lautsprecher").font(.caption).foregroundStyle(Theme.text2)
                        }
                        Spacer()
                        Image(systemName: "play.fill").foregroundStyle(Theme.sound)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("")
    }

    private func startPlainEnrichment() {
        let c = SessionController.Config(mode: .enrichment, freq: 6000, ear: .both, levelDb: -36, source: .rain, stimulus: .nbnThird, widthOctaves: 1, targetMin: 30, mmlDb: nil, loudnessDb: -36)
        SessionController.shared.start(c)
    }
}

struct ModeCard: View {
    var info: ModeInfo
    @State private var session = SessionController.shared
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: info.symbol, color: Theme.sound)
            VStack(alignment: .leading, spacing: 6) {
                Text(info.title).font(.titleM).foregroundStyle(Theme.text)
                Text(info.tagline).font(.caption).foregroundStyle(Theme.text2)
                ViewThatFits {
                    HStack(spacing: 6) {
                        EvidenceBadge(level: info.level)
                        Chip(info.dose)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        EvidenceBadge(level: info.level)
                        Chip(info.dose)
                    }
                }
            }
            Spacer()
            Image(systemName: session.config?.mode == info.mode && session.state == .running ? "speaker.wave.2.fill" : "play.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.sound))
        }
        .card()
    }
}
