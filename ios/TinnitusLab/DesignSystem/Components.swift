import SwiftUI
import TinnitusAudio
import TinnitusCore

// MARK: - Background

/// Shared mood of the app: how warm (loud) the last check-in was. Every screen's background
/// follows it, so the whole app tells one story: calm teal on quiet days, a warmer amber glow on loud ones.
@MainActor
@Observable
final class Ambient {
    static let shared = Ambient()
    /// 0 = calm … 1 = very loud. Fades back to calm within 6 hours of the last check-in.
    var warmth: Double = 0

    func update(loudness: Double?, at ts: Date?) {
        guard let loudness, let ts else { warmth = 0; return }
        let age = Date.now.timeIntervalSince(ts) / 3600
        let w = max(0, min(1, (loudness - 3) / 6)) * max(0, 1 - age / 6)
        if abs(w - warmth) > 0.01 { withAnimation(.easeInOut(duration: 1.6)) { warmth = w } }
    }
}

/// Slow horizon glow behind every screen: teal at rest, warming towards amber after a loud check-in
/// (static with "Bewegung reduzieren").
struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ambient = Ambient.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || AppEnv.isUITest)) { tl in
            let t = reduceMotion || AppEnv.isUITest ? 0 : tl.date.timeIntervalSinceReferenceDate
            let a = Float(sin(t / 9)) * 0.08, b = Float(cos(t / 11)) * 0.06
            let w = ambient.warmth
            ZStack {
                Theme.bg
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5 + a, 0], [1, 0],
                    [0, 0.32 + b], [0.5 - a, 0.26 + b], [1, 0.32 - b],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Theme.sound.opacity(0.20 * (1 - w)), Theme.sound.opacity(0.12 * (1 - w)), Theme.sound.opacity(0.18 * (1 - w)),
                    Theme.sound.opacity(0.05), Theme.sound.opacity(0.04), Theme.sound.opacity(0.05),
                    Theme.bg.opacity(0), Theme.bg.opacity(0), Theme.bg.opacity(0),
                ])
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5 - a, 0], [1, 0],
                    [0, 0.36 - b], [0.5 + a, 0.3], [1, 0.36 + b],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    Theme.tin.opacity(0.24), Theme.tin.opacity(0.14), Theme.tin.opacity(0.22),
                    Theme.tin.opacity(0.05), Theme.tin.opacity(0.04), Theme.tin.opacity(0.05),
                    Theme.bg.opacity(0), Theme.bg.opacity(0), Theme.bg.opacity(0),
                ])
                .opacity(w)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Standard screen container: scroll view on the aurora background.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AuroraBackground())
    }
}

// MARK: - Text

struct Eyebrow: View {
    var text: String
    var color: Color = Theme.text3
    init(_ text: String, color: Color = Theme.text3) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased()).font(.eyebrow).tracking(0.8).foregroundStyle(color)
    }
}

struct ScreenHeader: View {
    var eyebrow: String?
    var title: String
    var lead: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { Eyebrow(eyebrow) }
            Text(title).font(.titleXL).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            if let lead { Text(lead).font(.body).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeader<Trailing: View>: View {
    var title: String
    var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title).font(.titleM).foregroundStyle(Theme.text)
            Spacer()
            trailing
        }
        .padding(.top, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        trailing = EmptyView()
    }
}

/// Renders the lesson markup (**bold**, bullets).
struct ProseView: View {
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Prose.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let p):
                    Text(markdown(p)).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Theme.text3).frame(width: 5, height: 5).offset(y: -2)
                                Text(markdown(item)).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

// MARK: - Surfaces

/// Quiet surface: one material, one hairline. `glow` only tints the hairline so emphasis stays subtle
/// and screens don't turn into a patchwork of coloured tiles.
struct CardModifier: ViewModifier {
    var glow: Color?
    var padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(glow?.opacity(0.28) ?? Theme.stroke, lineWidth: 1)
            }
            .softScroll()
    }
}

extension View {
    func card(glow: Color? = nil, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(glow: glow, padding: padding))
    }
}

struct Chip: View {
    enum Tone { case neutral, good, warn, bad, tint(Color) }
    var text: String
    var tone: Tone = .neutral
    var symbol: String?

    init(_ text: String, tone: Tone = .neutral, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    private var color: Color {
        switch tone {
        case .neutral: Theme.text2
        case .good: Theme.good
        case .warn: Theme.warn
        case .bad: Theme.bad
        case .tint(let c): c
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.semibold)) }
            Text(text).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

struct EvidenceBadge: View {
    var level: EvidenceLevel
    var label: String?
    private var color: Color {
        switch level {
        case .strong: Theme.good
        case .moderate: Theme.sound
        case .weak: Theme.tin
        case .experimental: Theme.warn
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(1...4, id: \.self) { i in
                    Capsule().fill(i <= level.rawValue ? color : Theme.stroke2).frame(width: 6, height: 6)
                }
            }
            Text(label ?? "Evidenz: \(level.label)").font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evidenz \(level.label), \(level.rawValue) von 4")
    }
}

struct Callout: View {
    enum Tone { case info, warn, good }
    var text: Text
    var tone: Tone = .info

    init(_ s: String, tone: Tone = .info) {
        text = Text((try? AttributedString(markdown: s)) ?? AttributedString(s))
        self.tone = tone
    }

