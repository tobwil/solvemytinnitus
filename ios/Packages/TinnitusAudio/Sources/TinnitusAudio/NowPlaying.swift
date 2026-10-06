import Foundation
#if os(iOS)
import MediaPlayer

/// Lock screen and Control Center integration: title, remaining time, play/pause/stop (no skip).
@MainActor
public final class NowPlaying {
    public static let shared = NowPlaying()

    public var onPlay: (@MainActor () -> Void)?
    public var onPause: (@MainActor () -> Void)?
    public var onStop: (@MainActor () -> Void)?
    private var registered = false

    public func update(title: String, subtitle: String, elapsed: Double, duration: Double?, playing: Bool) {
        register()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyAlbumTitle: "Tinnitus Lab",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    public func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func register() {
        guard !registered else { return }
        registered = true
        let c = MPRemoteCommandCenter.shared()
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        c.changePlaybackPositionCommand.isEnabled = false
        c.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPlay?() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onPause?() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                if MPNowPlayingInfoCenter.default().playbackState == .playing { self?.onPause?() } else { self?.onPlay?() }
            }
            return .success
        }
        c.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.onStop?() }
            return .success
        }
    }
}
#endif
