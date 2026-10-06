import SwiftData
import SwiftUI
import TinnitusCore

struct ThoughtsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query(sort: \ThoughtRecord.date, order: .reverse) private var records: [ThoughtRecord]
    @State private var situation = ""
    @State private var thought = ""
    @State private var feeling: Int?
    @State private var alternative = ""
    @State private var feelingAfter: Int?

    var body: some View {
        Screen {
            ScreenHeader(eyebrow: "Werkzeug", title: "Gedanken-Check", lead: "Schreib eine Situation auf, in der der Tinnitus dich belastet hat, und prüfe den Gedanken dahinter.")
            VStack(alignment: .leading, spacing: 12) {
                field("1 · Situation", "Wo warst du, was war los? z. B. „Abends im Bett, alles still“", $situation)
                field("2 · Automatischer Gedanke", "Was ging dir durch den Kopf? z. B. „Ich werde heute wieder nicht schlafen“", $thought)
                Text("3 · Wie belastend fühlte sich das an?").font(.titleM)
                Scale10(value: $feeling, labels: ("gar nicht", "extrem"), color: Theme.mind)
            }
            .card()
            VStack(alignment: .leading, spacing: 12) {
                Text("4 · Prüfen").font(.titleM)
                ForEach(MindContent.thoughtPrompts, id: \.self) { q in
                    Label(q, systemImage: "chevron.right.circle").font(.subheadline).foregroundStyle(Theme.text)
                }
                field("5 · Ausgewogenerer Gedanke", "z. B. „Ich habe schon oft trotz Tinnitus geschlafen. Ich mache die Klanganreicherung an.“", $alternative)
                Text("6 · Wie belastend jetzt?").font(.titleM)
                Scale10(value: $feelingAfter, labels: ("gar nicht", "extrem"), color: Theme.mind)
            }
            .card(glow: Theme.mind)
            Button("Speichern") {
                ctx.insert(ThoughtRecord(situation: situation, thought: thought, feeling: Double(feeling ?? 0), alternative: alternative, feelingAfter: Double(feelingAfter ?? 0)))
                DataActions.logMind(ctx, kind: "thoughts", durationS: 300)
                model.showToast("Gedanken-Check gespeichert")
                model.pop()
            }
            .buttonStyle(.primary(Theme.mind))
            .disabled(thought.trimmingCharacters(in: .whitespaces).isEmpty || alternative.trimmingCharacters(in: .whitespaces).isEmpty)
            if !records.isEmpty {
                SectionHeader("Frühere Einträge")
                ForEach(records.prefix(10)) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Theme.text3)
                            Spacer()
                            Chip("\(Int(r.feeling)) → \(Int(r.feelingAfter))", tone: r.feelingAfter < r.feeling ? .good : .neutral)
                        }
                        Text(r.thought).strikethrough(color: Theme.text3).foregroundStyle(Theme.text2)
                        Text(r.alternative).font(.body.weight(.semibold))
                    }
                    .card(padding: 12)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.titleM)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...6)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
        }
    }
}

struct SpikePlanView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        Screen {
            ScreenHeader(eyebrow: "Werkzeug", title: "Notfallplan", lead: "Schreib ihn an einem guten Tag. An einem lauten Tag liest du ihn nur noch und folgst ihm. Er ist auch als Widget erreichbar.")
            TextEditor(text: $text)
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
            Callout("Plötzliche starke Veränderung, pulsierender Tinnitus, Hörverlust oder Schwindel: zeitnah HNO-ärztlich abklären lassen.", tone: .warn)
            Button("Speichern") {
                ctx.settings().spikePlan = text
                DataActions.logMind(ctx, kind: "plan", durationS: 300)
                model.showToast("Notfallplan gespeichert")
                model.pop()
            }
            .buttonStyle(.primary(Theme.mind))
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let p = ctx.settings().spikePlan
            text = p.isEmpty ? MindContent.spikePlanTemplate : p
        }
    }
}
