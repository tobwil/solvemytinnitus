import Foundation

public enum Stats {
    public static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    /// Geometric median-ish: median in log space (used for pitch-match trials).
    public static func geoMedian(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let logs = xs.map { log2($0) }.sorted()
        let m = logs.count / 2
        let v = logs.count % 2 == 1 ? logs[m] : (logs[m - 1] + logs[m]) / 2
        return pow(2, v)
    }

    public struct Interval: Sendable, Equatable {
        public var mean: Double
        public var lo: Double
        public var hi: Double
    }

    /// Mean and approximate 95 % CI (t ≈ 2.26 for n < 10, else 2), as in the web app.
    public static func ci(_ xs: [Double]) -> Interval {
        let m = mean(xs)
        guard xs.count >= 2 else { return Interval(mean: m, lo: m, hi: m) }
        let sd = sqrt(xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1))
        let t = xs.count < 10 ? 2.26 : 2
        let se = t * sd / sqrt(Double(xs.count))
        return Interval(mean: m, lo: m - se, hi: m + se)
    }

    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double {
        guard xs.count == ys.count, xs.count > 1 else { return 0 }
        let mx = mean(xs), my = mean(ys)
        var n = 0.0, dx = 0.0, dy = 0.0
        for i in xs.indices {
            n += (xs[i] - mx) * (ys[i] - my)
            dx += (xs[i] - mx) * (xs[i] - mx)
            dy += (ys[i] - my) * (ys[i] - my)
        }
        return dx > 0 && dy > 0 ? n / sqrt(dx * dy) : 0
    }

    public static func correlationLabel(_ r: Double) -> String {
        switch abs(r) {
        case ..<0.2: "kein Zusammenhang"
        case ..<0.4: "schwach"
        case ..<0.6: "mittel"
        default: "stark"
        }
    }
}

public enum Day {
    /// YYYY-MM-DD in the current calendar (matches the web app's `dayKey`).
    public static func key(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    public static func daysAgo(_ n: Int, from date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -n, to: date) ?? date
    }
}

public enum Format {
    /// "6,00 kHz" / "12,5 kHz" / "500 Hz" in German style.
    public static func hz(_ f: Double) -> String {
        let (v, u) = hzParts(f)
        return "\(v) \(u)"
    }

    public static func hzParts(_ f: Double) -> (String, String) {
        if f >= 1000 {
            let digits = f >= 10000 ? 1 : 2
            return (decimal(f / 1000, digits: digits), "kHz")
        }
        return ("\(Int(f.rounded()))", "Hz")
    }

    public static func decimal(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "de_DE")))
    }

    public static func signed(_ v: Double, digits: Int = 1) -> String {
        (v > 0 ? "+" : v < 0 ? "−" : "") + decimal(abs(v), digits: digits)
    }

    /// "m:ss"
    public static func duration(_ s: Double) -> String {
        let t = max(0, Int(s.rounded()))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    public static func db(_ v: Double) -> String { "\(Int(v.rounded())) dB" }
}
