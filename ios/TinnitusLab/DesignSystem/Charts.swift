import Charts
import SwiftUI
import TinnitusAudio
import TinnitusCore

/// Likeness spectrum as bars, highest bar in amber.
struct SpectrumBars: View {
    var points: [SpectrumPoint]
    var peak: Double?
    var height: CGFloat = 150

    var body: some View {
        Chart(points, id: \.freq) { p in
            BarMark(x: .value("Frequenz", label(p.freq)), y: .value("Ähnlichkeit", p.value))
                .foregroundStyle(p.freq == peak ? Theme.tin : Theme.lab.opacity(0.7))
                .cornerRadius(4)
        }
        .chartYScale(domain: 0...10)
        .chartYAxis { AxisMarks(values: [0, 5, 10]) }
        .frame(height: height)
        .accessibilityLabel("Tinnitus-Spektrum, höchste Ähnlichkeit bei \(peak.map(Format.hz) ?? "–")")
    }

    private func label(_ f: Double) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }
}

/// Tiny trend line (Heute).
struct Sparkline: View {
    var values: [Double]
    var color: Color = Theme.tin
    var range: ClosedRange<Double> = 0...10
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("Tag", i), y: .value("Wert", v))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Tag", i), y: .value("Wert", v))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartYScale(domain: range)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 64)
        .accessibilityHidden(true)
    }
}

/// Hearing profile per ear on a log frequency axis. Lower on the chart = worse hearing.
struct HearingChart: View {
    var left: [HearingPoint]
    var right: [HearingPoint]
    var tinnitusHz: Double?
    /// "dB HL" for Apple audiograms / merged, "dB rel." for the app's own relative values.
    var unit: String
    var height: CGFloat = 220

    var body: some View {
        Chart {
            ForEach(left, id: \.freq) { p in
                LineMark(x: .value("Hz", log2(p.freq)), y: .value(unit, p.level), series: .value("Ohr", "Links"))
                    .foregroundStyle(by: .value("Ohr", "Links"))
                PointMark(x: .value("Hz", log2(p.freq)), y: .value(unit, p.level))
                    .foregroundStyle(by: .value("Ohr", "Links"))
            }
            ForEach(right, id: \.freq) { p in
                LineMark(x: .value("Hz", log2(p.freq)), y: .value(unit, p.level), series: .value("Ohr", "Rechts"))
                    .foregroundStyle(by: .value("Ohr", "Rechts"))
                PointMark(x: .value("Hz", log2(p.freq)), y: .value(unit, p.level))
                    .foregroundStyle(by: .value("Ohr", "Rechts"))
            }
            if let tinnitusHz {
                RuleMark(x: .value("Tinnitus", log2(tinnitusHz)))
                    .foregroundStyle(Theme.tin)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .center) { Text("Tinnitus").font(.caption2).foregroundStyle(Theme.tin) }
            }
        }
        .chartForegroundStyleScale(["Links": Theme.sound, "Rechts": Theme.distress])
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartXScale(domain: log2(250.0)...log2(16000.0))
        .chartXAxis {
            AxisMarks(values: [250.0, 500, 1000, 2000, 4000, 8000, 16000].map { log2($0) }) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let x = v.as(Double.self) {
                        let f = pow(2, x)
                        Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))")
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Live FFT of the output with the tinnitus frequency and optional notch band (web "spectrumViz").
struct LiveSpectrumView: View {
    var tinnitusHz: Double?
    var notch: ClosedRange<Double>?
    var color: Color = Theme.sound
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30)) { tl in
            // the renderer must depend on the timeline date, otherwise SwiftUI keeps the first frame
            let frame = tl.date
            Canvas { ctx, size in
                _ = frame
                let bins = AudioEngine.shared.analyzer.bins()
                let n = bins.count
                let minHz = SpectrumAnalyzer.minHz, maxHz = SpectrumAnalyzer.maxHz
                func x(_ f: Double) -> CGFloat { CGFloat(log(f / minHz) / log(maxHz / minHz)) * size.width }
                if let notch {
                    let r = CGRect(x: x(notch.lowerBound), y: 0, width: x(notch.upperBound) - x(notch.lowerBound), height: size.height)
                    ctx.fill(Path(r), with: .color(Theme.tin.opacity(0.08)))
                }
                let w = size.width / CGFloat(n)
                for i in 0..<n {
                    let db = Double(bins[i])
                    let norm = max(0, min(1, (db + 110) / 90))
                    let h = CGFloat(norm) * size.height
                    let rect = CGRect(x: CGFloat(i) * w + 1, y: size.height - h, width: max(1, w - 2), height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(0.35 + 0.65 * norm)))
                }
                if let tinnitusHz {
                    var p = Path()
                    p.move(to: CGPoint(x: x(tinnitusHz), y: 0))
                    p.addLine(to: CGPoint(x: x(tinnitusHz), y: size.height))
                    ctx.stroke(p, with: .color(Theme.tin), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
        }
        .frame(height: 90)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { AudioEngine.shared.retainAnalyser() }
        .onDisappear { AudioEngine.shared.releaseAnalyser() }
        .accessibilityLabel("Live-Spektrum des Klangs")
    }
}

/// Simple time series chart with optional second series and baseline.
struct SeriesChart: View {
    struct Series: Identifiable {
        var name: String
        var color: Color
        var points: [(Date, Double)]
        var area = false
        var id: String { name }
    }
    var series: [Series]
    var yDomain: ClosedRange<Double>?
    var height: CGFloat = 200

    var body: some View {
        Chart {
            ForEach(series) { s in
                ForEach(Array(s.points.enumerated()), id: \.offset) { _, p in
                    if s.area {
                        AreaMark(x: .value("Datum", p.0, unit: .day), y: .value(s.name, p.1), series: .value("Reihe", s.name))
                            .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Datum", p.0, unit: .day), y: .value(s.name, p.1), series: .value("Reihe", s.name))
                        .foregroundStyle(by: .value("Reihe", s.name))
                        .interpolationMethod(.monotone)
                        .symbol(.circle)
                        .symbolSize(18)
                }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartYScale(domain: yDomain ?? 0...10)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
        .frame(height: height)
    }
}
