import Foundation
import SwiftUI

// MARK: - File Types

enum FileKind: String, Codable, CaseIterable {
    case video, audio, image, pdf, text, document

    var icon: String {
        switch self {
        case .video:    return "video.fill"
        case .audio:    return "waveform"
        case .image:    return "photo.fill"
        case .pdf:      return "doc.richtext.fill"
        case .text:     return "doc.text.fill"
        case .document: return "folder.fill"
        }
    }

    var emoji: String {
        switch self {
        case .video:    return "🎬"
        case .audio:    return "🎵"
        case .image:    return "🖼️"
        case .pdf:      return "📄"
        case .text:     return "📝"
        case .document: return "📁"
        }
    }

    var accentColor: Color {
        switch self {
        case .video:    return Color(hex: "#a89cf7")
        case .audio:    return Color(hex: "#60d4a0")
        case .image:    return Color(hex: "#f5b84a")
        case .pdf:      return Color(hex: "#f07070")
        case .text:     return Color(hex: "#7ea8f5")
        case .document: return Color(hex: "#9898b8")
        }
    }

    static func from(url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "avi", "mkv", "webm", "m4v": return .video
        case "mp3", "wav", "aac", "flac", "m4a", "ogg": return .audio
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif": return .image
        case "pdf": return .pdf
        case "txt", "md", "csv", "json", "html", "xml": return .text
        default: return .document
        }
    }

    var supportedExtensions: [String] {
        switch self {
        case .video:    return ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        case .audio:    return ["mp3", "wav", "aac", "flac", "m4a", "ogg"]
        case .image:    return ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]
        case .pdf:      return ["pdf"]
        case .text:     return ["txt", "md", "csv", "json", "html", "xml"]
        case .document: return []
        }
    }
}

// MARK: - Library Entry

struct MediaSegmentEmbedding: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startOffsetSec: Int
    var endOffsetSec: Int
    var embedding: [Float]
}

