import AVFoundation

/// Calm German voice for guided exercises, so nobody has to look at the display.
/// Uses the best German voice installed on the device: Premium (neural, on-device) › Enhanced › Compact.
/// Premium voices are a free download in iOS Settings; `quality` lets the settings screen point there.
@MainActor
final class Speech {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()

    init() {
        // mix with sound programmes and duck them while speaking, instead of interrupting
        synth.usesApplicationAudioSession = true
    }

    /// Best installed German voice; recomputed so a voice downloaded meanwhile is picked up.
    var voice: AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("de") }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            let q = switch v.quality { case .premium: 3; case .enhanced: 2; default: 1 }
            // prefer de-DE over de-AT/de-CH, and skip novelty voices
            return q * 10 + (v.language == "de-DE" ? 2 : 0) + (v.voiceTraits.contains(.isNoveltyVoice) ? -20 : 0)
        }
        return german.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    var quality: AVSpeechSynthesisVoiceQuality { voice?.quality ?? .default }
    var voiceName: String { voice?.name ?? "Standard" }

    func say(_ text: String) {
        synth.stopSpeaking(at: .word)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        // neural voices sound natural at the default rate; compact ones need slowing down
        u.rate = quality == .default ? 0.42 : AVSpeechUtteranceDefaultSpeechRate * 0.92
        u.pitchMultiplier = quality == .default ? 0.95 : 1.0
        u.volume = 0.9
        u.preUtteranceDelay = 0.15
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
