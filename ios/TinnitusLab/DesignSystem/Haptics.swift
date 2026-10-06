import CoreHaptics
import UIKit

/// Simple feedback plus Core Haptics breath pacing (inhale swelling, exhale decaying).
@MainActor
enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tick() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }

    private static var engine: CHHapticEngine?

    private static func ensureEngine() -> CHHapticEngine? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.playsHapticsOnly = true
        }
        try? engine?.start()
        return engine
    }

    /// One breath phase as a continuous vibration: rising for inhale, falling for exhale.
    static func breath(inhale: Bool, seconds: Double) {
        guard let engine = ensureEngine() else { return }
        let start: Float = inhale ? 0.05 : 0.6
        let end: Float = inhale ? 0.6 : 0.0
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
        ], relativeTime: 0, duration: seconds)
        let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0, value: start),
            .init(relativeTime: seconds, value: end),
        ], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameterCurves: [curve]),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    static func stopAll() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }
}
