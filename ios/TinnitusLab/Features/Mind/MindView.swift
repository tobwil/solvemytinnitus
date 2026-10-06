import SwiftData
import SwiftUI
import TinnitusCore

struct MindView: View {
    @Environment(AppModel.self) private var model
    @Query private var settingsList: [AppSettings]
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        let done = settingsList.first?.lessonsDone ?? []
        let next = MindContent.lessons.first { !done.contains($0.id) }
        Screen {
            HStack(alignment: .center, spacing: 16) {
                ScreenHeader(eyebrow: "Kopf", title: "Kopf-Training", lead: nil)
                Spacer()
                RingView(progress: Double(done.count) / Double(MindContent.lessons.count), color: Theme.mind, lineWidth: 9) {
                    Text("\(done.count)/\(MindContent.lessons.count)").font(.display(17)).monospacedDigit()
                }
                .frame(width: 70, height: 70)
            }
            Text("Kognitive Verhaltenstherapie ist das am besten belegte Verfahren gegen Tinnitus-Belastung (Cochrane 2020, UNITI-Studie 2025). Dieses Programm folgt ihren Bausteinen. Es ist Selbsthilfe, keine Psychotherapie.")
                .foregroundStyle(Theme.text2)
            if let next {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Lektion \(next.n) von \(MindContent.lessons.count)", color: Theme.mind)
                    Text(next.title).font(.titleL)
                    Text(next.sub).foregroundStyle(Theme.text2)
                    Button { model.push(.lesson(next.id)) } label: { NextLabel("Starten · \(next.minutes) min") }
                        .buttonStyle(.primary(Theme.mind, large: false))
                        .frame(maxWidth: 220)
                        .padding(.top, 6)
                }
                .card(glow: Theme.mind)
                .zoomSource("lesson-\(next.id)", in: zoom)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alle Lektionen abgeschlossen").font(.titleM)
                    Text("Übe weiter mit den Werkzeugen. Wiederholung ist, was wirkt.").foregroundStyle(Theme.text2)
                }
                .card(glow: Theme.mind)
            }
            SectionHeader("Werkzeuge")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(MindContent.tools) { t in
                    Button { model.push(.tool(t.id)) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            IconBadge(symbol: t.symbol, color: Theme.mind, size: 34)
                            Text(t.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text(t.sub).font(.caption).foregroundStyle(Theme.text2).lineLimit(2, reservesSpace: true)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            SectionHeader("Alle Lektionen")
            VStack(spacing: 0) {
                ForEach(MindContent.lessons) { l in
                    let isDone = done.contains(l.id)
                    Button { model.push(.lesson(l.id)) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(isDone ? Theme.good.opacity(0.15) : Theme.mind.opacity(0.14))
                                if isDone { Image(systemName: "checkmark").foregroundStyle(Theme.good).font(.caption.weight(.bold)) }
                                else { Text("\(l.n)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.mind) }
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("\(l.sub) · \(l.minutes) min").font(.caption).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.text3)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if l.id != MindContent.lessons.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .card(padding: 6)
        }
        .navigationTitle("")
    }
}

struct LessonView: View {
    var id: String
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var start = Date.now
    @State private var answers: [String: String] = [:]

    var body: some View {
        if let l = MindContent.lesson(id) {
            let tool = l.tool.flatMap(MindContent.tool)
            Screen {
                ScreenHeader(eyebrow: "Lektion \(l.n) von \(MindContent.lessons.count) · \(l.minutes) min", title: l.title, lead: l.sub)
                ProseView(text: l.body).card()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grundlage: Bausteine der tinnitusspezifischen kognitiven Verhaltenstherapie. Selbsthilfe, keine Psychotherapie.")
                        .font(.caption).foregroundStyle(Theme.text3)
                    SourceLinks(refs: MindContent.lessonRefs, compact: true)
                }
                if !l.reflect.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zum Nachdenken").font(.titleM)
                        Text("Beantworte die Fragen für dich, gern schriftlich. Nichts davon wird geteilt.").font(.caption).foregroundStyle(Theme.text2)
                        ForEach(l.reflect, id: \.self) { q in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(q).font(.subheadline.weight(.semibold))
                                TextField("Deine Antwort …", text: Binding(get: { answers[q] ?? "" }, set: { answers[q] = $0 }), axis: .vertical)
                                    .lineLimit(2...5)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                            }
                        }
                    }
                    .card()
                }
                if let p = l.bodyProgram {
                    Button { model.open(.body(p)) } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: "figure.cooldown", color: Theme.body)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kiefer-Programm").font(.titleM).foregroundStyle(Theme.text)
                                Text("Ruheposition, geführte Öffnung, Selbstmassage").font(.caption).foregroundStyle(Theme.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
                        }
                        .card(glow: Theme.body)
                    }
                    .buttonStyle(.plain)
                }
                if let tool {
                    HStack(spacing: 12) {
                        IconBadge(symbol: tool.symbol, color: Theme.mind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Übung: \(tool.title)").font(.titleM)
                            Text(tool.sub).font(.caption).foregroundStyle(Theme.text2)
                        }
                    }
                    .card(glow: Theme.mind)
                }
                Button {
                    DataActions.completeLesson(ctx, l.id, durationS: Date.now.timeIntervalSince(start))
                    model.showToast("Lektion \(l.n) abgeschlossen")
                    if let tool { model.replaceTop(with: .tool(tool.id)) } else { model.pop() }
                } label: {
                    NextLabel(tool != nil ? "Abschließen und zur Übung" : "Lektion abschließen")
                }
                .buttonStyle(.primary(Theme.mind))
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { start = .now }
        }
    }
}

struct ToolView: View {
    var id: String
    var body: some View {
        switch id {
        case "thoughts": ThoughtsView()
        case "plan": SpikePlanView()
        default:
            if let t = MindContent.tool(id), let steps = t.steps {
                GuidedExerciseView(tool: t, steps: steps)
            }
        }
    }
}
