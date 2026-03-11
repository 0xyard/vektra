import Foundation
import AVFoundation

/// Provides media duration and segment limits for video/audio. API: video with audio 80s, video without audio 120s, audio 80s per segment.
enum MediaDurationHelper: Sendable {
    /// Segment limit for video with audio and for audio-only files.
    nonisolated static let maxSegmentDurationWithAudioSec: Double = 80
    /// Segment limit for video without an audio track.
    nonisolated static let maxSegmentDurationVideoNoAudioSec: Double = 120

    /// Maximum segment duration in seconds for a given media file. Use when computing segment count for embedding.
    static nonisolated func maxSegmentDurationSecAsync(url: URL, kind: FileKind) async -> Double {
        switch kind {
        case .video:
            let hasAudio = await videoHasAudioAsync(url: url)
            return hasAudio ? maxSegmentDurationWithAudioSec : maxSegmentDurationVideoNoAudioSec
        case .audio:
            return maxSegmentDurationWithAudioSec
        default:
            return maxSegmentDurationWithAudioSec
        }
    }

    /// Synchronous: max segment duration for cost estimate. For video, uses audio detection; for audio, 80s.
    static nonisolated func maxSegmentDurationSec(url: URL, kind: FileKind) -> Double {
        switch kind {
        case .video:
            return videoHasAudio(url: url) ? maxSegmentDurationWithAudioSec : maxSegmentDurationVideoNoAudioSec
        case .audio:
            return maxSegmentDurationWithAudioSec
        default:
            return maxSegmentDurationWithAudioSec
        }
    }

    /// Returns true if the asset has at least one audio track. Only meaningful for video URLs.
    static nonisolated func videoHasAudioAsync(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }

    /// Synchronous wrapper for UI/cost estimate.
    static nonisolated func videoHasAudio(url: URL) -> Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            result = await videoHasAudioAsync(url: url)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// Returns duration in seconds for video/audio URLs, or nil if not media or unreadable. Synchronous wrapper for use from sync callers (e.g. cost estimate).
    static nonisolated func durationSec(url: URL) -> Double? {
        var result: Double?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            result = await durationSecAsync(url: url)
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// Async version using the non-deprecated load(.duration) API.
    static nonisolated func durationSecAsync(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else { return nil }
            return duration.seconds
        } catch {
            return nil
        }
    }

    /// Number of segments for embedding (each segment ≤ maxSegmentDurationSec).
    static nonisolated func segmentCount(durationSec: Double, maxSegmentDurationSec: Double) -> Int {
        max(1, Int(ceil(durationSec / maxSegmentDurationSec)))
    }
}
