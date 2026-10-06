import CoreMotion
import Foundation
import Observation
import TinnitusCore

/// AirPods head tracking (CMHeadphoneMotionManager, 06-koerper-dehnung): orientation relative to a
/// reference taken at the start of each exercise (yaw drifts over time), plus jerk detection.
/// Sign convention matches `MotionTarget`: yaw left −/right +, roll left −/right +, pitch flexion +.
@MainActor
@Observable
final class HeadTracker: NSObject {
    static let shared = HeadTracker()

    private(set) var connected = false
    private(set) var running = false
    private(set) var yaw = 0.0
    private(set) var roll = 0.0
    private(set) var pitch = 0.0
    /// Angular speed in °/s (for "langsamer" warnings).
    private(set) var speed = 0.0
    private(set) var authorized = CMHeadphoneMotionManager.authorizationStatus() != .denied

    @ObservationIgnored private let manager = CMHeadphoneMotionManager()
    @ObservationIgnored private var reference: CMAttitude?
    @ObservationIgnored private var resetRequested = true

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard isAvailable, !running else { return }
        running = true
        resetRequested = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let att = motion.attitude.copy() as! CMAttitude
            let rate = motion.rotationRate
            MainActor.assumeIsolated { self?.handle(att, rate: rate) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        running = false
        reference = nil
    }

    /// Takes the current orientation as zero.
    func recenter() { resetRequested = true }

    private func handle(_ att: CMAttitude, rate: CMRotationRate) {
        connected = true
        authorized = true
        if resetRequested || reference == nil {
            reference = att.copy() as? CMAttitude
            resetRequested = false
        }
        if let ref = reference { att.multiply(byInverseOf: ref) }
        let deg = 180 / Double.pi
        yaw = -att.yaw * deg
        roll = att.roll * deg
        pitch = -att.pitch * deg
        speed = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z) * deg
    }

    func value(_ axis: MotionTarget.Axis) -> Double {
        switch axis {
        case .yaw: yaw
        case .roll: roll
        case .pitch: pitch
        }
    }
}

extension HeadTracker: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in HeadTracker.shared.connected = true }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in HeadTracker.shared.connected = false }
    }
}
