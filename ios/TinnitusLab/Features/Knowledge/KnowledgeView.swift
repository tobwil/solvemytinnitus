import SwiftUI
import TinnitusCore
import UIKit

struct KnowledgeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        Screen {
            ScreenHeader(eyebrow: "Wissen · Stand \(EvidenceContent.asOf)", title: "Was die Forschung sagt", lead: nil)
            VStack(alignment: .leading, spacing: 8) {
                Text("Das Wichtigste in drei Sätzen").font(.titleM)
                ForEach(EvidenceContent.summary, id: \.self) { s in
                    Text((try? AttributedString(markdown: s)) ?? AttributedString(s)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(glow: Theme.tin)
            SectionHeader("Was du in Deutschland konkret tun kannst")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(EvidenceContent.nextSteps) { s in
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: s.symbol, color: Theme.sound, size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title).font(.subheadline.weight(.semibold))
                            Text(s.text).font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                            if let link = s.link, let label = s.linkLabel {
                                Button(label) { openURL(link) }.font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                    Label("Einstellungen öffnen (Hörtest unter deinen AirPods)", systemImage: "gear")
                }
                .font(.caption.weight(.semibold))
            }
            .card()
            ForEach(EvidenceContent.groups) { g in
                SectionHeader(g.title)
                ForEach(g.items) { item in EvidenceCard(item: item) }
            }
            SectionHeader("Wie diese App die Forschung nutzt")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(EvidenceContent.howTheAppUsesResearch, id: \.0) { t, d in
                    Text("**\(t):** \(d)").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            Text("Quellen stehen als Kurzzitat unter jedem Abschnitt. Ein Tipp sucht die Studie in PubMed (S3-Leitlinie: AWMF-Register), so lässt sich jede Aussage nachprüfen.")
                .font(.caption).foregroundStyle(Theme.text3)
            Callout(SafetyContent.redFlagCallout, tone: .warn)
            Button { model.push(.settings) } label: { Label("Einstellungen & Daten", systemImage: "gearshape") }.buttonStyle(.ghost())
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EvidenceCard: View {
    var item: EvidenceItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.title).font(.titleM)
                Spacer()
                EvidenceBadge(level: item.level, label: item.level.label)
            }
            Text(item.verdict).font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
            Text(item.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let a = item.inApp {
                Label("In der App: \(a)", systemImage: "sparkles")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 2)
            Eyebrow("Quellen")
            SourceLinks(refs: item.refs)
        }
        .card()
    }
}

// MARK: - Sources

/// Short citations ("Fuller et al. 2020, Cochrane; Roberts et al. 2008, JARO") as tappable links,
/// so every claim can be checked: a PubMed search for author + year + tinnitus, the AWMF register for the S3 guideline.
struct SourceLinks: View {
    var refs: String
    /// Folded into one "Quellen (n)" line, for headers where the list would push content down.
    var compact = false
    @Environment(\.openURL) private var openURL
    @State private var open = false

    static func url(for ref: String) -> URL? {
        if ref.contains("Leitlinie") { return URL(string: "https://register.awmf.org/de/leitlinien/detail/017-064") }
        guard let author = ref.split(whereSeparator: { $0 == " " || $0 == "," }).first,
              let year = ref.range(of: #"(19|20)\d\d"#, options: .regularExpression).map({ ref[$0] }) else { return nil }
        var c = URLComponents(string: "https://pubmed.ncbi.nlm.nih.gov/")!
        c.queryItems = [URLQueryItem(name: "term", value: "\(author)[au] AND \(year)[dp] AND tinnitus")]
        return c.url
    }

    private var items: [String] {
        refs.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.book.closed").font(.caption2)
                        Text("Quellen (\(items.count))")
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
                    .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "aufgeklappt" : "zugeklappt")
                if open { list.transition(.opacity) }
            }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { r in
                if let u = Self.url(for: r) {
                    Button { openURL(u) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(r).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "arrow.up.right").font(.caption2.weight(.bold))
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.text2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(r.contains("Leitlinie") ? "Öffnet die Leitlinie bei der AWMF" : "Sucht die Studie in PubMed")
                } else {
                    Text(r).font(.caption).foregroundStyle(Theme.text3)
                }
            }
        }
    }
}
