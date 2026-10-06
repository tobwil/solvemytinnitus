import Accelerate
import AVFoundation
import Synchronization

/// FFT of the master output for the live spectrum (Hann window, 4096 points, log-spaced bins).
public final class SpectrumAnalyzer: @unchecked Sendable {
    public static let binCount = 72
    public static let minHz = 200.0
    public static let maxHz = 20000.0
    public static let floorDb: Float = -120

    private let n = 4096

    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private let window: [Float]
    private let latest = Mutex<[Float]>([Float](repeating: SpectrumAnalyzer.floorDb, count: SpectrumAnalyzer.binCount))

    public init() {
        dft = try? vDSP.DiscreteFourierTransform(count: n, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
    }

    /// Centre frequency of bin i.
    public static func frequency(ofBin i: Int) -> Double {
        minHz * pow(maxHz / minHz, (Double(i) + 0.5) / Double(binCount))
    }

    /// Latest magnitudes in dB (smoothed).
    public func bins() -> [Float] { latest.withLock { $0 } }

    public func reset() {
        latest.withLock { $0 = [Float](repeating: Self.floorDb, count: Self.binCount) }
    }

    func process(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let dft, let ch = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        var input = [Float](repeating: 0, count: n)
        let count = min(n, frames)
        // mix down to mono
        for c in 0..<Int(buffer.format.channelCount) {
            let p = ch[c]
            for i in 0..<count { input[i] += p[i] }
        }
        vDSP.multiply(input, window, result: &input)
        let zeros = [Float](repeating: 0, count: n)
        let res: (real: [Float], imaginary: [Float]) = dft.transform(real: input, imaginary: zeros)
        let re = res.real, im = res.imaginary
        var mags = [Float](repeating: 0, count: n / 2)
        let norm = Float(n) / 4
        for i in 0..<(n / 2) {
            let a: Float = re[i] * re[i]
            let b: Float = im[i] * im[i]
            mags[i] = (a + b).squareRoot() / norm
        }
        let rate = buffer.format.sampleRate > 0 ? buffer.format.sampleRate : sampleRate
        let hzPerBin = rate / Double(n)
        guard hzPerBin.isFinite, hzPerBin > 0 else { return }
        var out = [Float](repeating: Self.floorDb, count: Self.binCount)
        for b in 0..<Self.binCount {
            let lo = Self.minHz * pow(Self.maxHz / Self.minHz, Double(b) / Double(Self.binCount))
            let hi = Self.minHz * pow(Self.maxHz / Self.minHz, Double(b + 1) / Double(Self.binCount))
            let i0 = max(1, Int(lo / hzPerBin)), i1 = min(n / 2 - 1, max(i0, Int(hi / hzPerBin)))
            // bands above Nyquist (low sample rates) stay at the floor
            guard i0 <= i1 else { continue }
            var m: Float = 0
            for i in i0...i1 { m = max(m, mags[i]) }
            out[b] = max(Self.floorDb, 20 * log10(max(1e-9, m)))
        }
        latest.withLock { prev in
            for i in 0..<Self.binCount { prev[i] = prev[i] * 0.6 + out[i] * 0.4 }
        }
    }
}
