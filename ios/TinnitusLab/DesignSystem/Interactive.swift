import SwiftUI
import TinnitusAudio
import TinnitusCore

// MARK: - Loudness dial

/// Large 0–10 dial for check-ins: drag or tap, haptic detent per step, a word for the value and a
/// colour that grows stronger with the rating. Faster and more forgiving than eleven small buttons.
struct LoudnessDial: View {
    enum Kind { case loudness, distress }
    @Binding var value: Int?
    var kind: Kind
    var color: Color

    private var words: [String] {
        kind == .loudness
            ? ["nicht hörbar", "kaum", "kaum", "leise", "leise", "deutlich", "deutlich", "laut", "laut", "sehr laut", "extrem laut"]
            : ["gar nicht", "kaum", "kaum", "etwas", "etwas", "spürbar", "spürbar", "stark", "stark", "sehr stark", "extrem"]
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let value {
                    Text("\(value)")
                        .font(.display(56))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText(value: Double(value)))
                    Text(words[value]).font(.headline).foregroundStyle(Theme.text2).contentTransition(.opacity)
                } else {
                    Label("Auf die Skala tippen oder ziehen", systemImage: "hand.tap")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text3)
                        .frame(minHeight: 66, alignment: .leading)
                }
                Spacer()
            }
            .animation(.snappy(duration: 0.2), value: value)
            GeometryReader { g in
                let w = g.size.width
                let step = w / 10
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface3).frame(height: 14)
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.35), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, CGFloat(value ?? 0) * step + 14), height: 14)
                        .opacity(value == nil ? 0 : 1)
                    ForEach(0...10, id: \.self) { i in
                        Circle()
                            .fill(i <= (value ?? -1) ? Color.white.opacity(0.7) : Theme.text3.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .position(x: max(7, min(w - 7, CGFloat(i) * step)), y: 22)
                    }
                    if let value {
                        Circle()
                            .fill(Theme.bgElevated)
                            .overlay(Circle().strokeBorder(color, lineWidth: 3))
                            .frame(width: 34, height: 34)
                            .shadow(color: color.opacity(0.35), radius: 8, y: 3)
                            .position(x: max(17, min(w - 17, CGFloat(value) * step)), y: 22)
                            .animation(.snappy(duration: 0.18), value: value)
                    }
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let nv = Int((v.location.x / step).rounded()).clamped(0, 10)
                    if nv != value { value = nv }
                })
            }
            .frame(height: 44)
            HStack {
                Text(kind == .loudness ? "nicht hörbar" : "gar nicht")
                Spacer()
                Text("extrem")
            }
            .font(.caption).foregroundStyle(Theme.text3)
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(kind == .loudness ? "Lautheit" : "Belastung")
        .accessibilityValue(value.map { "\($0) von 10, \(words[$0])" } ?? "nicht gewählt")
        .accessibilityAdjustableAction { dir in
            let v = value ?? 5
            value = (dir == .increment ? v + 1 : v - 1).clamped(0, 10)
        }
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

// MARK: - Sound orb

