import AVFoundation
import TinnitusCore

/// Current output route, classified into calibration profiles.
public struct AudioRouteInfo: Sendable, Equatable {
    public var kind: DeviceKind
    public var name: String
    public var portType: String

    public var stamp: DeviceStamp {
        DeviceStamp(kind: kind, name: name, calibrated: DeviceProfile.profile(for: kind).calibrated)
    }

    public static let none = AudioRouteInfo(kind: .unknown, name: "", portType: "")

    /// Classify by port type and name. AirPods models are told apart by their (user-editable) name,
    /// so a renamed AirPods Pro falls back to the generic Bluetooth profile.
    public static func classify(portType: String, name: String) -> DeviceKind {
        let n = name.lowercased()
        #if os(iOS)
        let bt: Set<String> = [AVAudioSession.Port.bluetoothA2DP.rawValue, AVAudioSession.Port.bluetoothLE.rawValue, AVAudioSession.Port.bluetoothHFP.rawValue]
        let speaker = AVAudioSession.Port.builtInSpeaker.rawValue
        let receiver = AVAudioSession.Port.builtInReceiver.rawValue
        let wired = AVAudioSession.Port.headphones.rawValue
        let usb = AVAudioSession.Port.usbAudio.rawValue
        #else
        let bt: Set<String> = ["BluetoothA2DPOutput", "BluetoothLEOutput", "BluetoothHFP"]
        let speaker = "Speaker", receiver = "Receiver", wired = "Headphones", usb = "USBAudio"
        #endif
        if portType == speaker || portType == receiver { return .speaker }
        if portType == wired { return .wired }
        if portType == usb { return .usb }
        if bt.contains(portType) {
            if n.contains("airpods pro") {
                // AirPods Pro 3 report "AirPods Pro" as well; the model number is not exposed.
                // Users can pick the exact model in settings; default to Pro 2.
                return n.contains("3") ? .airPodsPro3 : .airPodsPro2
            }
            if n.contains("airpods max") { return .airPodsMax }
            if n.contains("airpods") { return .airPods4 }
            return .bluetooth
        }
        return .unknown
    }

    #if os(iOS)
    public static func current() -> AudioRouteInfo {
        #if targetEnvironment(simulator)
        // the simulator always reports its speaker; treat it as wired headphones so measurement
        // flows can be developed and UI-tested
        return AudioRouteInfo(kind: .wired, name: "Simulator", portType: AVAudioSession.Port.headphones.rawValue)
        #else
        guard let out = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return .none }
        return AudioRouteInfo(kind: classify(portType: out.portType.rawValue, name: out.portName), name: out.portName, portType: out.portType.rawValue)
        #endif
    }
    #else
    public static func current() -> AudioRouteInfo { .none }
    #endif
}