    private var color: Color {
        switch tone {
        case .info: Theme.lab
        case .warn: Theme.warn
        case .good: Theme.good
        }
    }
    private var symbol: String {
        switch tone {
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .good: "checkmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.body.weight(.semibold))
            text.font(.subheadline).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius - 4, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius - 4, style: .continuous).strokeBorder(color.opacity(0.22)))
        .accessibilityElement(children: .combine)
    }
}

struct Metric: View {
    var label: String
    var value: String
    var unit: String?
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.display(22)).foregroundStyle(color).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                if let unit { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.text3) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
        .accessibilityElement(children: .combine)
    }
}

struct IconBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(color.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

// MARK: - Progress

struct RingView<Center: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center
    var body: some View {
        ZStack {
            Circle().stroke(Theme.surface3, lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            center
        }
    }
}

extension RingView where Center == EmptyView {
    init(progress: Double, color: Color, lineWidth: CGFloat = 10) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
        center = EmptyView()
    }
}

struct ProgressDots: View {
    var total: Int
    var done: Int
    var color: Color = Theme.lab
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule().fill(i < done ? color : Theme.surface3).frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fortschritt \(done) von \(total)")
    }
}

// MARK: - Inputs

/// 0–10 rating as tappable numbers (as in the web app).
struct Scale10: View {
    @Binding var value: Int?
    var labels: (String, String)
    var color: Color = Theme.tin
    var onPick: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0...10, id: \.self) { v in
                    Button {
                        value = v
                        Haptics.selection()
                        onPick?(v)
                    } label: {
                        Text("\(v)")
                            .font(.callout.weight(.semibold)).monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(value == v ? Theme.onAccent : Theme.text)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(value == v ? color : Theme.surface2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(v) von 10")
                    .accessibilityAddTraits(value == v ? .isSelected : [])
                }
            }
            HStack {
                Text(labels.0)
                Spacer()
                Text(labels.1)
            }
            .font(.caption).foregroundStyle(Theme.text3)
        }
    }
}

struct LabeledSlider: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var color: Color = Theme.sound
    var format: (Double) -> String = { "\(Int($0.rounded()))" }
    var scale: (String, String)?
    var onEditingEnded: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(Theme.text2)
                Spacer()
                Text(format(value)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
            }
            Slider(value: $value, in: range, step: step) { editing in
                if !editing { onEditingEnded?() }
            }
            .tint(color)
            .accessibilityLabel(label)
            .accessibilityValue(format(value))
            if let scale {
                HStack { Text(scale.0); Spacer(); Text(scale.1) }.font(.caption).foregroundStyle(Theme.text3)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ChoiceRow: View {
    var title: String
    var sub: String?
    var symbol: String?
    var selected: Bool
    var color: Color = Theme.lab
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack(spacing: 12) {
                if let symbol { IconBadge(symbol: symbol, color: color, size: 34) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    if let sub { Text(sub).font(.caption).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? color : Theme.text3).font(.title3)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? color.opacity(0.1) : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? color.opacity(0.5) : Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.text
    var large = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .headline : .subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: large ? 54 : 42)
            .foregroundStyle(color == Theme.text ? Theme.bg : Theme.onAccent)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var color: Color = Theme.text
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .headline : .subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: large ? 54 : 42)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static func primary(_ color: Color = Theme.text, large: Bool = true) -> PrimaryButtonStyle { PrimaryButtonStyle(color: color, large: large) }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static func ghost(_ color: Color = Theme.text, large: Bool = false) -> GhostButtonStyle { GhostButtonStyle(color: color, large: large) }
}

/// Button label with a trailing chevron ("Weiter: …").
struct NextLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
        }
    }
}

struct TextLinkButton: View {
    var title: String
    var symbol: String?
    var action: () -> Void
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { if let symbol { Image(systemName: symbol) } }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text2)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// Big round play/pause button used by players.
struct PlayButton: View {
    var playing: Bool
    var color: Color = Theme.sound
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 84, height: 84)
                .background(Circle().fill(color))
                .shadow(color: color.opacity(0.45), radius: 20, y: 8)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause" : "Start")
    }
}

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    enum Kind { case success, info, alert }
    var text: String
    var kind: Kind = .success
    let id = UUID()
}

struct ToastView: View {
    var toast: ToastMessage
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : toast.kind == .alert ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(toast.kind == .success ? Theme.good : toast.kind == .alert ? Theme.warn : Theme.lab)
            Text(toast.text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Theme.stroke2))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// "≈ 52 dB SPL" under level sliders when the device has a calibration profile (04-module "Labor").
struct SPLHint: View {
    var dbfs: Double
    var freq: Double
    @State private var engine = AudioEngine.shared
    var body: some View {
        let est = engine.estimator
        if est.profile.calibrated {
            Text("≈ \(Int(est.spl(dbfs: dbfs, at: freq).rounded())) dB SPL geschätzt (±\(Int(est.profile.uncertainty(at: freq))) dB, \(engine.deviceKind.label))")
                .font(.caption).foregroundStyle(Theme.text3)
        } else {
            Text("Relativer Pegel – Gerät unkalibriert").font(.caption).foregroundStyle(Theme.text3)
        }
    }
}
