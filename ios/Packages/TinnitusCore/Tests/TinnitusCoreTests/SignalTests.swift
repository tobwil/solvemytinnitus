import Foundation
import Testing
@testable import TinnitusCore

@Suite("Signal")
struct SignalTests {
    let fs = 48000.0

    @Test("Notch: −3 dB at the edges, ≈ −24 dB in the middle, 0 dB passband", arguments: [4000.0, 6000.0, 8000.0, 12000.0])
    func notchResponse(center: Double) {
        let w = 1.0
        let half = pow(2, w / 2)
        let mid = FilterDesign.notchResponseDb(at: center, center: center, widthOctaves: w, sampleRate: fs)
        let loEdge = FilterDesign.notchResponseDb(at: center / half, center: center, widthOctaves: w, sampleRate: fs)
        let hiEdge = FilterDesign.notchResponseDb(at: center * half, center: center, widthOctaves: w, sampleRate: fs)
        let pass = FilterDesign.notchResponseDb(at: center / 4, center: center, widthOctaves: w, sampleRate: fs)
        #expect(mid < -18 && mid > -32, "middle \(mid) dB")
        #expect(abs(loEdge + 3) < 1.5, "low edge \(loEdge) dB")
        #expect(abs(hiEdge + 3) < 1.5, "high edge \(hiEdge) dB")
        #expect(abs(pass) < 0.5, "passband \(pass) dB")
    }

    @Test("Notch applied offline to a tone at the centre attenuates it by > 18 dB")
    func notchOfflineTone() {
        let f = 6000.0
        let tone = OfflineRender.render(.tone(freq: f), seconds: 1, sampleRate: fs)
        let notched = OfflineRender.notch(tone, center: f, widthOctaves: 1, sampleRate: fs)
        let ratio = OfflineRender.rms(notched[24000...]) / OfflineRender.rms(tone[24000...])
        #expect(Level.gainToDb(ratio) < -18)
        let low = OfflineRender.render(.tone(freq: 1500), seconds: 1, sampleRate: fs)
        let lowN = OfflineRender.notch(low, center: f, widthOctaves: 1, sampleRate: fs)
        let lowRatio = OfflineRender.rms(lowN[24000...]) / OfflineRender.rms(low[24000...])
        #expect(abs(Level.gainToDb(lowRatio)) < 0.5)
    }

    @Test("Notched noise has a hole at f_T")
    func notchedNoiseHole() {
        let f = 6000.0
        let x = OfflineRender.render(.notchedNoise(.white, center: f, widthOctaves: 1), seconds: 2, sampleRate: fs)
        // analyse with narrow bandpasses at f and at f/4
        func bandPower(_ fc: Double) -> Double {
            var bp = BiquadChain([BiquadCoefficients(.bandpass, frequency: fc, q: 8, sampleRate: fs), BiquadCoefficients(.bandpass, frequency: fc, q: 8, sampleRate: fs)])
            let y = x.map { Float(bp.process(Double($0))) }
            return OfflineRender.rms(y[9600...])
        }
        let hole = Level.gainToDb(bandPower(f) / bandPower(f / 4))
        #expect(hole < -12, "hole \(hole) dB")
    }

    @Test("Bandpass Q and makeup match the web formulas")
    func bandpassDesign() {
        #expect(abs(FilterDesign.bandpassQ(widthOctaves: 1) - 1.41421) < 1e-4)
        #expect(abs(FilterDesign.bandpassQ(widthOctaves: 1.0 / 3) - 4.3185) < 1e-3)
        #expect(FilterDesign.narrowbandMakeup(center: 6000, widthOctaves: 1.0 / 3, sampleRate: fs) <= 30)
    }

    @Test("Peaking +9 dB at f_T for the AM enrichment")
    func peaking() {
        let c = BiquadCoefficients(.peaking(gainDb: 9), frequency: 6000, q: 0.7, sampleRate: fs)
        #expect(abs(Level.gainToDb(c.magnitude(at: 6000, sampleRate: fs)) - 9) < 0.05)
    }

    @Test("Level cap is enforced inside the voice")
    func levelCap() {
        let x = OfflineRender.render(.tone(freq: 1000), levelDb: 0, seconds: 0.5, sampleRate: fs, capDb: -20)
        let peak = x[4800...].map { abs($0) }.max() ?? 0
        #expect(peak <= Float(Level.dbToGain(-20)) * 1.01)
    }

    @Test("AM tone keeps the web app's RMS ratio")
    func amTone() {
        let t = OfflineRender.render(.tone(freq: 4000), seconds: 1, sampleRate: fs)
        let a = OfflineRender.render(.amTone(freq: 4000), seconds: 1, sampleRate: fs)
        let ratio = OfflineRender.rms(a[4800...]) / OfflineRender.rms(t[4800...])
        #expect(abs(ratio - 0.612 * 1.22) < 0.03)
    }

