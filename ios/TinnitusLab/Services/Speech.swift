import AVFoundation
import TinnitusCore

/// Calm German voice for guided exercises, so nobody has to look at the display.
/// All fixed phrases (`VoicePrompts.all`) ship as recordings made with a neural voice
/// (`Scripts/voice/generate.py`); only text without a recording falls back to the best installed system voice.
@MainActor
final class Speech {
    static let shared = Speech()
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    init() {
        // mix with sound programmes instead of interrupting them
        synth.usesApplicationAudioSession = true
    }

    /// Bundled recording for a phrase, if any.
    func recording(for text: String) -> URL? {
        Bundle.main.url(forResource: VoicePrompts.key(text), withExtension: "m4a")
    }

    /// True when the app ships recordings (then the system voice is only a fallback).
    var hasRecordings: Bool { VoicePrompts.all.first.flatMap(recording(for:)) != nil }

    /// Best installed German system voice: Premium › Enhanced › Compact.
    var voice: AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("de") }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            let q = switch v.quality { case .premium: 3; case .enhanced: 2; default: 1 }
            return q * 10 + (v.language == "de-DE" ? 2 : 0) + (v.voiceTraits.contains(.isNoveltyVoice) ? -20 : 0)
        }
        return german.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    var quality: AVSpeechSynthesisVoiceQuality { voice?.quality ?? .default }
    var voiceName: String { voice?.name ?? "Standard" }

    func say(_ text: String) {
        stop()
        if let url = recording(for: text), let p = try? AVAudioPlayer(contentsOf: url) {
            p.volume = 0.95
            p.prepareToPlay()
            p.play()
            player = p
            return
        }
        let u = AVSpeechUtterance(string: VoicePrompts.spoken(text))
        u.voice = voice
        u.rate = quality == .default ? 0.42 : AVSpeechUtteranceDefaultSpeechRate * 0.92
        u.pitchMultiplier = quality == .default ? 0.95 : 1.0
        u.volume = 0.9
        u.preUtteranceDelay = 0.15
        synth.speak(u)
    }

    func stop() {
        player?.stop()
        player = nil
        synth.stopSpeaking(at: .immediate)
    }
}