struct LibraryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var filePath: String
    var fileName: String
    var fileKind: FileKind
    var mimeType: String
    var sizeBytes: Int64
    var embeddedAt: Date
    var embedding: [Float]
    /// Security-scoped bookmark for sandbox access (persisted across launches).
    var securityBookmark: Data? = nil
    /// Optional per-segment embeddings (used for jump-to-timestamp search in media).
    var segmentEmbeddings: [MediaSegmentEmbedding]? = nil

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    
    var resolvedFileURL: URL {
        guard let securityBookmark else { return fileURL }
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: securityBookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        return fileURL
    }

    var sizeFormatted: String {
        let kb = Double(sizeBytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    var embeddedAgo: String {
        let diff = Date().timeIntervalSince(embeddedAt)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    // Exclude embedding from Hashable / Equatable for performance
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LibraryEntry, rhs: LibraryEntry) -> Bool { lhs.id == rhs.id }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    var id: UUID { entry.id }
    let entry: LibraryEntry
    let score: Float
    let bestSegment: MediaSegmentEmbedding?

    var scorePercent: String { String(format: "%.1f%%", score * 100) }
    var scoreFraction: Double { Double(score) }
}

// MARK: - Cost Estimate

struct CostEstimate {
    let url: URL
    let fileName: String
    let fileKind: FileKind
    let sizeBytes: Int64
    let estimatedTokens: Int
    let estimatedCostUSD: Double
    let note: String
    /// For video/audio: number of segments the API will use (video: 80s or 120s max per segment depending on audio; audio: 80s). 1 if single segment or non-media.
    let segmentCount: Int
    
    static let maxInputTokensPerRequest: Int = 8192
    
    /// Rough estimate of tokens for a single API request (per segment for segmented media).
    var estimatedTokensPerRequest: Int {
        max(1, Int(round(Double(estimatedTokens) / Double(max(segmentCount, 1)))))
    }
    
    enum TokenLimitSeverity {
        case warn
        case severe
    }
    
    /// Warning if the estimate is likely beyond model max input tokens (8,192).
    var tokenLimitWarning: (severity: TokenLimitSeverity, message: String)? {
        let perReq = estimatedTokensPerRequest
        guard perReq > Self.maxInputTokensPerRequest else { return nil }
        if perReq >= Self.maxInputTokensPerRequest * 3 {
            return (.severe, "Severely over 8,192-token limit (≈\(perReq.formatted())/request)")
        }
        return (.warn, "Likely over 8,192-token limit (≈\(perReq.formatted())/request)")
    }

    var sizeFormatted: String {
        let kb = Double(sizeBytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    var costFormatted: String {
        if estimatedCostUSD < 0.01 { return "< $0.01" }
        return String(format: "$%.4f", estimatedCostUSD)
    }

    static func for_(url: URL) -> CostEstimate {
        let kind = FileKind.from(url: url)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        let usdPerMillion: Double = 0.15

        let (tokens, note, segmentCount): (Int, String, Int)
        switch kind {
        case .video:
            let videoMaxSeg = MediaDurationHelper.maxSegmentDurationSec(url: url, kind: .video)
            if let durationSec = MediaDurationHelper.durationSec(url: url) {
                let segments = MediaDurationHelper.segmentCount(durationSec: durationSec, maxSegmentDurationSec: videoMaxSeg)
                let tokensPerSegment = Int(videoMaxSeg) * 258
                segmentCount = segments
                tokens = segments * tokensPerSegment
                note = segments > 1
                    ? "\(Int(durationSec))s → \(segments) segments (\(Int(videoMaxSeg))s max)"
                    : "~\(Int(durationSec))s"
            } else {
                let estSeconds = Double(size * 8) / 2_000_000
                segmentCount = MediaDurationHelper.segmentCount(durationSec: estSeconds, maxSegmentDurationSec: videoMaxSeg)
                tokens = segmentCount * Int(videoMaxSeg) * 258
                note = "~\(Int(estSeconds))s → \(segmentCount) segment(s), \(Int(videoMaxSeg))s max"
            }
        case .audio:
            let audioMaxSeg = MediaDurationHelper.maxSegmentDurationWithAudioSec
            if let durationSec = MediaDurationHelper.durationSec(url: url) {
                let segments = MediaDurationHelper.segmentCount(durationSec: durationSec, maxSegmentDurationSec: audioMaxSeg)
                let tokensPerSegment = Int(audioMaxSeg) * 32
                segmentCount = segments
                tokens = segments * tokensPerSegment
                note = segments > 1
                    ? "\(Int(durationSec))s → \(segments) segments (80s max)"
                    : "~\(Int(durationSec))s"
            } else {
                let estSeconds = Double(size * 8) / 128_000
                segmentCount = MediaDurationHelper.segmentCount(durationSec: estSeconds, maxSegmentDurationSec: audioMaxSeg)
                tokens = segmentCount * Int(audioMaxSeg) * 32
                note = "~\(Int(estSeconds))s → \(segmentCount) segment(s), 80s max"
            }
        case .image:
            tokens = 258
            note = "Fixed per image"
            segmentCount = 1
        case .pdf:
            let estPages = max(1, Int(size / 3000))
            tokens = estPages * 800
            note = "~\(estPages) pages estimated"
            segmentCount = 1
        case .text, .document:
            tokens = max(100, Int(Double(size) / 1024 * 250))
            note = "Based on file size"
            segmentCount = 1
        }

        let cost = Double(tokens) / 1_000_000 * usdPerMillion
        return CostEstimate(
            url: url,
            fileName: url.lastPathComponent,
            fileKind: kind,
            sizeBytes: size,
            estimatedTokens: tokens,
            estimatedCostUSD: cost,
            note: note,
            segmentCount: segmentCount
        )
    }
}

// MARK: - Settings

struct AppSettings: Codable {
    var apiKey: String = ""
    var model: String = "gemini-embedding-2-preview"
}

// MARK: - Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - MIME map

func mimeType(for url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    let map: [String: String] = [
        "mp4":"video/mp4","mov":"video/quicktime","avi":"video/x-msvideo",
        "mkv":"video/x-matroska","webm":"video/webm","m4v":"video/x-m4v",
        "mp3":"audio/mpeg","wav":"audio/wav","aac":"audio/aac",
        "flac":"audio/flac","m4a":"audio/mp4","ogg":"audio/ogg",
        "jpg":"image/jpeg","jpeg":"image/jpeg","png":"image/png",
        "gif":"image/gif","webp":"image/webp","heic":"image/heic",
        "pdf":"application/pdf","txt":"text/plain","md":"text/plain",
        "csv":"text/csv","json":"application/json","html":"text/html","xml":"text/xml"
    ]
    return map[ext] ?? "application/octet-stream"
}