/// Living orb behind the player ring: breathes slowly and reacts to the energy of what is playing.
/// Calm and dim during silence phases; static with "Bewegung reduzieren".
struct SoundOrb: View {
    var color: Color
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active || AppEnv.isUITest)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let bins = AudioEngine.shared.analyzer.bins()
            let energy = active ? min(1, max(0, (Double(bins.reduce(0, +)) / Double(max(1, bins.count)) + 105) / 45)) : 0
            let breath = 0.5 + 0.5 * sin(t * 2 * .pi / 6)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let k = Double(i)
                    Circle()
                        .fill(RadialGradient(colors: [color.opacity(0.32 - k * 0.08), color.opacity(0)], center: .center, startRadius: 0, endRadius: 150))
                        .scaleEffect(0.78 + 0.08 * breath + 0.22 * energy * (1 - k * 0.25))
                        .offset(x: cos(t * (0.4 + k * 0.17) + k) * 8 * energy, y: sin(t * (0.33 + k * 0.21) + k) * 8 * energy)
                        .blur(radius: 6 + k * 6)
                }
            }
        }
        .onAppear { AudioEngine.shared.retainAnalyser() }
        .onDisappear { AudioEngine.shared.releaseAnalyser() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Tinnitus preview

/// "So klingt mein Tinnitus": plays the measured tone/hiss for a few seconds, e.g. to show relatives.
struct TinnitusPreviewButton: View {
    var match: TinnitusMatch
    @State private var playing = false

    var body: some View {
        Button {
            guard !playing else { return }
            play()
        } label: {
            Label(playing ? "Spielt …" : "So klingt mein Tinnitus", systemImage: playing ? "speaker.wave.3.fill" : "ear")
                .symbolEffect(.variableColor.iterative, isActive: playing)
        }
        .buttonStyle(.ghost(Theme.tin))
        .accessibilityHint("Spielt deinen gemessenen Tinnitus-Klang vier Sekunden lang leise ab, zum Beispiel für Angehörige.")
    }

    private func play() {
        let engine = AudioEngine.shared
        guard engine.canMeasure else { return }
        engine.configureSession()
        playing = true
        let recipe: Recipe = match.timbre == .tone ? .tone(freq: match.freq) : .narrowband(freq: match.freq, widthOctaves: 1.0 / 3)
        // the matched loudness, never louder than measurement limits
        let v = engine.play(recipe, ear: match.ear, levelDb: min(match.loudnessDb, -20), purpose: .measurement)
        Task {
            try? await Task.sleep(for: .seconds(4))
            v.stop(fadeMs: 400)
            try? await Task.sleep(for: .milliseconds(400))
            playing = false
        }
    }
}

// MARK: - Zoom transitions

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Shared namespace for card → detail zoom transitions.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks a card as the source of a zoom transition.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in ns: Namespace.ID?) -> some View {
        if let ns { matchedTransitionSource(id: id, in: ns) } else { self }
    }

    /// Detail view that zooms out of its source card.
    @ViewBuilder
    func zoomDestination(_ id: some Hashable, in ns: Namespace.ID?) -> some View {
        if let ns { navigationTransition(.zoom(sourceID: id, in: ns)) } else { self }
    }

    /// Cards fade and scale slightly while they scroll in and out of view.
    func softScroll() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }
}

// MARK: - Chip scroller

/// Horizontal row of chips that shows where more is: the clipped edge fades out and a small arrow
/// appears on that side (tap to page). Both disappear once the row reaches its end.
/// Bleeds to the screen edges; the first and last chip keep the 20 pt page gutter.
struct ChipScroller<Item: Identifiable, Content: View>: View {
    var items: [Item]
    @ViewBuilder var chip: (Item) -> Content
    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var position = ScrollPosition(edge: .leading)

    private var canLeft: Bool { offset > 4 }
    private var canRight: Bool { offset < maxOffset - 4 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { chip($0) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: [CGFloat].self) { g in
            [g.contentOffset.x + g.contentInsets.leading, max(0, g.contentSize.width - g.containerSize.width), g.containerSize.width]
        } action: { _, v in
            withAnimation(.easeOut(duration: 0.2)) {
                offset = v[0]
                maxOffset = v[1]
                width = v[2]
            }
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: canLeft ? 84 : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: canRight ? 84 : 0)
            }
        }
        .overlay(alignment: .leading) {
            if canLeft { arrow("chevron.left", label: "Zurückblättern") { page(-1) } }
        }
        .overlay(alignment: .trailing) {
            if canRight { arrow("chevron.right", label: "Weitere Optionen") { page(1) } }
        }
        .padding(.horizontal, -20)
    }

    private func page(_ dir: CGFloat) {
        let target = min(maxOffset, max(0, offset + dir * width * 0.6))
        withAnimation(.snappy(duration: 0.35)) { position.scrollTo(x: target) }
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Theme.stroke2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .accessibilityLabel(label)
    }
}
