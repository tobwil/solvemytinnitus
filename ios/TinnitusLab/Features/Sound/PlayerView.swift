import MediaPlayer
import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore
import UniformTypeIdentifiers

struct PlayerView: View {
    var mode: TherapyMode
    @Environment(\.modelContext) private var ctx
    @Environment(AppModel.self) private var model
    @Query private var ri: [RITrial]
    @State private var session = SessionController.shared
    @State private var engine = AudioEngine.shared
    @State private var draft: SessionController.Config?
    @State private var askPre = false
    @State private var pre: Int?
    @State private var showFiles = false
    @State private var showLibrary = false
    @State private var loadingMusic = false
    @State private var musicError: String?
    @State private var widthDraft: Double?
    @State private var showSettings = false

    private var info: ModeInfo { SoundContent.mode(mode) }
    /// 05-audio-engine: speaker output only for enrichment.
    private var speakerBlocked: Bool { engine.deviceKind == .speaker && mode != .enrichment }
    private var isThis: Bool { session.config?.mode == mode }
    private var cfg: SessionController.Config? { isThis ? session.config : draft }
    private var best: RISummary? { RIAnalysis.best(ri.map { .init(stimulus: $0.stimulus, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) }) }

    var body: some View {
        Screen {
            if let c = cfg {
                header(c)
                if session.isActive && !isThis {
                    Callout("Gerade läuft „\(session.title)“. Beim Start wird es beendet und gespeichert.", tone: .warn)
                }
                if let msg = session.message, isThis { Callout(msg, tone: .warn) }
                if speakerBlocked {
                    Callout("Über den Lautsprecher ist nur Klanganreicherung erlaubt. Für dieses Programm brauchst du Kopfhörer.", tone: .warn)
                }
                DisclosureGroup(isExpanded: $showSettings) {
                    VStack(alignment: .leading, spacing: 12) {
                        LiveSpectrumView(tinnitusHz: c.freq, notch: c.mode == .notched ? notchBand(c) : nil)
                        settingsCard(c)
                    }
                    .padding(.top, 10)
                } label: {
                    Label("Klang anpassen", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                }
                .tint(Theme.text2)
                .card()
                DisclosureGroup("Wie es wirken soll und was belegt ist") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(info.desc)
                        Text("**Evidenz:** \(info.evidence)")
                        if !info.refs.isEmpty {
                            Eyebrow("Quellen").padding(.top, 4)
                            SourceLinks(refs: info.refs)
                        }
                    }
                    .font(.subheadline).foregroundStyle(Theme.text2).padding(.top, 8)
                }
                .font(.subheadline.weight(.semibold)).tint(Theme.text2)
                .card()
            } else {
                Callout("Für dieses Programm brauchen wir zuerst eine Messung deiner Tinnitus-Frequenz.", tone: .warn)
                Button("Zur Messung") { model.open(.spectrum) }.buttonStyle(.primary(Theme.lab))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(isPresented: $askPre) { preSheet }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { Task { await loadMusic(url) } }
        }
        .sheet(isPresented: $showLibrary) {
            MediaPickerView { url in
                showLibrary = false
                if let url { Task { await loadMusic(url) } }
            }
            .ignoresSafeArea()
        }
    }

    private func load() {
        guard draft == nil, let m = ctx.latestMatch() else { return }
        draft = SessionController.defaultConfig(mode: mode, match: m, settings: ctx.settings(), best: best?.stimulus)
    }

    private func notchBand(_ c: SessionController.Config) -> ClosedRange<Double> {
        let h = pow(2, c.widthOctaves / 2)
        return (c.freq / h)...(c.freq * h)
    }

    /// Edits go to the running session or to the draft.
    private func edit(_ change: @escaping (inout SessionController.Config) -> Void) {
        if isThis { session.update(change) } else if var d = draft { change(&d); draft = d }
    }

    // MARK: Header / transport

