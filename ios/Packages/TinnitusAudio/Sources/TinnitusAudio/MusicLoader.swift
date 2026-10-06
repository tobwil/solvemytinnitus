import AVFoundation
import TinnitusCore

/// Own music through the notch (05-audio-engine "Eigene Musik"). Files are decoded to mono and
/// pre-rendered through the same 8th-order notch as the noise recipes, then looped.
/// DRM-protected Apple Music streams have no accessible asset and cannot be filtered.
public enum MusicLoader {
    public static let maxSeconds = 10.0 * 60

    public struct Decoded: Sendable {
        public var samples: [Float]
        public var sampleRate: Double
        public var title: String
        public var truncated: Bool
    }

    public enum LoadError: LocalizedError {
        case unreadable
        public var errorDescription: String? {
            "Die Datei lässt sich nicht lesen. Kopiergeschützte Titel (z. B. Apple Music) können nicht gefiltert werden."
        }
    }

    /// Decodes and notches off the main thread.
    public static func load(url: URL, center: Double, widthOctaves: Double) async throws -> Decoded {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let file = try? AVAudioFile(forReading: url) else { throw LoadError.unreadable }
            let fmt = file.processingFormat
            let total = min(file.length, AVAudioFramePosition(maxSeconds * fmt.sampleRate))
            var mono = [Float]()
            mono.reserveCapacity(Int(total))
            let chunk: AVAudioFrameCount = 32768
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: chunk) else { throw LoadError.unreadable }
            while AVAudioFramePosition(mono.count) < total {
                try file.read(into: buf, frameCount: min(chunk, AVAudioFrameCount(total) - AVAudioFrameCount(mono.count)))
                guard buf.frameLength > 0, let ch = buf.floatChannelData else { break }
                let n = Int(buf.frameLength), c = Int(fmt.channelCount)
                for i in 0..<n {
                    var s: Float = 0
                    for k in 0..<c { s += ch[k][i] }
                    mono.append(s / Float(c))
                }
            }
            // normalise to −12 dBFS peak so levels are comparable with the noise recipes
            let peak = mono.reduce(Float(0)) { max($0, abs($1)) }
            if peak > 0 {
                let g = Float(Level.dbToGain(-12)) / peak
                for i in mono.indices { mono[i] *= g }
            }
            let notched = OfflineRender.notch(mono, center: center, widthOctaves: widthOctaves, sampleRate: fmt.sampleRate)
            // short fades at the loop point
            var out = notched
            let fade = min(out.count / 2, Int(0.05 * fmt.sampleRate))
            for i in 0..<fade {
                let g = Float(i) / Float(fade)
                out[i] *= g
                out[out.count - 1 - i] *= g
            }
            return Decoded(samples: out, sampleRate: fmt.sampleRate, title: url.deletingPathExtension().lastPathComponent, truncated: file.length > total)
        }.value
    }
}
