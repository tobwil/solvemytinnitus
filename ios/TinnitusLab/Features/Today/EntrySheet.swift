import SwiftData
import SwiftUI
import TinnitusCore

/// What a timeline entry points to, so it can be corrected or removed.
enum EntryRef {
    case checkIn(CheckIn)
    case session(TherapySession)
    case mind(MindExercise)
    case body(BodySession)

    var model: any PersistentModel {
        switch self {
        case .checkIn(let c): c
        case .session(let s): s
        case .mind(let m): m
        case .body(let b): b
        }
    }
}

extension FlowEvent {
    static func checkIn(_ c: CheckIn) -> FlowEvent {
        FlowEvent(id: c.uid, time: c.ts, symbol: "waveform.path.ecg", title: "Lautheit \(Int(c.loudness)) · Belastung \(Int(c.distress))",
                  tint: Theme.tin, ref: .checkIn(c))
    }
}

/// Open an entry: check-ins can be corrected, every entry can be deleted (with confirmation).
struct EntrySheet: View {
    var event: FlowEvent
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var loudness: Int?
    @State private var distress: Int?
    @State private var confirmDelete = false

    private var checkIn: CheckIn? { if case .checkIn(let c) = event.ref { c } else { nil } }
    private var changed: Bool {
        guard let c = checkIn else { return false }
        return loudness != Int(c.loudness) || distress != Int(c.distress)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(event.time.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                        Text(checkIn == nil ? event.title : "Check-in").font(.titleL)
                        if checkIn == nil, let d = event.detail { Text(d).foregroundStyle(Theme.text2) }
                    }
                    if checkIn != nil {
                        Text("Wie laut war er?").font(.titleM)
                        LoudnessDial(value: $loudness, kind: .loudness, color: Theme.tin)
                        Text("Wie sehr hat er dich belastet?").font(.titleM).padding(.top, 4)
                        LoudnessDial(value: $distress, kind: .distress, color: Theme.distress)
                        Button("Änderung speichern") {
                            if let c = checkIn, let l = loudness, let d = distress {
                                DataActions.updateCheckIn(ctx, c, loudness: Double(l), distress: Double(d))
                                model.showToast("Check-in geändert")
                            }
                            dismiss()
                        }
                        .buttonStyle(.primary(Theme.tin))
                        .disabled(!changed || loudness == nil || distress == nil)
                        .padding(.top, 4)
                    } else if let r = event.route {
                        Button {
                            dismiss()
                            model.open(r)
                        } label: { NextLabel("Nochmal öffnen") }
                        .buttonStyle(.ghost(Theme.accent, large: true))
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Eintrag löschen", systemImage: "trash").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .tint(Theme.bad)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
            .alert("Eintrag löschen?", isPresented: $confirmDelete) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    if let ref = event.ref { DataActions.deleteEntry(ctx, ref.model) }
                    model.showToast("Eintrag gelöscht")
                    dismiss()
                }
            } message: {
                Text("Der Eintrag verschwindet aus Tageswelle, Verlauf und Auswertungen.")
            }
        }
        .presentationDetents(checkIn == nil ? [.medium] : [.large])
        .presentationBackground(Theme.bgElevated)
        .onAppear {
            if let c = checkIn {
                loudness = Int(c.loudness)
                distress = Int(c.distress)
            }
        }
    }
}

/// All check-ins, newest first, each one tappable to correct or delete (in "Verlauf").
struct CheckInHistory: View {
    @Query(sort: \CheckIn.ts, order: .reverse) private var checkins: [CheckIn]
    @State private var showAll = false
    @State private var editing: FlowEvent?

    var body: some View {
        if !checkins.isEmpty {
            let shown = Array(checkins.prefix(showAll ? 200 : 8))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Check-ins").font(.titleM)
                    Spacer()
                    Text("Tippen zum Ändern").font(.caption).foregroundStyle(Theme.text3)
                }
                VStack(spacing: 0) {
                    ForEach(shown) { c in
                        Button { editing = .checkIn(c) } label: {
                            HStack(spacing: 10) {
                                Text(c.ts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                    .font(.subheadline).foregroundStyle(Theme.text)
                                Spacer()
                                Chip("\(Int(c.loudness))", tone: .tint(Theme.tin))
                                Chip("\(Int(c.distress))", tone: .tint(Theme.distress))
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.text3)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Check-in \(c.ts.formatted(date: .abbreviated, time: .shortened)), Lautheit \(Int(c.loudness)), Belastung \(Int(c.distress))")
                        if c.id != shown.last?.id { Divider() }
                    }
                }
                if checkins.count > 8 {
                    TextLinkButton(showAll ? "Weniger anzeigen" : "Alle \(checkins.count) anzeigen") { withAnimation { showAll.toggle() } }
                }
            }
            .card()
            .sheet(item: $editing) { EntrySheet(event: $0) }
        }
    }
}
