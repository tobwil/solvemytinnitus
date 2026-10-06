import SwiftData
import SwiftUI
import TinnitusCore

/// Two questions, ten seconds. Several ratings a day show fluctuations and triggers.
struct CheckInView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: \CheckIn.ts, order: .reverse) private var recent: [CheckIn]
    @State private var loudness: Int?
    @State private var distress: Int?

    private var last: CheckIn? { recent.first }

    var body: some View {
        NavigationStack {
            Screen {
                ScreenHeader(eyebrow: "Kurz-Check-in", title: "Wie ist es gerade?", lead: "Zwei Fragen, zehn Sekunden. Mehrere kurze Einschätzungen am Tag zeigen Schwankungen und Auslöser viel genauer als ein Tageswert.")
                if let last {
                    Button {
                        loudness = Int(last.loudness)
                        distress = Int(last.distress)
                        Haptics.selection()
                    } label: {
                        Label("Wie zuletzt: \(Int(last.loudness)) und \(Int(last.distress)) · \(last.ts.formatted(.relative(presentation: .named)))", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.ghost(Theme.text2))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wie laut ist dein Tinnitus jetzt?").font(.titleM)
                    LoudnessDial(value: $loudness, kind: .loudness, color: Theme.tin)
                }
                .card()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wie sehr belastet er dich gerade?").font(.titleM)
                    LoudnessDial(value: $distress, kind: .distress, color: Theme.distress)
                }
                .card()
                Button("Speichern") {
                    DataActions.addCheckIn(ctx, loudness: Double(loudness!), distress: Double(distress!))
                    model.showToast("Check-in gespeichert")
                    dismiss()
                }
                .buttonStyle(.primary())
                .disabled(loudness == nil || distress == nil)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
    }
}