    private func header(_ c: SessionController.Config) -> some View {
        let running = isThis && session.state == .running
        let remaining = isThis ? session.remaining : (c.targetMin > 0 ? Double(c.targetMin * 60) : nil)
        return VStack(spacing: 14) {
            Eyebrow("Klang", color: Theme.sound)
            Text(info.title).font(.titleL)
            EvidenceBadge(level: info.level)
            RingView(progress: isThis ? session.progress : 0, color: Theme.sound, lineWidth: 10) {
                VStack(spacing: 4) {
                    Text(remaining.map { Format.duration($0) } ?? Format.duration(isThis ? session.elapsed : 0))
                        .font(.display(44)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: remaining != nil))
                        .animation(.linear(duration: 0.3), value: Int(session.elapsed))
                    Text(isThis ? session.phase : "Bereit").font(.caption).foregroundStyle(session.silence && isThis ? Theme.tin : Theme.text2)
                        .multilineTextAlignment(.center).frame(maxWidth: 170)
                }
            }
            .frame(width: 230, height: 230)
            .background { SoundOrb(color: session.silence && isThis ? Theme.tin : Theme.sound, active: running && !session.silence).frame(width: 330, height: 330) }
            PlayButton(playing: running) { togglePlay() }
                .disabled(speakerBlocked && !isThis)
                .opacity(speakerBlocked && !isThis ? 0.4 : 1)
            durationChips(c)
            if isThis {
                Button { session.finish(auto: false) } label: { Label("Beenden", systemImage: "stop.fill") }
                    .buttonStyle(.ghost(Theme.text2))
                    .frame(maxWidth: 160)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func togglePlay() {
        if isThis {
            session.toggle()
            return
        }
        guard draft != nil else { return }
        if draft?.source == .music && session.music == nil {
            showFiles = true
            return
        }
        pre = nil
        askPre = true
    }

    private func startNow(pre: Double?) {
        guard let d = draft else { return }
        session.start(d, origin: .app, pre: pre)
    }

    private var preSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vorher kurz bewerten").font(.titleL)
            Text("Wie laut ist dein Tinnitus jetzt? So sehen wir später, was bei dir wirkt.").foregroundStyle(Theme.text2)
            Scale10(value: $pre, labels: ("nicht hörbar", "extrem laut")) { v in
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    askPre = false
                    startNow(pre: Double(v))
                }
            }
            TextLinkButton("Überspringen") {
                askPre = false
                startNow(pre: nil)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Theme.bgElevated)
    }

    // MARK: Settings

