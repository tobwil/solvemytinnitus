import Foundation

// MARK: - Residual inhibition

public struct RISummary: Sendable, Hashable, Identifiable {
    public var stimulus: StimulusKind
    public var n: Int
    public var depth: Double
    public var duration: Double
    public var score: Double
    public var id: StimulusKind { stimulus }
}

public enum RIAnalysis {
    public struct TrialValues: Sendable {
        public var stimulus: StimulusKind
        public var depth: Double
        public var durationOfEffectS: Double
        public init(stimulus: StimulusKind, depth: Double, durationOfEffectS: Double) {
            self.stimulus = stimulus
            self.depth = depth
            self.durationOfEffectS = durationOfEffectS
        }
    }

    /// Ranking by depth × (1 + duration/60), as in the web app.
    public static func summarize(_ trials: [TrialValues]) -> [RISummary] {
        var map: [StimulusKind: [TrialValues]] = [:]
        for t in trials { map[t.stimulus, default: []].append(t) }
        return map.map { kind, ts in
            let depth = ts.reduce(0) { $0 + $1.depth } / Double(ts.count)
            let duration = ts.reduce(0) { $0 + $1.durationOfEffectS } / Double(ts.count)
            return RISummary(stimulus: kind, n: ts.count, depth: depth, duration: duration, score: depth * (1 + duration / 60))
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.stimulus.rawValue < $1.stimulus.rawValue }
    }

    public static func best(_ trials: [TrialValues]) -> RISummary? {
        guard let first = summarize(trials).first, first.depth > 0 else { return nil }
        return first
    }

    /// Stimulus with the fewest trials (random among ties) for blinded testing.
    public static func leastTested<G: RandomNumberGenerator>(_ trials: [StimulusKind], using g: inout G) -> StimulusKind {
        var counts = Dictionary(uniqueKeysWithValues: StimulusKind.allCases.map { ($0, 0) })
        for t in trials { counts[t, default: 0] += 1 }
        let minCount = counts.values.min() ?? 0
        let candidates = StimulusKind.allCases.filter { counts[$0] == minCount }
        return candidates.randomElement(using: &g) ?? .nbnThird
    }

    public static func leastTested(_ trials: [StimulusKind]) -> StimulusKind {
        var g = SystemRandomNumberGenerator()
        return leastTested(trials, using: &g)
    }

    /// Depth and duration of the effect from a rating curve sampled every 2 s.
    public static func evaluate(baseline: Double, curve: [Double], sampleIntervalS: Double = 2) -> (depth: Double, durationS: Double) {
        let c = curve.isEmpty ? [baseline] : curve
        let depth = max(0, baseline - (c.min() ?? baseline))
        guard depth > 0 else { return (0, 0) }
        var dur = Double(c.count) * sampleIntervalS
        for i in 1..<max(1, c.count) where c[i] >= baseline * 0.9 {
            dur = Double(i) * sampleIntervalS
            break
        }
        return (depth, dur)
    }

    public static func verdict(depth: Double) -> String {
        depth >= 3 ? "Starke Residual Inhibition." : depth >= 1 ? "Leichte Residual Inhibition." : "Keine messbare Unterdrückung mit diesem Klang."
    }

    /// Suggested stimulus level: MML + 10 dB, never above −8 dBFS.
    public static func suggestedLevel(mmlDb: Double?, loudnessDb: Double) -> Double {
        min(-8, (mmlDb ?? loudnessDb) + 10)
    }
}

// MARK: - Spectrum

public enum SpectrumAnalysis {
    /// Shown when test tones were marked "nicht hörbar".
    public static let inaudibleExplanation = "Wenn du einen Ton nicht hörst, hat das meist einen von zwei Gründen: Dein Gehör ist in diesem Bereich schwächer, oder dein Tinnitus überdeckt den Ton. Beides spricht dafür, dass dein Tinnitus genau dort oder knapp daneben liegt – er sitzt typischerweise am Rand eines Hörverlusts. Ein sicherer Beweis ist es nicht; die Feinabstimmung und der Hörcheck klären das genauer."

    /// Inaudible frequencies next to the likeness peak point to the tinnitus region.
    public static func inaudibleHint(inaudible: Set<Double>, peak: Double) -> String? {
        guard !inaudible.isEmpty else { return nil }
        let list = inaudible.sorted().map(Format.hz).joined(separator: ", ")
        let near = inaudible.contains { abs(log2($0 / peak)) <= 0.6 }
        return "Nicht hörbar: \(list). " + (near
            ? "Das liegt direkt neben deinem Ähnlichkeits-Gipfel bei \(Format.hz(peak)) – ein starker Hinweis auf deine Tinnitus-Region. "
            : "") + inaudibleExplanation
    }

