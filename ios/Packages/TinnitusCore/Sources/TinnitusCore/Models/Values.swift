import Foundation

/// Value types shared by records, export and audio. Raw values match the web app's JSON.

public enum Ear: String, Codable, Sendable, CaseIterable, Identifiable {
    case left, right, both
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .left: "Links"
        case .right: "Rechts"
        case .both: "Beide"
        }
    }
    /// Channel gains (left, right).
    public var gains: (Float, Float) {
        switch self {
        case .left: (1, 0)
        case .right: (0, 1)
        case .both: (1, 1)
        }
    }
}

public enum Timbre: String, Codable, Sendable, CaseIterable {
    case tone, hiss
}

public struct HearingPoint: Codable, Sendable, Hashable {
    public var freq: Double
    /// Relative threshold in dB (0 = full scale; more negative = better hearing).
    public var level: Double
    public init(freq: Double, level: Double) {
        self.freq = freq
        self.level = level
    }
}

public struct SpectrumPoint: Codable, Sendable, Hashable {
    public var freq: Double
    /// Mean likeness 0–10.
    public var value: Double
    public init(freq: Double, value: Double) {
        self.freq = freq
        self.value = value
    }
}

public enum StimulusKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case nbnThird = "nbn-third"
    case nbnOctave = "nbn-octave"
    case amTone = "am-tone"
    case tone
    case bbn
    case notchedBbn = "notched-bbn"
    public var id: String { rawValue }
}

public enum SomaticManeuver: String, Codable, Sendable, CaseIterable {
    case clench
    case jawForward = "jaw-forward"
    case jawOpen = "jaw-open"
    case headForward = "head-forward"
    case headBack = "head-back"
    case headLeft = "head-left"
    case headRight = "head-right"
    case gaze
}

/// -1 quieter, 0 none, 1 louder, 2 pitch/timbre change (web-compatible).
public struct SomaticResult: Codable, Sendable, Hashable {
    public var maneuver: SomaticManeuver
    public var change: Int
    public init(maneuver: SomaticManeuver, change: Int) {
        self.maneuver = maneuver
        self.change = change
    }
}

public enum TherapyMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case enrichment, reset, notched, cr
    public var id: String { rawValue }
}

/// Sound sources of the enrichment and notched modes.
public enum SoundSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case am, rain, pink, brown, white, music
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .am: "AM 10 Hz"
        case .rain: "Regen"
        case .pink: "Rosa"
        case .brown: "Braun"
        case .white: "Weiß"
        case .music: "Musik"
        }
    }
}

/// Where a session or check-in was started. Used for automatic task completion and to skip ratings.
public enum EntryOrigin: String, Codable, Sendable {
    case app, watch, widget, siri, notification, sleepFocus
}

/// Typed session parameters (replaces the web app's `Record<string, …>`).
public struct SessionParams: Codable, Sendable, Hashable {
    public var levelDb: Double
    public var source: SoundSource?
    public var stimulus: StimulusKind?
    public var notchWidthOctaves: Double?
    public var origin: EntryOrigin?
    /// Energy-averaged estimated level of the session (dB SPL) and the device it was played on;
    /// used to cross-check against HealthKit's headphone exposure.
    public var estimatedSPL: Double?
    public var device: DeviceKind?
    public init(levelDb: Double, source: SoundSource? = nil, stimulus: StimulusKind? = nil, notchWidthOctaves: Double? = nil, origin: EntryOrigin? = nil, estimatedSPL: Double? = nil, device: DeviceKind? = nil) {
        self.levelDb = levelDb
        self.source = source
        self.stimulus = stimulus
        self.notchWidthOctaves = notchWidthOctaves
        self.origin = origin
        self.estimatedSPL = estimatedSPL
        self.device = device
    }
}

/// Output device classes with distinct calibration profiles (see 05-audio-engine).
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case airPodsPro2, airPodsPro3, airPods4, airPodsMax, bluetooth, wired, usb, speaker, unknown

    public var label: String {
        switch self {
        case .airPodsPro2: "AirPods Pro 2"
        case .airPodsPro3: "AirPods Pro 3"
        case .airPods4: "AirPods 4"
        case .airPodsMax: "AirPods Max"
        case .bluetooth: "Bluetooth-Kopfhörer"
        case .wired: "Kabel-Kopfhörer"
        case .usb: "USB-Kopfhörer"
        case .speaker: "Lautsprecher"
        case .unknown: "Unbekanntes Gerät"
        }
    }

    public var isHeadphones: Bool { self != .speaker && self != .unknown }
    public var isApple: Bool { [.airPodsPro2, .airPodsPro3, .airPods4, .airPodsMax].contains(self) }
    /// Head tracking via CMHeadphoneMotionManager.
    public var supportsHeadTracking: Bool { isApple }
}

/// Which device a measurement was made with. Measurements are only comparable within one device
/// unless the device is calibrated.
public struct DeviceStamp: Codable, Sendable, Hashable {
    public var kind: DeviceKind
    public var name: String
    public var calibrated: Bool
    public init(kind: DeviceKind, name: String, calibrated: Bool) {
        self.kind = kind
        self.name = name
        self.calibrated = calibrated
    }
    public static let unknown = DeviceStamp(kind: .unknown, name: "", calibrated: false)
}

/// Neck range of motion in degrees, from AirPods head tracking.
public struct NeckROM: Codable, Sendable, Hashable {
    public var rotationLeft: Double
    public var rotationRight: Double
    public var tiltLeft: Double
    public var tiltRight: Double
    public var flexion: Double
    public var extensionDeg: Double
    public init(rotationLeft: Double = 0, rotationRight: Double = 0, tiltLeft: Double = 0, tiltRight: Double = 0, flexion: Double = 0, extensionDeg: Double = 0) {
        self.rotationLeft = rotationLeft
        self.rotationRight = rotationRight
        self.tiltLeft = tiltLeft
        self.tiltRight = tiltRight
        self.flexion = flexion
        self.extensionDeg = extensionDeg
    }
    public var total: Double { rotationLeft + rotationRight + tiltLeft + tiltRight + flexion + extensionDeg }
}

public enum HearingSource: String, Codable, Sendable {
    case app, healthKit, merged
}
