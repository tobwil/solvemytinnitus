import SwiftData
import SwiftUI
import TinnitusCore

/// "Üben": starts from how you feel instead of from a feature list. Pick what you need right now,
/// get one clear suggestion plus a few that fit with it. Sound, mind and body are one library underneath.
struct PracticeView: View {
    enum Need: String, CaseIterable, Identifiable {
        case plan, loud, sleep, tense, brooding
        var id: String { rawValue }
        var label: String {
            switch self {
            case .plan: "Mein Plan"
            case .loud: "Er ist laut"
            case .sleep: "Einschlafen"
            case .tense: "Verspannt"
            case .brooding: "Gedankenkarussell"
            }
        }
        var symbol: String {
            switch self {
            case .plan: "sun.horizon"
            case .loud: "speaker.wave.3"
            case .sleep: "moon.stars"
            case .tense: "figure.cooldown"
            case .brooding: "tornado"
            }
        }
    }

    struct Suggestion: Identifiable {
        var title: String
        var sub: String
        var symbol: String
        var route: AppRoute
        var id: String { title }
    }

    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query private var settingsList: [AppSettings]
    @Query(sort: \TinnitusMatch.date) private var matches: [TinnitusMatch]
    @State private var need: Need = Calendar.current.component(.hour, from: .now) >= 21 ? .sleep : .plan
    @Namespace private var chipNS

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        let (hero, more) = suggestions(for: need)
        Screen {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Üben")
                Text("Was brauchst du jetzt?").font(.titleXL)
            }
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ChipScroller(items: Need.allCases) { n in
                Button {
                    withAnimation(.snappy(duration: 0.3)) { need = n }
                } label: {
                    Label(n.label, systemImage: n.symbol)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(need == n ? Theme.onAccent : Theme.text)
                        .background {
                            if need == n {
                                Capsule().fill(Theme.accent).matchedGeometryEffect(id: "chip", in: chipNS)
                            } else {
                                Capsule().strokeBorder(Theme.stroke2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(need == n ? .isSelected : [])
            }
            .sensoryFeedback(.selection, trigger: need)

            if let hero {
                HeroSuggestion(s: hero) { go(hero.route) }
                    .id(need)
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
            }

            if !more.isEmpty {
                Eyebrow("Dazu passt").padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(more) { s in
                        Button { go(s.route) } label: { LibraryRow(symbol: s.symbol, title: s.title, sub: s.sub) }
                            .buttonStyle(.plain)
                        if s.id != more.last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .card(padding: 4)
                .id("more-\(need.rawValue)")
                .transition(.opacity)
            }

            Eyebrow("Alles zum Üben").padding(.top, 16)
            VStack(spacing: 0) {
                Button { model.push(.sound(nil)) } label: {
                    LibraryRow(symbol: "waveform", title: "Klang", sub: matches.isEmpty ? "Regen, Rauschen, Notched, Reset" : "Zugeschnitten auf \(Format.hz(matches.last!.freq))")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                Button { model.push(.mind) } label: {
                    LibraryRow(symbol: "brain.head.profile", title: "Kopf", sub: "\(settings?.lessonsDone.count ?? 0) von \(MindContent.lessons.count) Lektionen · \(MindContent.tools.count) Werkzeuge")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                Button { model.push(.body(nil)) } label: {
                    LibraryRow(symbol: "figure.cooldown", title: "Körper", sub: "Nacken und Kiefer lösen")
                }
                .buttonStyle(.plain)
            }
            .card(padding: 4)
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
    }

    private func go(_ r: AppRoute) {
        switch r {
        case .play: model.open(r)
        default: model.push(r)
        }
    }

    /// Body programmes go through the overview until the safety questions are answered.
    private func bodyRoute(_ p: BodyProgramID) -> AppRoute {
        settings?.contraindications == nil ? .body(nil) : .body(p)
    }

    private func tool(_ id: String) -> Suggestion {
        let t = MindContent.tool(id)!
        return Suggestion(title: t.title, sub: t.sub, symbol: t.symbol, route: .tool(id))
    }

    private func lesson(_ id: String) -> Suggestion {
        let l = MindContent.lesson(id)!
        return Suggestion(title: "Lektion \(l.n): \(l.title)", sub: "\(l.sub) · \(l.minutes) min", symbol: "book", route: .lesson(id))
    }

    private func suggestions(for need: Need) -> (Suggestion?, [Suggestion]) {
        switch need {
        case .plan:
            let tasks = Program.todayTasks(DataActions.programState(ctx)).filter { !$0.done && $0.id != "checkin" }
            let items = tasks.map { Suggestion(title: $0.title, sub: $0.sub, symbol: $0.symbol, route: $0.route) }
            if items.isEmpty {
                return (Suggestion(title: "Alles für heute geschafft", sub: "Wenn du magst: ein ruhiger Atem zum Abschluss.", symbol: "checkmark.seal", route: .tool("breath")), [])
            }
            return (items.first, Array(items.dropFirst().prefix(3)))
        case .loud:
            return (Suggestion(title: "Klang darüberlegen", sub: "Regen oder Rauschen, etwas leiser als dein Tinnitus. 30 Minuten.", symbol: "cloud.rain", route: .play(.enrichment, minutes: 30)),
                    [tool("breath"), tool("plan"), lesson("l8")])
        case .sleep:
            return (Suggestion(title: "Nachtklang", sub: "Ein leiser Klang gegen die Stille, klingt bis zum Morgen sanft aus.", symbol: "moon.stars", route: .play(.enrichment, minutes: 480)),
                    [tool("breath"), tool("pmr"), lesson("l7")])
        case .tense:
            return (Suggestion(title: "Kiefer lösen", sub: "8 sanfte Übungen, etwa 8 Minuten. Geführt, Schritt für Schritt.", symbol: "figure.cooldown", route: bodyRoute(.jaw)),
                    [Suggestion(title: "Nacken und Schultern", sub: "8 Übungen gegen Kopfvorhaltung", symbol: "figure.cooldown", route: bodyRoute(.neck)), tool("pmr"), tool("breath")])
        case .brooding:
            return (Suggestion(title: "Gedanken-Check", sub: "Einen belastenden Gedanken aufschreiben und prüfen. 5 Minuten.", symbol: "pencil.line", route: .tool("thoughts")),
                    [tool("attention"), tool("mindful"), lesson("l4")])
        }
    }
}

/// The one big suggestion: a calm ring, a clear title, one action.
private struct HeroSuggestion: View {
    var s: PracticeView.Suggestion
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().strokeBorder(Theme.accent.opacity(0.35 - Double(i) * 0.1), lineWidth: 1.5)
                            .frame(width: 112 + CGFloat(i) * 34, height: 112 + CGFloat(i) * 34)
                    }
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 112, height: 112)
                    Image(systemName: s.symbol).font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                .phaseAnimator([1.0, 1.05], trigger: reduceMotion || AppEnv.isUITest ? 0 : 1) { v, p in v.scaleEffect(p) } animation: { _ in .easeInOut(duration: 3) }
                .frame(height: 190)
                VStack(spacing: 6) {
                    Text(s.title).font(.titleL).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                    Text(s.sub).font(.subheadline).foregroundStyle(Theme.text2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Image(systemName: isPlay ? "play.fill" : "arrow.right")
                    Text(isPlay ? "Starten" : "Öffnen")
                }
                .font(.headline)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(Capsule().fill(Theme.accent))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(s.title)
        .accessibilityHint(s.sub)
    }

    private var isPlay: Bool { if case .play = s.route { true } else { false } }
}

/// Plain list row used across the practice and profile rooms.
struct LibraryRow: View {
    var symbol: String
    var title: String
    var sub: String?
    var tint: Color = Theme.accent
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(tint).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                if let sub { Text(sub).font(.caption).foregroundStyle(Theme.text2).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