    public static let frequencies: [Double] = [1000, 2000, 3000, 4000, 5000, 6000, 8000, 10000, 12000, 14000, 16000]
    public static let repetitions = 2

    public struct Result: Sendable {
        public var points: [SpectrumPoint]
        public var peak: Double
        /// Mean absolute difference between repetitions (lower = more consistent).
        public var consistency: Double
        /// Peak minus mean of all but the top three.
        public var sharpness: Double
        public var shapeLabel: String {
            sharpness > 4 ? "tonal, schmalbandig" : sharpness > 2 ? "mittelbreit" : "breitbandig"
        }
    }

    public static func evaluate(_ ratings: [Double: [Double]]) -> Result {
        let points = frequencies.map { SpectrumPoint(freq: $0, value: Stats.mean(ratings[$0] ?? [0])) }
        let top = points.max { $0.value < $1.value } ?? points[0]
        let diffs = frequencies.map { f -> Double in
            let r = ratings[f] ?? []
            return r.count > 1 ? abs(r[0] - r[1]) : 0
        }
        let sorted = points.sorted { $0.value > $1.value }
        let sharp = sorted[0].value - Stats.mean(sorted.dropFirst(3).map(\.value))
        return Result(points: points, peak: top.freq, consistency: Stats.mean(diffs), sharpness: sharp)
    }
}

// MARK: - Pitch match

public enum MatchAnalysis {
    public static let fMin = 500.0
    public static let fMax = 18000.0

    public static func octaveDistance(_ a: Double, _ b: Double) -> Double { abs(log2(a / b)) }

    public static func combine(trials: [Double]) -> (freq: Double, spreadOctaves: Double) {
        let f = Stats.geoMedian(trials)
        let spread = trials.map { octaveDistance($0, f) }.max() ?? 0
        return (f, spread)
    }

    /// Independent start point for each trial: random offset up to ±0.75 octave.
    public static func jitteredStart<G: RandomNumberGenerator>(_ start: Double, using g: inout G) -> Double {
        min(fMax, max(fMin, start * pow(2, (Double.random(in: 0..<1, using: &g) - 0.5) * 1.5)))
    }

    /// Octave candidates for the octave-confusion check.
    public static func octaveCandidates(_ f: Double) -> [Double] {
        [f / 2, f, f * 2].filter { $0 >= fMin && $0 <= fMax }
    }

    /// Frequency on a log axis (pad position 0…1).
    public static func freq(at x: Double, fMin: Double = fMin, fMax: Double = fMax) -> Double {
        fMin * pow(fMax / fMin, min(1, max(0, x)))
    }

    public static func position(of f: Double, fMin: Double = fMin, fMax: Double = fMax) -> Double {
        log(f / fMin) / log(fMax / fMin)
    }
}

// MARK: - Hearing threshold

/// Simplified Hughson-Westlake (down 10 / up 5); threshold = level heard twice on ascending runs.
public struct HearingStaircase: Sendable {
    public static let frequencies: [Double] = [500, 1000, 2000, 3000, 4000, 6000, 8000, 10000, 12000, 14000, 16000]
    /// Frequencies the own test covers when an Apple audiogram (≤ 8 kHz) was imported.
    public static let highFrequencies: [Double] = [10000, 12000, 14000, 16000]
    public static let start = -40.0
    public static let minLevel = -95.0
    public static let maxLevel = -6.0

    public let frequencies: [Double]
    public private(set) var index = 0
    public private(set) var level = HearingStaircase.start
    public private(set) var results: [HearingPoint] = []
    private var heard: [Double] = []
    private var presentations = 0

    public init(frequencies: [Double] = HearingStaircase.frequencies) {
        self.frequencies = frequencies
    }

    public var isDone: Bool { index >= frequencies.count }
    public var currentFrequency: Double? { isDone ? nil : frequencies[index] }

    /// Returns true if the frequency changed.
    @discardableResult
    public mutating func answer(heard ok: Bool) -> Bool {
        guard !isDone else { return false }
        presentations += 1
        // safety net for inconsistent answers: take the lowest level heard so far
        if presentations >= 14 {
            next(heard.min() ?? Self.maxLevel)
            return true
        }
        if ok {
            heard.append(level)
            if heard.filter({ $0 == level }).count >= 2 || level <= Self.minLevel {
                next(level)
                return true
            }
            level = max(Self.minLevel, level - 10)
        } else {
            level += 5
            if level >= Self.maxLevel {
                next(Self.maxLevel)
                return true
            }
        }
        return false
    }