    @Test("CR: four tones at the ratios, 3 cycles on, 2 off")
    func crTiming() {
        let ft = 6000.0
        let cycle = fs / 1.5
        let x = OfflineRender.render(.cr(ft: ft), seconds: 5 / 1.5 * 2, sampleRate: fs)
        func cycleRms(_ k: Int) -> Double {
            let a = Int(Double(k) * cycle), b = Int(Double(k + 1) * cycle)
            return OfflineRender.rms(x[a..<b])
        }
        for k in [0, 1, 2, 5, 6, 7] { #expect(cycleRms(k) > 0.05, "cycle \(k) should sound") }
        for k in [3, 4, 8, 9] { #expect(cycleRms(k) < 1e-6, "cycle \(k) should be silent") }
        let v = SynthVoice(recipe: .cr(ft: ft), sampleRate: fs, control: VoiceControl(levelDb: 0))
        let expected = Recipe.crRatios.map { ft * $0 }
        for (a, b) in zip(v.crDebug.freqs, expected) { #expect(abs(a - b) < 1e-6) }
    }

    @Test("CR tones are 150 ms with ramps, placed in 4 slots per cycle")
    func crToneLength() {
        let x = OfflineRender.render(.cr(ft: 4000), seconds: 1 / 1.5, sampleRate: fs)
        let slot = Int(fs / 1.5) / 4
        // samples after 150 ms in the first slot must be silent
        let tail = x[Int(0.151 * fs)..<slot]
        #expect(tail.allSatisfy { $0 == 0 })
        #expect(OfflineRender.rms(x[Int(0.02 * fs)..<Int(0.13 * fs)]) > 0.3)
    }

    @Test("Tone bursts and chime finish by themselves")
    func selfFinishing() {
        let control = VoiceControl(levelDb: -20)
        var v = SynthVoice(recipe: .toneBursts(freq: 1000), sampleRate: fs, control: control)
        var buf = [Float](repeating: 0, count: 512)
        var n = 0
        while !v.isFinished && n < 1000 { buf.withUnsafeMutableBufferPointer { v.render(into: $0.baseAddress!, frames: 512) }; n += 1 }
        #expect(control.isFinished)
        #expect(Double(n * 512) / fs < 1.3)
    }

    @Test("Stop fades out over the requested time and marks finished")
    func stopFade() {
        let control = VoiceControl(levelDb: -6)
        var v = SynthVoice(recipe: .noise(.pink), sampleRate: fs, control: control)
        var buf = [Float](repeating: 0, count: 4800)
        buf.withUnsafeMutableBufferPointer { v.render(into: $0.baseAddress!, frames: 4800) }
        control.stop(fadeMs: 50)
        buf.withUnsafeMutableBufferPointer { v.render(into: $0.baseAddress!, frames: 4800) }
        #expect(control.isFinished)
        #expect(abs(buf[4799]) < 1e-3)
    }

    @Test("Frequency glide follows the control")
    func glide() {
        let control = VoiceControl(levelDb: 0, freq: 1000)
        var v = SynthVoice(recipe: .tone(freq: 1000), sampleRate: fs, control: control)
        var buf = [Float](repeating: 0, count: 4800)
        control.frequency = 2000
        buf.withUnsafeMutableBufferPointer { v.render(into: $0.baseAddress!, frames: 4800) }
        buf.withUnsafeMutableBufferPointer { v.render(into: $0.baseAddress!, frames: 4800) }
        // count zero crossings in the second block: ≈ 2 × 2000 × 0.1 s
        var zc = 0
        for i in 1..<buf.count where (buf[i - 1] < 0) != (buf[i] < 0) { zc += 1 }
        #expect(abs(zc - 400) <= 4)
    }

    @Test("Pink and brown noise are bounded")
    func noiseBounds() {
        for c in NoiseColor.allCases {
            var g = NoiseGenerator(c, seed: 42)
            var peak = 0.0
            for _ in 0..<96000 { peak = max(peak, abs(g.next())) }
            #expect(peak < 1.5, "\(c) peak \(peak)")
        }
    }

    @Test("Hearing dose: 80 dB for 40 h/week = 100 %, +3 dB halves the time")
    func dose() {
        #expect(abs(HearingDose.fraction(db: 80, seconds: 40.0 / 7 * 3600) - 1) < 1e-9)
        #expect(abs(HearingDose.fraction(db: 83, seconds: 40.0 / 7 * 3600 / 2) - 1) < 1e-9)
    }
}
