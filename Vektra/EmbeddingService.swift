import Foundation
import AVFoundation
import PDFKit

// MARK: - Errors

enum EmbeddingError: LocalizedError {
    case noApiKey
    case uploadFailed(String)
    case processingFailed(String)
    case processingTimeout
    case embeddingFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey:               return "No API key configured. Open Settings (⌘,) to add your key."
        case .uploadFailed(let m):    return "Upload failed: \(m)"
        case .processingFailed(let m):return "File processing failed: \(m)"
        case .processingTimeout:      return "File processing timed out. Try again."
        case .embeddingFailed(let m): return "Embedding failed: \(m)"
        case .invalidResponse:        return "Invalid response from Google API."
        }
    }
}

// MARK: - Progress

struct EmbedProgress {
    let fileName: String
    let status: String
    let fraction: Double
}

struct EmbedResult {
    let embedding: [Float]
    let segments: [MediaSegmentEmbedding]?
}

// MARK: - Service

actor EmbeddingService {
    static let shared = EmbeddingService()

    private let base = "https://generativelanguage.googleapis.com"
    
    private final class UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    // MARK: Embed a file end-to-end

    func embed(
        url: URL,
        settings: AppSettings,
        progress: @escaping (EmbedProgress) -> Void
    ) async throws -> EmbedResult {
        guard !settings.apiKey.isEmpty else { throw EmbeddingError.noApiKey }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let kind = await MainActor.run { FileKind.from(url: url) }
        let fileName = url.lastPathComponent
        let mime = await MainActor.run { mimeType(for: url) }

        let send: (EmbedProgress) -> Void = { p in
            Task { @MainActor in progress(p) }
        }

        let parts: [[String: Any]]

        if kind == .text {
            send(EmbedProgress(fileName: fileName, status: "Reading file…", fraction: 0.1))
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            parts = [["text": String(text.prefix(100_000))]]
            send(EmbedProgress(fileName: fileName, status: "Embedding…", fraction: 0.5))
        } else if kind == .image, let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let size = attrs.fileSize, size < 4 * 1024 * 1024 {
            guard mime == "image/jpeg" || mime == "image/png" else {
                throw EmbeddingError.embeddingFailed("Embedding only supports JPEG and PNG images. This file is \(mime).")
            }
            send(EmbedProgress(fileName: fileName, status: "Encoding image…", fraction: 0.2))
            let data = try Data(contentsOf: url)
            let b64 = data.base64EncodedString()
            parts = [["inline_data": ["mime_type": mime, "data": b64]]]
            send(EmbedProgress(fileName: fileName, status: "Embedding…", fraction: 0.5))
        } else if kind == .pdf {
            if let doc = PDFDocument(url: url), doc.pageCount > 6 {
                throw EmbeddingError.embeddingFailed("PDFs are limited to 6 pages for embedding. This file has \(doc.pageCount) pages.")
            }
            send(EmbedProgress(fileName: fileName, status: "Uploading to Google…", fraction: 0.1))
            let fileUri = try await uploadFile(url: url, mime: mime, apiKey: settings.apiKey, progress: { frac in
                send(EmbedProgress(fileName: fileName, status: "Uploading…", fraction: 0.1 + frac * 0.5))
            })
            send(EmbedProgress(fileName: fileName, status: "Generating embedding…", fraction: 0.65))
            parts = [["file_data": ["mime_type": mime, "file_uri": fileUri]]]
        } else {
            let durationSec = (kind == .video || kind == .audio)
                ? await MediaDurationHelper.durationSecAsync(url: url)
                : nil
            let maxSeg = (kind == .video || kind == .audio)
                ? await MediaDurationHelper.maxSegmentDurationSecAsync(url: url, kind: kind)
                : 80
            let segmentCount = durationSec.map { MediaDurationHelper.segmentCount(durationSec: $0, maxSegmentDurationSec: maxSeg) } ?? 1

            if kind == .audio, segmentCount > 1, let duration = durationSec {
                send(EmbedProgress(fileName: fileName, status: "Exporting audio segment (1/\(segmentCount))…", fraction: 0.1))
                var segmentEmbeddings: [[Float]] = []
                var segments: [MediaSegmentEmbedding] = []

                let asset = AVURLAsset(url: url)
                for i in 0..<segmentCount {
                    let startSec = Double(i) * maxSeg
                    let endSec = min(startSec + maxSeg, duration)

                    send(EmbedProgress(fileName: fileName, status: "Exporting audio segment (\(i + 1)/\(segmentCount))…", fraction: 0.1 + Double(i) / Double(segmentCount) * 0.25))

                    let segmentURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("vektra-audio-seg-\(UUID().uuidString).m4a")
                    defer { try? FileManager.default.removeItem(at: segmentURL) }

                    try await exportAudioSegment(asset: asset, startSec: startSec, endSec: endSec, outputURL: segmentURL)

                    send(EmbedProgress(fileName: fileName, status: "Uploading audio segment (\(i + 1)/\(segmentCount))…", fraction: 0.35 + Double(i) / Double(segmentCount) * 0.2))
                    let segMime = "audio/mp4"
                    let fileUri = try await uploadFile(url: segmentURL, mime: segMime, apiKey: settings.apiKey, progress: { _ in })

                    send(EmbedProgress(fileName: fileName, status: "Generating embedding (\(i + 1)/\(segmentCount))…", fraction: 0.55 + Double(i) / Double(segmentCount) * 0.4))
                    let part: [String: Any] = ["file_data": ["mime_type": segMime, "file_uri": fileUri]]
                    let vec = try await embedContent(parts: [part], settings: settings)
                    segmentEmbeddings.append(vec)
                    segments.append(MediaSegmentEmbedding(startOffsetSec: Int(startSec), endOffsetSec: Int(endSec), embedding: vec))
                }

                let embedding = averageEmbeddings(segmentEmbeddings)
                send(EmbedProgress(fileName: fileName, status: "Done", fraction: 1.0))
                return EmbedResult(embedding: embedding, segments: segments)
            }

            send(EmbedProgress(fileName: fileName, status: "Uploading to Google…", fraction: 0.1))
            let fileUri = try await uploadFile(url: url, mime: mime, apiKey: settings.apiKey, progress: { frac in
                send(EmbedProgress(fileName: fileName, status: "Uploading…", fraction: 0.1 + frac * 0.5))
            })

            if kind == .video, segmentCount > 1, let duration = durationSec {
                send(EmbedProgress(fileName: fileName, status: "Generating embedding (1/\(segmentCount))…", fraction: 0.55))
                var segmentEmbeddings: [[Float]] = []
                var segments: [MediaSegmentEmbedding] = []
                for i in 0..<segmentCount {
                    let startSec = Double(i) * maxSeg
                    let endSec = min(startSec + maxSeg, duration)
                    let part = partForFileWithSegment(fileUri: fileUri, mime: mime, startOffsetSec: Int(startSec), endOffsetSec: Int(endSec))
                    let seg = try await embedContent(parts: [part], settings: settings)
                    segmentEmbeddings.append(seg)
                    segments.append(MediaSegmentEmbedding(startOffsetSec: Int(startSec), endOffsetSec: Int(endSec), embedding: seg))
                    let frac = 0.55 + Double(i + 1) / Double(segmentCount) * 0.4
                    send(EmbedProgress(fileName: fileName, status: "Generating embedding (\(i + 1)/\(segmentCount))…", fraction: frac))
                }
                let embedding = averageEmbeddings(segmentEmbeddings)
                send(EmbedProgress(fileName: fileName, status: "Done", fraction: 1.0))
                return EmbedResult(embedding: embedding, segments: segments)
            }

            send(EmbedProgress(fileName: fileName, status: "Generating embedding…", fraction: 0.65))
            parts = [["file_data": ["mime_type": mime, "file_uri": fileUri]]]
        }

        let embedding = try await embedContent(parts: parts, settings: settings)
        send(EmbedProgress(fileName: fileName, status: "Done", fraction: 1.0))
        return EmbedResult(embedding: embedding, segments: nil)
    }

    // MARK: Embed a text query

    func embedQuery(_ text: String, settings: AppSettings) async throws -> [Float] {
        guard !settings.apiKey.isEmpty else { throw EmbeddingError.noApiKey }
        let parts: [[String: Any]] = [["text": text]]
        return try await embedContent(parts: parts, settings: settings)
    }

    // MARK: - Upload via File API

    private func uploadFile(
        url: URL,
        mime: String,
        apiKey: String,
        progress: (Double) -> Void
    ) async throws -> String {
        let fileData = try Data(contentsOf: url)
        let fileSize = fileData.count
        let fileName = url.lastPathComponent

        // Step 1: Start resumable session
        var startReq = URLRequest(url: URL(string: "\(base)/upload/v1beta/files?uploadType=resumable")!)
        startReq.httpMethod = "POST"
        startReq.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        startReq.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startReq.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startReq.setValue("\(fileSize)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startReq.setValue(mime, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta = try JSONSerialization.data(withJSONObject: ["file": ["display_name": fileName]])
        startReq.httpBody = meta

        let (_, startResp) = try await URLSession.shared.data(for: startReq)
        guard let httpResp = startResp as? HTTPURLResponse,
              let uploadURLString = httpResp.value(forHTTPHeaderField: "x-goog-upload-url"),
              let uploadURL = URL(string: uploadURLString)
        else { throw EmbeddingError.uploadFailed("Could not start upload session") }

        progress(0.3)

        // Step 2: Upload bytes
        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "PUT"
        uploadReq.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadReq.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadReq.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        uploadReq.setValue(mime, forHTTPHeaderField: "Content-Type")
        uploadReq.httpBody = fileData

        let (uploadData, uploadResp) = try await URLSession.shared.data(for: uploadReq)
        guard let uploadHTTP = uploadResp as? HTTPURLResponse, uploadHTTP.statusCode == 200
        else { throw EmbeddingError.uploadFailed("Upload failed") }

        progress(0.8)

        guard let json = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let fileUri = file["uri"] as? String
        else { throw EmbeddingError.uploadFailed("No file URI in response") }

        // Step 3: Wait for ACTIVE state if needed
        let state = file["state"] as? String ?? ""
        let apiFileName = file["name"] as? String ?? ""
        if state == "PROCESSING" {
            try await waitForActive(fileName: apiFileName, apiKey: apiKey)
        }

        progress(1.0)
        return fileUri
    }

    private func waitForActive(fileName: String, apiKey: String, maxAttempts: Int = 15) async throws {
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            var req = URLRequest(url: URL(string: "\(base)/v1beta/\(fileName)")!)
            req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let state = json["state"] as? String ?? ""
                if state == "ACTIVE" { return }
                if state == "FAILED" { throw EmbeddingError.processingFailed("Google reported FAILED state") }
            }
        }
        throw EmbeddingError.processingTimeout
    }

    // MARK: - Embed Content

    private func embedContent(parts: [[String: Any]], settings: AppSettings) async throws -> [Float] {
        let model = settings.model.isEmpty ? "gemini-embedding-2-preview" : settings.model
        let urlStr = "\(base)/v1beta/models/\(model):embedContent"

        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(settings.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        let body: [String: Any] = ["content": ["parts": parts]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw EmbeddingError.invalidResponse }

        if http.statusCode != 200 {
            let errMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw EmbeddingError.embeddingFailed(errMsg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddingObj = json["embedding"] as? [String: Any],
              let values = embeddingObj["values"] as? [NSNumber]
        else { throw EmbeddingError.invalidResponse }

        return values.map { $0.floatValue }
    }

    /// Build a content part for file_data with segment (API segmenting, no file cutting; video only).
    private func partForFileWithSegment(fileUri: String, mime: String, startOffsetSec: Int, endOffsetSec: Int) -> [String: Any] {
        var fileData: [String: Any] = [
            "mime_type": mime,
            "file_uri": fileUri,
        ]
        if mime.hasPrefix("video/") {
            fileData["video_segment_config"] = [
                "start_offset_sec": startOffsetSec,
                "end_offset_sec": endOffsetSec,
            ] as [String: Any]
        }
        return ["file_data": fileData]
    }

    /// Element-wise mean of embeddings (same dimension).
    private func averageEmbeddings(_ vectors: [[Float]]) -> [Float] {
        guard !vectors.isEmpty, let dim = vectors.first?.count else { return [] }
        var sum = [Float](repeating: 0, count: dim)
        for v in vectors where v.count == dim {
            for i in 0..<dim { sum[i] += v[i] }
        }
        let n = Float(vectors.count)
        return sum.map { $0 / n }
    }

    private func exportAudioSegment(
        asset: AVAsset,
        startSec: Double,
        endSec: Double,
        outputURL: URL
    ) async throws {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw EmbeddingError.embeddingFailed("Could not create audio export session.")
        }
        let exportBox = UncheckedSendableBox(export)
        export.outputURL = outputURL
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: startSec, preferredTimescale: 600),
            end: CMTime(seconds: endSec, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            exportBox.value.exportAsynchronously {
                let export = exportBox.value
                switch export.status {
                case .completed:
                    cont.resume()
                case .failed:
                    cont.resume(throwing: export.error ?? EmbeddingError.embeddingFailed("Audio export failed."))
                case .cancelled:
                    cont.resume(throwing: EmbeddingError.embeddingFailed("Audio export cancelled."))
                default:
                    cont.resume(throwing: EmbeddingError.embeddingFailed("Audio export did not complete."))
                }
            }
        }
    }
}

// MARK: - Cosine Similarity

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0, normA: Float = 0, normB: Float = 0
    for i in 0..<a.count {
        dot   += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denom = sqrt(normA) * sqrt(normB)
    return denom == 0 ? 0 : dot / denom
}
