import Foundation
import TinnitusCore

/// Sensitivity profile of an output device: estimated dB SPL at the eardrum for a 0 dBFS sine at full
/// system volume and full app volume.
///
/// IMPORTANT: The numbers below are conservative *placeholders* derived from published maximum output
/// levels (EU limit ~100 dB(A) for Apple headphones). They must be replaced by artificial-head
/// measurements per third-octave band before release (05-audio-engine, step 2). Above 8 kHz the fit
/// in the ear dominates, so the uncertainty band is large.
public struct DeviceProfile: Sendable, Hashable {
    public var kind: DeviceKind
    /// dB SPL at 0 dBFS, full volume, 1 kHz.
    public var sensitivity1k: Double
    /// Per-band deviation from 1 kHz (third-octave centres → dB).
    public var bandOffsets: [Double: Double]
    /// ± uncertainty in dB up to 8 kHz / above 8 kHz.
    public var uncertaintyLow: Double
    public var uncertaintyHigh: Double
    /// Treated as calibrated (levels shown in dB SPL, comparable across devices).
    public var calibrated: Bool
    /// Valid up to this frequency.
    public var validUpTo: Double

    public func sensitivity(at f: Double) -> Double {
        guard !bandOffsets.isEmpty else { return sensitivity1k }
        let keys = bandOffsets.keys.sorted()
        if f <= keys.first! { return sensitivity1k + bandOffsets[keys.first!]! }
        if f >= keys.last! { return sensitivity1k + bandOffsets[keys.last!]! }
        // log-frequency interpolation
        for (a, b) in zip(keys, keys.dropFirst()) where f >= a && f <= b {
            let t = log2(f / a) / log2(b / a)
            return sensitivity1k + bandOffsets[a]! * (1 - t) + bandOffsets[b]! * t
        }
        return sensitivity1k
    }

    public func uncertainty(at f: Double) -> Double { f > 8000 ? uncertaintyHigh : uncertaintyLow }

    public static func profile(for kind: DeviceKind) -> DeviceProfile {
        // placeholder curves: slight high-frequency roll-off for in-ears, see note above
        let inEar: [Double: Double] = [250: 0, 1000: 0, 4000: 2, 8000: 0, 12500: -4, 16000: -8]
        switch kind {
        case .airPodsPro2, .airPodsPro3:
            return DeviceProfile(kind: kind, sensitivity1k: 100, bandOffsets: inEar, uncertaintyLow: 3, uncertaintyHigh: 10, calibrated: true, validUpTo: 16000)
        case .airPods4:
            return DeviceProfile(kind: kind, sensitivity1k: 100, bandOffsets: inEar, uncertaintyLow: 5, uncertaintyHigh: 12, calibrated: true, validUpTo: 12500)
        case .airPodsMax:
            return DeviceProfile(kind: kind, sensitivity1k: 100, bandOffsets: [250: 0, 1000: 0, 8000: 0, 16000: -6], uncertaintyLow: 3, uncertaintyHigh: 8, calibrated: true, validUpTo: 16000)
        case .speaker:
            return DeviceProfile(kind: kind, sensitivity1k: 85, bandOffsets: [:], uncertaintyLow: 10, uncertaintyHigh: 15, calibrated: false, validUpTo: 8000)
        case .bluetooth, .wired, .usb, .unknown:
            // unknown headphones: assume a loud device so that caps are conservative
            return DeviceProfile(kind: kind, sensitivity1k: 110, bandOffsets: [:], uncertaintyLow: 10, uncertaintyHigh: 15, calibrated: false, validUpTo: 16000)
        }
    }
}

/// Converts app levels (dBFS) to estimated dB SPL and back.
public struct LevelEstimator: Sendable {
    public var profile: DeviceProfile
    /// App master volume 0…1.
    public var masterVolume: Double
    /// iOS output volume 0…1.
    public var systemVolume: Double
    /// Personal offset from the 1 kHz threshold anchor (dB).
    public var userOffset: Double

