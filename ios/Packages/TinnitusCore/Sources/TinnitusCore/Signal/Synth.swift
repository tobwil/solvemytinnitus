import Foundation
import Synchronization

/// Sound recipes, identical to the web app (see docs/ios/05-audio-engine.md).
public enum Recipe: Sendable, Equatable {
    case tone(freq: Double)
    /// 100 % AM at `modHz`, RMS-equalised ×1.22.
    case amTone(freq: Double, modHz: Double = 10)
    /// White noise through two cascaded bandpasses with makeup gain.
    case narrowband(freq: Double, widthOctaves: Double)
    case noise(NoiseColor)
    case notchedNoise(NoiseColor, center: Double, widthOctaves: Double)
    /// Pink → HP 400 Hz → slow 0.13 Hz level modulation.
    case rain
    case notchedRain(center: Double, widthOctaves: Double)
    /// Pink → peaking +9 dB, Q 0.7 at f_T → 10 Hz AM with 40 % depth (Sendesen 2026).
    case amNoise(center: Double, modHz: Double = 10)
    /// Pulsed tone train for threshold testing; finishes by itself.
    case toneBursts(freq: Double, count: Int = 3, onMs: Double = 200, offMs: Double = 150)
    /// Acoustic coordinated reset (Tass 2012).
    case cr(ft: Double, cycleHz: Double = 1.5, onCycles: Int = 3, offCycles: Int = 2, toneMs: Double = 150)
    /// Soft bell used as a cue; finishes by itself.
    case chime

    public var finishesByItself: Bool {
        switch self {
        case .toneBursts, .chime: true
        default: false
        }
    }

    /// The four CR frequencies relative to f_T.
    public static let crRatios: [Double] = [0.766, 0.9, 1.1, 1.395]

    public static func stimulus(_ kind: StimulusKind, freq: Double, notchWidth: Double) -> Recipe {
        switch kind {
        case .tone: .tone(freq: freq)
        case .amTone: .amTone(freq: freq)
        case .nbnThird: .narrowband(freq: freq, widthOctaves: 1.0 / 3)
        case .nbnOctave: .narrowband(freq: freq, widthOctaves: 1)
        case .bbn: .noise(.white)
        case .notchedBbn: .notchedNoise(.white, center: freq, widthOctaves: notchWidth)
        }
    }
}

/// Lock-free control surface shared between UI and render thread.
public final class VoiceControl: Sendable {
    private let _level = Atomic<UInt64>(0)
    private let _freq = Atomic<UInt64>(0)
    private let _stopFadeMs = Atomic<UInt64>(0)
    private let _stop = Atomic<Bool>(false)
    private let _finished = Atomic<Bool>(false)
    private let _cap = Atomic<UInt64>(0)

    public init(levelDb: Double, freq: Double = 0, capDb: Double = -6) {
        _level.store(levelDb.bitPattern, ordering: .relaxed)
        _freq.store(freq.bitPattern, ordering: .relaxed)
        _cap.store(capDb.bitPattern, ordering: .relaxed)
    }