    private func settingsCard(_ c: SessionController.Config) -> some View {
        let est = engine.estimator
        let spl = est.spl(dbfs: c.levelDb, at: c.mode == .enrichment && c.source != .am ? 1000 : c.freq)
        let cap = SafetyLimits.capDbfs(purpose: .sound, estimator: est, freq: c.freq)
        return VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(label: "Pegel", value: Binding(get: { c.levelDb }, set: { v in
                if isThis { session.setLevel(v) } else { draft?.levelDb = v }
            }), range: -70...(-8), color: Theme.sound, format: { "\(Int($0)) dB" })
            HStack {
                Text(engine.profile.calibrated ? "≈ \(Int(min(spl, 85))) dB SPL (\(engine.deviceKind.label), geschätzt)" : "relativer Pegel, Gerät unkalibriert")
                Spacer()
                if c.levelDb > cap { Chip("Hörschutz-Deckel", tone: .warn, symbol: "shield.lefthalf.filled") }
            }
            .font(.caption).foregroundStyle(Theme.text3)
            modeSettings(c)
        }
    }

    /// Duration as quick choices right under the play button; the last minute fades out (sleep timer).
    private func durationChips(_ c: SessionController.Config) -> some View {
        let options: [(Int, String)] = [(15, "15 min"), (30, "30 min"), (60, "1 h"), (480, "Nacht"), (0, "∞")]
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { m, label in
                    let on = c.targetMin == m
                    Button {
                        if isThis { session.setTarget(minutes: m) } else { draft?.targetMin = m }
                        Haptics.selection()
                    } label: {
                        Text(label).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(on ? Theme.onAccent : Theme.text)
                            .background(Capsule().fill(on ? Theme.sound : Theme.surface2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("Läuft auch bei gesperrtem Bildschirm · die letzte Minute klingt sanft aus").font(.caption).foregroundStyle(Theme.text3)
        }
    }

    @ViewBuilder
    private func modeSettings(_ c: SessionController.Config) -> some View {
        switch c.mode {
        case .enrichment:
            Text("Klang").font(.titleM)
            Picker("Klang", selection: Binding(get: { c.source }, set: { v in edit { $0.source = v } })) {
                ForEach([SoundSource.am, .rain, .pink, .brown], id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Ziel ist der „Mixing Point“: Der Tinnitus soll noch leicht hörbar bleiben, eingebettet in den Klang.").font(.caption).foregroundStyle(Theme.text3)
            Toggle("Mit anderen Apps mischen (z. B. unter einem Hörbuch)", isOn: Binding(get: { ctx.settings().mixWithOthers }, set: { ctx.settings().mixWithOthers = $0 }))
                .font(.subheadline).tint(Theme.sound)
        case .notched:
            Text("Klangquelle").font(.titleM)
            Picker("Quelle", selection: Binding(get: { c.source }, set: { v in
                if v == .music && session.music == nil { showFiles = true }
                edit { $0.source = v }
            })) {
                ForEach([SoundSource.pink, .white, .rain, .music], id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Button { showFiles = true } label: { Label("Datei", systemImage: "folder") }.buttonStyle(.ghost(Theme.sound))
                Button { showLibrary = true } label: { Label("Mediathek", systemImage: "music.note.list") }.buttonStyle(.ghost(Theme.sound))
            }
            if loadingMusic { ProgressView("Musik wird gefiltert …").font(.caption) }
            if let m = session.music { Text("\(m.title)\(m.truncated ? " (erste 10 min)" : "")").font(.caption).foregroundStyle(Theme.text2) }
            if let musicError { Text(musicError).font(.caption).foregroundStyle(Theme.warn) }
            Text("Apple-Music-Titel sind kopiergeschützt und lassen sich nicht filtern. Gekaufte oder eigene Dateien funktionieren.").font(.caption).foregroundStyle(Theme.text3)
            LabeledSlider(label: "Breite der Lücke", value: Binding(get: { widthDraft ?? c.widthOctaves }, set: { v in
                widthDraft = v
                if !isThis { draft?.widthOctaves = v }
            }), range: 0.5...2, step: 0.25, color: Theme.sound,
                          format: { "\(Format.decimal($0, digits: 2)) Okt." }, onEditingEnded: {
                if isThis, let w = widthDraft { session.update { $0.widthOctaves = w } }
            })
            let band = notchBand(c)
            Text("Lücke: \(Format.hz(band.lowerBound)) – \(Format.hz(band.upperBound))").font(.caption).foregroundStyle(Theme.text3)
        case .reset:
            if let best {
                Callout("Vorausgewählt: dein bester Klang aus dem Labor (Ø −\(Format.decimal(best.depth)) Punkte).", tone: .good)
            } else {
                Callout("Noch kein Labor-Ergebnis, Standard ist Schmalband ⅓ Oktave.", tone: .warn)
            }
            Picker("Klang", selection: Binding(get: { c.stimulus }, set: { v in edit { $0.stimulus = v } })) {
                ForEach(SoundContent.stimuli) { s in Text(s.label + (best?.stimulus == s.kind ? " ★" : "")).tag(s.kind) }
            }
            .pickerStyle(.menu)
            LabeledSlider(label: "Klang-Phase", value: Binding(get: { c.onS }, set: { v in edit { $0.onS = v } }), range: 15...90, step: 5, color: Theme.sound, format: { "\(Int($0)) s" })
            LabeledSlider(label: "Stille-Phase", value: Binding(get: { c.offS }, set: { v in edit { $0.offS = v } }), range: 15...180, step: 5, color: Theme.sound, format: { "\(Int($0)) s" })
        case .cr:
            HStack {
                ForEach(Recipe.crRatios, id: \.self) { r in Chip(Format.hz(c.freq * r), tone: .tint(Theme.sound)) }
            }
            Text("Sehr leise, nahe der Hörschwelle, wie in der Originalstudie.").font(.caption).foregroundStyle(Theme.text3)
        }
    }

    private func loadMusic(_ url: URL) async {
        guard let c = cfg else { return }
        loadingMusic = true
        musicError = nil
        defer { loadingMusic = false }
        do {
            let m = try await MusicLoader.load(url: url, center: c.freq, widthOctaves: c.widthOctaves)
            session.music = m
            edit { $0.source = .music }
        } catch {
            musicError = error.localizedDescription
        }
    }
}

/// Music library picker; only DRM-free items with an asset URL can go through the notch.
struct MediaPickerView: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let p = MPMediaPickerController(mediaTypes: .music)
        p.allowsPickingMultipleItems = false
        p.showsCloudItems = false
        p.prompt = "Nur Titel ohne Kopierschutz"
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MPMediaPickerControllerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            onPick(collection.items.first?.assetURL)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) { onPick(nil) }
    }
}
