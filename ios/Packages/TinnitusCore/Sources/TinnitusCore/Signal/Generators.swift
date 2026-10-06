import Foundation

/// Allocation-free PRNG usable on the audio render thread (xorshift128+).
public struct FastRandom: RandomNumberGenerator, Sendable {
    private var s0: UInt64
    private var s1: UInt64

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        s0 = seed | 1
        s1 = 0x9E37_79B9_7F4A_7C15 ^ seed
        for _ in 0..<8 { _ = next() }
    }

    @inline(__always)
    public mutating func next() -> UInt64 {
        var x = s0
        let y = s1
        s0 = y
        x ^= x << 23
        s1 = x ^ y ^ (x >> 17) ^ (y >> 26)
        return s1 &+ y
    }

    /// Uniform in [-1, 1).
    @inline(__always)
    public mutating func bipolar() -> Double {
        Double(next() >> 11) * (2.0 / Double(1 << 53)) - 1
    }
}

public enum NoiseColor: String, Codable, Sendable, CaseIterable {
    case white, pink, brown
}

/// White, pink (Paul Kellet, as in the web app) and brown noise.
public struct NoiseGenerator: Sendable {
    public let color: NoiseColor
    private var rng: FastRandom
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
    private var last = 0.0

    public init(_ color: NoiseColor, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.color = color
        rng = FastRandom(seed: seed)
    }

    @inline(__always)
    public mutating func next() -> Double {
        let w = rng.bipolar()
        switch color {
        case .white:
            return w
        case .pink:
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.969 * b2 + w * 0.153852
            b3 = 0.8665 * b3 + w * 0.3104856
            b4 = 0.55 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.016898
            let out = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
            b6 = w * 0.115926
            return out
        case .brown:
            last = (last + 0.02 * w) / 1.02
            return last * 3.5
        }
    }
}

/// Sine oscillator with phase accumulator.
public struct Oscillator: Sendable {
    public var frequency: Double
    private var phase = 0.0

    public init(frequency: Double, phase: Double = 0) {
        self.frequency = frequency
        self.phase = phase
    }

    @inline(__always)
    public mutating func next(sampleRate: Double) -> Double {
        let v = sin(2 * Double.pi * phase)
        phase += frequency / sampleRate
        if phase >= 1 { phase -= floor(phase) }
        return v
    }
}

/// One-pole smoother for click-free parameter changes.
public struct Smoother: Sendable {
    public var value: Double
    public var target: Double
    private var coeff: Double

    public init(value: Double, timeConstantS: Double, sampleRate: Double) {
        self.value = value
        target = value
        coeff = timeConstantS <= 0 ? 0 : exp(-1 / (timeConstantS * sampleRate))
    }

    public mutating func setTimeConstant(_ s: Double, sampleRate: Double) {
        coeff = s <= 0 ? 0 : exp(-1 / (s * sampleRate))
    }

    @inline(__always)
    public mutating func next() -> Double {
        value = target + (value - target) * coeff
        return value
    }
}

/// Linear gain ramp (start → end over N samples). Used for fades with exact duration.
public struct LinearRamp: Sendable {
    public private(set) var value: Double
    private var step = 0.0
    private var remaining = 0

    public init(value: Double) { self.value = value }

    public mutating func ramp(to target: Double, samples: Int) {
        guard samples > 0 else { value = target; remaining = 0; return }
        step = (target - value) / Double(samples)
        remaining = samples
    }

    public var isRamping: Bool { remaining > 0 }

    @inline(__always)
    public mutating func next() -> Double {
        if remaining > 0 {
            value += step
            remaining -= 1
        }
        return value
    }
}

public enum Level {
    @inline(__always)
    public static func dbToGain(_ db: Double) -> Double { pow(10, db / 20) }
    @inline(__always)
    public static func gainToDb(_ g: Double) -> Double { 20 * log10(max(1e-9, g)) }
}