    public var levelDb: Double {
        get { Double(bitPattern: _level.load(ordering: .relaxed)) }
        set { _level.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Target frequency for gliding recipes (tone, narrowband). 0 = unchanged.
    public var frequency: Double {
        get { Double(bitPattern: _freq.load(ordering: .relaxed)) }
        set { _freq.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Hard ceiling in dBFS for this voice (hearing protection).
    public var capDb: Double {
        get { Double(bitPattern: _cap.load(ordering: .relaxed)) }
        set { _cap.store(newValue.bitPattern, ordering: .relaxed) }
    }

    public func stop(fadeMs: Double = 30) {
        _stopFadeMs.store(fadeMs.bitPattern, ordering: .relaxed)
        _stop.store(true, ordering: .releasing)
    }

    public var stopRequested: Bool { _stop.load(ordering: .acquiring) }
    var stopFadeMs: Double { Double(bitPattern: _stopFadeMs.load(ordering: .relaxed)) }

    public var isFinished: Bool { _finished.load(ordering: .acquiring) }
    func markFinished() { _finished.store(true, ordering: .releasing) }
}

/// Mono DSP for one recipe. Owned by the render thread; talks to the UI through `VoiceControl`.
public struct SynthVoice: Sendable {
    public let recipe: Recipe
    public let sampleRate: Double
    public let control: VoiceControl

    private var gain: LinearRamp
    private var levelSmoother: Smoother
    private var lastLevelDb: Double
    private var stopping = false
    private var finished = false
    private var t = 0 // samples rendered

    // generators / filters (only the ones a recipe needs are used)
    private var osc = Oscillator(frequency: 1000)
    private var mod = Oscillator(frequency: 10)
    private var noise: NoiseGenerator
    private var bp = BiquadChain([])
    private var lp = BiquadChain([])
    private var hp = BiquadChain([])
    private var freqSmoother: Smoother
    private var currentFreq: Double
    private var makeup = 1.0
    private var widthOctaves = 1.0
    private var coeffCountdown = 0
    // CR
    private var crFreqs: [Double] = []
    private var crOrder: [Int] = [0, 1, 2, 3]
    private var crRng = FastRandom()
    private var crCycle = 0
    private var crPos = 0
    private var chimeOsc: [Oscillator] = []

    public init(recipe: Recipe, sampleRate: Double, control: VoiceControl) {
        self.recipe = recipe
        self.sampleRate = sampleRate
        self.control = control
        let fs = sampleRate
        gain = LinearRamp(value: 0)
        levelSmoother = Smoother(value: Level.dbToGain(min(control.levelDb, control.capDb)), timeConstantS: 0.01, sampleRate: fs)
        lastLevelDb = control.levelDb
        var startFreq = 1000.0
        var color = NoiseColor.white
        switch recipe {
        case .tone(let f), .amTone(let f, _), .toneBursts(let f, _, _, _):
            startFreq = f
        case .narrowband(let f, let w):
            startFreq = f
            widthOctaves = w
        case .noise(let c):
            color = c
        case .notchedNoise(let c, let f, let w):
            color = c
            startFreq = f
            widthOctaves = w
        case .rain:
            color = .pink
        case .notchedRain(let f, let w):
            color = .pink
            startFreq = f
            widthOctaves = w
        case .amNoise(let f, _):
            color = .pink
            startFreq = f
        case .cr(let ft, _, _, _, _):
            startFreq = ft
        case .chime:
            break
        }
        startFreq = FilterDesign.clampFreq(startFreq, sampleRate: fs)
        currentFreq = startFreq
        freqSmoother = Smoother(value: startFreq, timeConstantS: 0.01, sampleRate: fs)
        noise = NoiseGenerator(color)
        osc = Oscillator(frequency: startFreq)

        switch recipe {
        case .amTone(_, let m), .amNoise(_, let m):
            mod = Oscillator(frequency: m)
        case .rain, .notchedRain:
            mod = Oscillator(frequency: 0.13)
        default:
            break
        }
        switch recipe {
        case .narrowband(let f, let w):
            let q = FilterDesign.bandpassQ(widthOctaves: w)
            let c = BiquadCoefficients(.bandpass, frequency: startFreq, q: q, sampleRate: fs)
            bp = BiquadChain([c, c])
            makeup = FilterDesign.narrowbandMakeup(center: f, widthOctaves: w, sampleRate: fs)
        case .notchedNoise(_, let f, let w), .notchedRain(let f, let w):
            let n = FilterDesign.notch(center: f, widthOctaves: w, sampleRate: fs)
            lp = BiquadChain(n.lp)
            hp = BiquadChain(n.hp)
            if case .notchedRain = recipe {
                bp = BiquadChain([BiquadCoefficients(.highpass, frequency: 400, q: 0.7071, sampleRate: fs)])
            }
        case .rain:
            bp = BiquadChain([BiquadCoefficients(.highpass, frequency: 400, q: 0.7071, sampleRate: fs)])
        case .amNoise:
            bp = BiquadChain([BiquadCoefficients(.peaking(gainDb: 9), frequency: startFreq, q: 0.7, sampleRate: fs)])
        case .cr(let ft, _, _, _, _):
            crFreqs = Recipe.crRatios.map { FilterDesign.clampFreq(ft * $0, sampleRate: fs) }
            crOrder.shuffle(using: &crRng)
        case .chime:
            chimeOsc = [528, 1056, 1584].map { Oscillator(frequency: $0) }
        default:
            break
        }
        // 20 ms fade-in like the web app's RAMP (bursts and CR shape themselves)
        gain.ramp(to: 1, samples: Int(0.02 * fs))
    }

    public var isFinished: Bool { finished }

    /// Renders `frames` mono samples, *adding* nothing: overwrites `out`.
    public mutating func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        if finished {
            out.update(repeating: 0, count: frames)
            return
        }
        // control-rate updates
        let lvl = min(control.levelDb, control.capDb)
        if lvl != lastLevelDb {
            lastLevelDb = lvl
            levelSmoother.target = Level.dbToGain(lvl)
        }
        let f = control.frequency
        if f > 0 { freqSmoother.target = FilterDesign.clampFreq(f, sampleRate: sampleRate) }
        if control.stopRequested && !stopping {
            stopping = true
            gain.ramp(to: 0, samples: max(1, Int(control.stopFadeMs / 1000 * sampleRate)))
        }

        for i in 0..<frames {
            let s = nextSample()
            let g = gain.next() * levelSmoother.next()
            out[i] = Float(s * g)
            t += 1
        }
        if stopping && !gain.isRamping {
            finish()
        }
        if recipe.finishesByItself && t >= selfDurationSamples {
            finish()
        }
    }

    private mutating func finish() {
        finished = true
        control.markFinished()
    }

    private var selfDurationSamples: Int {
        switch recipe {
        case .toneBursts(_, let count, let on, let off):
            return Int((0.02 + Double(count) * (on + off) / 1000 + 0.1) * sampleRate)
        case .chime:
            return Int(2.3 * sampleRate)
        default:
            return .max
        }
    }

    @inline(__always)
    private mutating func glide() {
        let nf = freqSmoother.next()
        if abs(nf - currentFreq) > 0.01 {
            currentFreq = nf
            osc.frequency = nf
            coeffCountdown -= 1
            if coeffCountdown <= 0, case .narrowband(_, let w) = recipe {
                // recompute filter every 32 samples while gliding
                coeffCountdown = 32
                let c = BiquadCoefficients(.bandpass, frequency: nf, q: FilterDesign.bandpassQ(widthOctaves: w), sampleRate: sampleRate)
                bp.update([c, c])
                makeup = FilterDesign.narrowbandMakeup(center: nf, widthOctaves: w, sampleRate: sampleRate)
            }
        }
    }

    @inline(__always)
    private mutating func nextSample() -> Double {
        let fs = sampleRate
        switch recipe {
        case .tone:
            glide()
            return osc.next(sampleRate: fs)
        case .amTone:
            glide()
            let c = osc.next(sampleRate: fs)
            let m = 0.5 + 0.5 * mod.next(sampleRate: fs)
            return c * m * 1.22
        case .narrowband:
            glide()
            return bp.process(noise.next()) * makeup
        case .noise:
            return noise.next()
        case .notchedNoise:
            let x = noise.next()
            return lp.process(x) + hp.process(x)
        case .rain:
            let x = bp.process(noise.next())
            return x * (0.8 + 0.2 * mod.next(sampleRate: fs))
        case .notchedRain:
            let x = bp.process(noise.next()) * (0.8 + 0.2 * mod.next(sampleRate: fs))
            return lp.process(x) + hp.process(x)
        case .amNoise:
            let x = bp.process(noise.next())
            return x * (0.6 + 0.4 * mod.next(sampleRate: fs))
        case .toneBursts(_, let count, let onMs, let offMs):
            let v = osc.next(sampleRate: fs)
            let start = Int(0.02 * fs)
            let pos = t - start
            if pos < 0 { return 0 }
            let period = Int((onMs + offMs) / 1000 * fs)
            let k = pos / max(1, period)
            if k >= count { return 0 }
            let p = Double(pos % max(1, period)) / fs
            let on = onMs / 1000
            return v * Self.envelope(p, length: on, ramp: 0.01)
        case .cr(_, let cycleHz, let onCycles, let offCycles, let toneMs):
            return crSample(cycleHz: cycleHz, onCycles: onCycles, offCycles: offCycles, toneMs: toneMs)
        case .chime:
            let ts = Double(t) / fs
            let env: Double
            if ts < 0.01 { env = ts / 0.01 } else { env = exp(log(0.0001) * (ts - 0.01) / 2.19) }
            let gains = [1.0, 0.35, 0.12]
            var s = 0.0
            for i in chimeOsc.indices { s += chimeOsc[i].next(sampleRate: fs) * gains[i] }
            return s * env
        }
    }

    /// Trapezoid envelope with linear ramps.
    @inline(__always)
    static func envelope(_ p: Double, length: Double, ramp: Double) -> Double {
        if p < 0 || p >= length { return 0 }
        if p < ramp { return p / ramp }
        if p > length - ramp { return (length - p) / ramp }
        return 1
    }

    @inline(__always)
    private mutating func crSample(cycleHz: Double, onCycles: Int, offCycles: Int, toneMs: Double) -> Double {
        let fs = sampleRate
        let cycleLen = Int(fs / cycleHz)
        if crPos >= cycleLen {
            crPos = 0
            crCycle += 1
            crOrder.shuffle(using: &crRng)
        }
        defer { crPos += 1 }
        let period = onCycles + offCycles
        guard crCycle % period < onCycles else { return 0 }
        let slotLen = cycleLen / 4
        let slot = min(3, crPos / slotLen)
        let tonePos = crPos - slot * slotLen
        let toneLen = min(Double(slotLen) * 0.9, toneMs / 1000 * fs)
        let p = Double(tonePos) / fs
        if tonePos == 0 { osc = Oscillator(frequency: crFreqs[crOrder[slot]]) }
        let env = Self.envelope(p, length: toneLen / fs, ramp: 0.01)
        let v = osc.next(sampleRate: fs)
        return env == 0 ? 0 : v * env
    }

    /// CR state for tests: (cycle index, current slot order).
    public var crDebug: (cycle: Int, order: [Int], freqs: [Double]) { (crCycle, crOrder, crFreqs) }
}

/// Offline renderer used by tests and to pre-render music through the notch.
public enum OfflineRender {
    public static func render(_ recipe: Recipe, levelDb: Double = 0, seconds: Double, sampleRate: Double = 48000, capDb: Double = 0) -> [Float] {
        let control = VoiceControl(levelDb: levelDb, capDb: capDb)
        var v = SynthVoice(recipe: recipe, sampleRate: sampleRate, control: control)
        let n = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: n)
        out.withUnsafeMutableBufferPointer { buf in
            var i = 0
            while i < n {
                let k = min(512, n - i)
                v.render(into: buf.baseAddress! + i, frames: k)
                i += k
            }
        }
        return out
    }

    /// Applies the 8th-order parallel notch to an arbitrary mono signal (e.g. decoded music).
    public static func notch(_ input: [Float], center: Double, widthOctaves: Double, sampleRate: Double) -> [Float] {
        let n = FilterDesign.notch(center: center, widthOctaves: widthOctaves, sampleRate: sampleRate)
        var lp = BiquadChain(n.lp)
        var hp = BiquadChain(n.hp)
        return input.map { x in
            let d = Double(x)
            return Float(lp.process(d) + hp.process(d))
        }
    }

    public static func rms(_ xs: ArraySlice<Float>) -> Double {
        guard !xs.isEmpty else { return 0 }
        return sqrt(xs.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(xs.count))
    }
}
