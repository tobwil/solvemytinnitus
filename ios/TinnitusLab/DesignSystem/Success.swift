import SwiftUI

/// Animated completion mark used at the end of every exercise: the ring draws itself, the check
/// springs in, a few soft particles drift outward. Static with "Bewegung reduzieren".
struct SuccessMark: View {
    var color: Color
    var size: CGFloat = 132
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @State private var pop = false
    @State private var burst = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.28), color.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.75))
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(pop ? 1 : 0.6)
                .opacity(pop ? 1 : 0)
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi + 0.3
                Circle()
                    .fill(i.isMultiple(of: 3) ? Theme.tin : color)
                    .frame(width: i.isMultiple(of: 2) ? 7 : 5)
                    .offset(x: burst ? cos(angle) * size * 0.78 : 0, y: burst ? sin(angle) * size * 0.78 : 0)
                    .opacity(burst ? 0 : 0.9)
                    .scaleEffect(burst ? 0.4 : 1)
            }
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 8)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: ring)
                .stroke(AngularGradient(colors: [color.opacity(0.6), color, Theme.tin.opacity(0.9), color], center: .center), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
            Circle()
                .fill(color.gradient)
                .frame(width: size * 0.72, height: size * 0.72)
                .scaleEffect(pop ? 1 : 0.2)
                .shadow(color: color.opacity(0.45), radius: 18, y: 8)
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.32, height: size * 0.24)
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .accessibilityElement()
        .accessibilityLabel("Abgeschlossen")
        .onAppear(perform: animate)
        .sensoryFeedback(.success, trigger: pop)
    }

    private func animate() {
        guard !reduceMotion else {
            ring = 1; check = 1; pop = true
            return
        }
        withAnimation(.easeOut(duration: 0.55)) { ring = 1 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.35)) { pop = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.55)) { check = 1 }
        withAnimation(.easeOut(duration: 0.9).delay(0.5)) { burst = true }
    }
}

private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Completion card: success mark, title, subtitle and optional stat chips.
struct CompletionCard<Extra: View>: View {
    var title: String
    var subtitle: String
    var color: Color
    var stats: [(String, String)]
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: 14) {
            SuccessMark(color: color)
            Text(title).font(.titleL)
            Text(subtitle).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            if !stats.isEmpty {
                HStack(spacing: 10) {
                    ForEach(stats, id: \.0) { s in
                        VStack(spacing: 2) {
                            Text(s.1).font(.display(22)).monospacedDigit().foregroundStyle(color)
                            Text(s.0).font(.caption).foregroundStyle(Theme.text3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
                    }
                }
            }
            extra
        }
        .frame(maxWidth: .infinity)
        .card(glow: color, padding: 20)
    }
}

extension CompletionCard where Extra == EmptyView {
    init(title: String, subtitle: String, color: Color, stats: [(String, String)] = []) {
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.stats = stats
        extra = EmptyView()
    }
}