    private mutating func next(_ threshold: Double) {
        results.append(HearingPoint(freq: frequencies[index], level: threshold))
        index += 1
        heard = []
        presentations = 0
        level = Self.start
    }
}

public enum HearingAnalysis {
    /// Edge of a high-frequency hearing loss: the frequency where the threshold rises most steeply
    /// (per octave). Tinnitus pitch typically lies at or just above this edge (Noreña et al. 2002).
    public static func lossEdge(_ pts: [HearingPoint], minSlope: Double = 10) -> Double? {
        let s = pts.sorted { $0.freq < $1.freq }
        guard s.count >= 3 else { return nil }
        var best: (f: Double, slope: Double)?
        for (a, b) in zip(s, s.dropFirst()) {
            let slope = (b.level - a.level) / max(0.1, log2(b.freq / a.freq))
            if slope >= minSlope, slope > (best?.slope ?? -.infinity) { best = (sqrt(a.freq * b.freq), slope) }
        }
        return best?.f
    }

    /// Frequencies where nothing was heard up to the maximum test level.
    public static func notHeard(_ pts: [HearingPoint], maxLevel: Double = HearingStaircase.maxLevel) -> [Double] {
        pts.filter { $0.level >= maxLevel }.map(\.freq).sorted()
    }

    public static func edgeHint(edge: Double, tinnitus: Double?) -> String {
        if let t = tinnitus, abs(log2(t / edge)) <= 0.75 {
            return "Dein Hörprofil fällt ab etwa \(Format.hz(edge)) deutlich ab, und dein Tinnitus liegt mit \(Format.hz(t)) genau an dieser Kante. Das ist typisch: Das Gehirn verstärkt dort, wo Signale aus dem Ohr fehlen. Klänge im Bereich davor wirken bei vielen am besten."
        }
        return "Dein Hörprofil fällt ab etwa \(Format.hz(edge)) deutlich ab. Tinnitus sitzt typischerweise an oder knapp über dieser Kante – prüfe mit der Feinabstimmung, ob deiner dort liegt."
    }

    /// High-frequency drop: mean(≥ 8 kHz) − mean(≤ 2 kHz), in dB. Positive = worse in the highs.
    /// Levels are relative thresholds (higher = worse).
    public static func highFrequencyDrop(_ pts: [HearingPoint]) -> Double? {
        let hi = pts.filter { $0.freq >= 8000 }.map(\.level)
        let lo = pts.filter { $0.freq <= 2000 }.map(\.level)
        guard !hi.isEmpty, !lo.isEmpty else { return nil }
        return Stats.mean(hi) - Stats.mean(lo)
    }

    /// Merge an Apple audiogram (dB HL, 250 Hz–8 kHz) with the app's own high-frequency thresholds.
    /// The app's relative values are shifted so they meet the audiogram at the overlap (8 kHz) if both
    /// exist there; otherwise they are kept as is and flagged as relative by the caller.
    public static func merge(appleHL: [HearingPoint], app: [HearingPoint]) -> [HearingPoint] {
        guard !appleHL.isEmpty else { return app }
        let high = app.filter { $0.freq > 8000 }
        var offset = 0.0
        if let a8 = appleHL.first(where: { $0.freq == 8000 }), let o8 = app.first(where: { $0.freq == 8000 }) {
            offset = a8.level - o8.level
        } else if let aLast = appleHL.max(by: { $0.freq < $1.freq }), let oFirst = high.min(by: { $0.freq < $1.freq }) {
            offset = aLast.level - oFirst.level
        }
        return (appleHL + high.map { HearingPoint(freq: $0.freq, level: $0.level + offset) }).sorted { $0.freq < $1.freq }
    }

    /// Apple audiograms are in dB HL (0 = normal, higher = worse). Our relative scale is "dBFS needed",
    /// where higher (less negative) is also worse, so both plot the same way.
    public static let hearingAidHint = "Hörgeräte gehören zu den am besten belegten Tinnitus-Maßnahmen, wenn ein Hörverlust vorliegt (UNITI-Studie 2025, S3-Leitlinie). Lass beim HNO ein Tonaudiogramm inklusive Hochtonbereich bis 16 kHz machen. AirPods Pro 2/3 haben eine Hörgerätefunktion für leichten bis mittleren Hörverlust (Einstellungen › AirPods)."
}

// MARK: - Somatic

public enum SomaticAnalysis {
    public static func isSomatic(_ results: [SomaticResult]) -> Bool {
        results.contains { $0.change != 0 }
    }
}