    public init(profile: DeviceProfile, masterVolume: Double, systemVolume: Double, userOffset: Double = 0) {
        self.profile = profile
        self.masterVolume = masterVolume
        self.systemVolume = systemVolume
        self.userOffset = userOffset
    }

    /// iOS does not publish its volume curve. A conservative linear-in-dB model (40 dB range) is used,
    /// which overestimates the level at low volume settings rather than underestimating it.
    public static func systemVolumeDb(_ v: Double) -> Double {
        v <= 0.001 ? -80 : (min(1, v) - 1) * 40
    }

    public var gainDb: Double {
        Level.gainToDb(max(0.0001, masterVolume)) + Self.systemVolumeDb(systemVolume) + userOffset
    }

    public func spl(dbfs: Double, at f: Double = 1000) -> Double {
        dbfs + gainDb + profile.sensitivity(at: f)
    }

    public func dbfs(forSPL spl: Double, at f: Double = 1000) -> Double {
        spl - gainDb - profile.sensitivity(at: f)
    }
}

public enum SoundPurpose: Sendable {
    /// Sound programmes (enrichment, notched, reset, CR).
    case sound
    /// Measurement and RI stimuli.
    case measurement
    /// Short cues (chime, left/right test).
    case cue
}

/// Hard limits (05-audio-engine, 08-datenschutz): sound ≤ 85 dB SPL, measurement ≤ 80 dB SPL,
/// RI stimuli ≤ MML + 15 dB, nothing above −6 dBFS.
public enum SafetyLimits {
    public static let absoluteMaxDbfs = -6.0
    public static let soundMaxSPL = 85.0
    public static let measurementMaxSPL = 80.0
    public static let riAboveMML = 15.0
    /// Measurement stimuli above this level are limited in duration.
    public static let longExposureSPL = 75.0
    public static let longExposureMaxS = 300.0

    public static func capDbfs(purpose: SoundPurpose, estimator: LevelEstimator, freq: Double = 1000) -> Double {
        let spl: Double
        switch purpose {
        case .sound, .cue: spl = soundMaxSPL
        case .measurement: spl = measurementMaxSPL
        }
        // for broadband/unknown frequency content use the most sensitive band
        let f = freq > 0 ? freq : 4000
        return min(absoluteMaxDbfs, estimator.dbfs(forSPL: spl, at: f))
    }

    /// Additional cap for RI stimuli relative to the masking level.
    public static func riCap(mmlDb: Double?, loudnessDb: Double) -> Double {
        min(absoluteMaxDbfs, (mmlDb ?? loudnessDb) + riAboveMML)
    }

    public static func maxDurationS(spl: Double) -> Double {
        spl > longExposureSPL ? longExposureMaxS : .infinity
    }

    /// Measurements on the built-in speaker are not allowed; sound enrichment is.
    public static func allowsMeasurement(_ kind: DeviceKind) -> Bool { kind != .speaker }
}

/// Daily dose counter (own levels × time, 3 dB exchange rate, WHO 80 dB(A)/40 h per week).
public final class DoseMeter: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = UserDefaults(suiteName: TinnitusSchema.appGroup) ?? .standard) {
        self.defaults = defaults
    }

    private func key(_ day: String) -> String { "dose.\(day)" }

    public func add(spl: Double, seconds: Double, now: Date = .now) {
        lock.lock(); defer { lock.unlock() }
        let k = key(Day.key(now))
        defaults.set(defaults.double(forKey: k) + HearingDose.fraction(db: spl, seconds: seconds), forKey: k)
    }

    /// Fraction of today's allowance (1 = 100 %).
    public func today(now: Date = .now) -> Double {
        lock.lock(); defer { lock.unlock() }
        return defaults.double(forKey: key(Day.key(now)))
    }

    public static let warnAt = 0.5
}
