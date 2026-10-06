import CryptoKit
import Foundation

/// Every phrase the app reads aloud. They are fixed, so they are recorded once with a neural voice
/// (`ios/Scripts/voice/generate.py`) and shipped as audio; the system voice is only a fallback.
public enum VoicePrompts {
    /// Exercise cues (both sides), rhythm labels and guided steps – deduplicated, sorted.
    public static var all: [String] {
        var s: Set<String> = ["Ein", "Aus"]
        for p in BodyContent.programs {
            for e in p.exercises {
                if e.sides == 2 {
                    s.insert(e.cue(side: 0))
                    s.insert(e.cue(side: 1))
                } else {
                    s.insert(e.cue)
                }
                for ph in e.rhythm?.phases ?? [] { s.insert(ph.label) }
            }
        }
        for t in MindContent.tools { for st in t.steps ?? [] { s.insert(st.text) } }
        for m in [1, 3, 5] { for st in MindContent.breath(minutes: m) { s.insert(st.text) } }
        return s.sorted()
    }

    /// File name of the recording: first 16 hex digits of SHA-256 over the UTF-8 text.
    public static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// What the voice should say: on-screen separators read badly aloud.
    public static func spoken(_ text: String) -> String {
        let t = text.replacingOccurrences(of: " · ", with: ". ")
            .replacingOccurrences(of: " – ", with: ", ")
        // a closing period helps neural voices end cleanly (single words otherwise trail off)
        return t.last.map { ".!?…".contains($0) } == true ? t : t + "."
    }
}
