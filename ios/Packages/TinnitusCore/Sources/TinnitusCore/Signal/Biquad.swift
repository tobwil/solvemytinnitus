import Foundation

/// Normalised biquad coefficients (a0 = 1), RBJ Audio EQ Cookbook. Q is linear (not dB as in Web Audio).
public struct BiquadCoefficients: Sendable, Equatable {
    public var b0, b1, b2, a1, a2: Double

    public enum Kind: Sendable { case lowpass, highpass, bandpass, peaking(gainDb: Double) }

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    public init(_ kind: Kind, frequency: Double, q: Double, sampleRate: Double) {
        let f = min(max(frequency, 10), sampleRate * 0.49)
        let w0 = 2 * Double.pi * f / sampleRate
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * q)
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
        switch kind {
        case .lowpass:
            b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .highpass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .bandpass:
            // constant 0 dB peak gain (like Web Audio's bandpass)
            b0 = alpha; b1 = 0; b2 = -alpha
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .peaking(let gainDb):
            let A = pow(10, gainDb / 40)
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        }
        self.init(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Complex response magnitude at frequency f.
    public func magnitude(at f: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * f / sampleRate
        let (re, im) = response(w)
        return sqrt(re * re + im * im)
    }

    /// H(e^{jw}) as (re, im).
    public func response(_ w: Double) -> (Double, Double) {
        // numerator b0 + b1 z^-1 + b2 z^-2, z^-1 = e^{-jw}
        let c1 = cos(w), s1 = -sin(w), c2 = cos(2 * w), s2 = -sin(2 * w)
        let nr = b0 + b1 * c1 + b2 * c2
        let ni = b1 * s1 + b2 * s2
        let dr = 1 + a1 * c1 + a2 * c2
        let di = a1 * s1 + a2 * s2
        let den = dr * dr + di * di
        return ((nr * dr + ni * di) / den, (ni * dr - nr * di) / den)
    }
}

/// Transposed direct form II biquad state.
public struct Biquad: Sendable {
    public var c: BiquadCoefficients
    private var z1 = 0.0, z2 = 0.0

    public init(_ c: BiquadCoefficients) { self.c = c }

    @inline(__always)
    public mutating func process(_ x: Double) -> Double {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }

    public mutating func reset() { z1 = 0; z2 = 0 }
}

/// Cascade of biquads.
public struct BiquadChain: Sendable {
    public var stages: [Biquad]
    public init(_ coefficients: [BiquadCoefficients]) { stages = coefficients.map(Biquad.init) }

    @inline(__always)
    public mutating func process(_ x: Double) -> Double {
        var v = x
        for i in stages.indices { v = stages[i].process(v) }
        return v
    }

    public mutating func update(_ coefficients: [BiquadCoefficients]) {
        for i in stages.indices where i < coefficients.count { stages[i].c = coefficients[i] }
    }

    /// Complex response of the whole cascade.
    public static func response(_ coefficients: [BiquadCoefficients], w: Double) -> (Double, Double) {
        var re = 1.0, im = 0.0
        for c in coefficients {
            let (r, i) = c.response(w)
            (re, im) = (re * r - im * i, re * i + im * r)
        }
        return (re, im)
    }
}

/// Filter designs used by the sound recipes (05-audio-engine).
public enum FilterDesign {
    /// Q values of an 8th-order Butterworth as four biquads.
    public static let butterworth8Q: [Double] = [0.5098, 0.6013, 0.8999, 2.5629]

    public static func clampFreq(_ f: Double, sampleRate: Double) -> Double {
        min(sampleRate / 2 - 500, max(100, f))
    }

    /// Band-stop as parallel 8th-order Butterworth low-pass at f·2^(−w/2) and high-pass at f·2^(w/2).
    public static func notch(center: Double, widthOctaves: Double, sampleRate: Double) -> (lp: [BiquadCoefficients], hp: [BiquadCoefficients]) {
        let half = pow(2, widthOctaves / 2)
        let lo = clampFreq(center / half, sampleRate: sampleRate)
        let hi = clampFreq(center * half, sampleRate: sampleRate)
        return (
            butterworth8Q.map { BiquadCoefficients(.lowpass, frequency: lo, q: $0, sampleRate: sampleRate) },
            butterworth8Q.map { BiquadCoefficients(.highpass, frequency: hi, q: $0, sampleRate: sampleRate) }
        )
    }

    /// Magnitude of the parallel notch in dB.
    public static func notchResponseDb(at f: Double, center: Double, widthOctaves: Double, sampleRate: Double) -> Double {
        let n = notch(center: center, widthOctaves: widthOctaves, sampleRate: sampleRate)
        let w = 2 * Double.pi * f / sampleRate
        let a = BiquadChain.response(n.lp, w: w)
        let b = BiquadChain.response(n.hp, w: w)
        let re = a.0 + b.0, im = a.1 + b.1
        return 20 * log10(max(1e-12, sqrt(re * re + im * im)))
    }

    /// Bandpass Q for a bandwidth in octaves (same formula as the web app).
    public static func bandpassQ(widthOctaves: Double) -> Double {
        let p = pow(2, widthOctaves)
        return sqrt(p) / (p - 1)
    }

    /// Makeup gain for two cascaded bandpasses on white noise (web app formula, capped at 30×).
    public static func narrowbandMakeup(center: Double, widthOctaves: Double, sampleRate: Double) -> Double {
        let q = bandpassQ(widthOctaves: widthOctaves)
        let bw = center / q
        return min(30, sqrt((sampleRate / 2) / bw) * 1.3)
    }
}
