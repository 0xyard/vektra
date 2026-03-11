import Foundation
import SwiftUI
import Combine

// MARK: - Active Embed Task

struct ActiveEmbed: Identifiable {
    let id = UUID()
    let fileName: String
    var status: String
    var fraction: Double
    var isDone: Bool = false
    var isError: Bool = false
}

// MARK: - AppStore

@MainActor
final class AppStore: ObservableObject {

    // ── Published state ──────────────────────────────────────────────────────
    @Published var library: [LibraryEntry] = []
    @Published var results: [SearchResult] = []
    @Published var selectedEntry: LibraryEntry?
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var hasSearched: Bool = false
    @Published var videoJumpStartSec: Int? = nil
    @Published var activeEmbeds: [UUID: ActiveEmbed] = [:]
    @Published var settings: AppSettings = SettingsService.shared.loadNonSensitive()
    @Published var showSettings: Bool = false
    @Published var pendingFiles: [CostEstimate] = []
    @Published var showConfirmEmbed: Bool = false
    @Published var showEmbedProgress: Bool = false
    @Published var embedHistory: [EmbedHistoryItem] = []
    @Published var errorMessage: String? = nil
    @Published var triggerFilePicker: Bool = false

    private let db = DatabaseService.shared
    private let embedSvc = EmbeddingService.shared
    private let historySvc = EmbedHistoryService.shared
    private let settingsSvc = SettingsService.shared

    private var activeBatchId: UUID? = nil
    private let embedHistoryLimit = 500

    init() {
        library = db.loadEntries()
        embedHistory = historySvc.load()
    }

    /// Load the API key from Keychain only when needed (embed/search/settings).
    /// If access is denied/needs auth, provide an operationPrompt to trigger the Keychain dialog.
    func ensureApiKeyLoaded(operationPrompt: String? = nil) {
        if settings.apiKey.isEmpty {
            settings.apiKey = settingsSvc.loadApiKeyWithMigrationIfNeeded(operationPrompt: operationPrompt)
        }
    }

    // ── File picker trigger ───────────────────────────────────────────────────
    func triggerAddFiles() { triggerFilePicker = true }

    // ── Prepare files for embedding ───────────────────────────────────────────
    func prepareFiles(urls: [URL]) {
        var pathSet = Set<String>()
        pendingFiles = urls.compactMap { url in
            let path = url.standardizedFileURL.path
            guard !pathSet.contains(path) else { return nil }
            pathSet.insert(path)
            return CostEstimate.for_(url: url)
        }
        if !pendingFiles.isEmpty { showConfirmEmbed = true }
    }

    /// Append more files to the pending list (e.g. from "Add more files" in the confirm sheet). Skips files already in the current batch.
    func appendFiles(urls: [URL]) {
        var existingPaths = Set(pendingFiles.map { $0.url.standardizedFileURL.path })
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !existingPaths.contains(path) else { continue }
            existingPaths.insert(path)
            pendingFiles.append(CostEstimate.for_(url: url))
        }
    }

    /// Remove one file from the pending list by URL. Dismisses the confirm sheet if the list becomes empty.
    func removePendingFile(url: URL) {
        let path = url.standardizedFileURL.path
        pendingFiles.removeAll { $0.url.standardizedFileURL.path == path }
        if pendingFiles.isEmpty { showConfirmEmbed = false }
    }

    // ── Embed all pending files ───────────────────────────────────────────────
    func confirmEmbed() {
        let files = pendingFiles
        pendingFiles = []
        showConfirmEmbed = false
        showEmbedProgress = true
        let batchId = UUID()
        activeBatchId = batchId
        logQueued(urls: files.map(\.url), batchId: batchId)
        Task { await embedAll(urls: files.map(\.url), batchId: batchId) }
    }

    // ── Embed loop ────────────────────────────────────────────────────────────
    func embedAll(urls: [URL], batchId: UUID) async {
        for url in urls { await embedOne(url: url, batchId: batchId) }
        if activeEmbeds.isEmpty {
            showEmbedProgress = false
        }
        if activeBatchId == batchId { activeBatchId = nil }
    }

    func embedOne(url: URL, batchId: UUID? = nil) async {
        let batchId = batchId ?? UUID()
        let embedId = UUID()
        let fileName = url.lastPathComponent
        activeEmbeds[embedId] = ActiveEmbed(fileName: fileName, status: "Starting…", fraction: 0)
        logStarted(url: url, batchId: batchId)

        do {
            ensureApiKeyLoaded(operationPrompt: "Vektra needs access to your Google API key to embed files.")
            let result = try await embedSvc.embed(url: url, settings: settings) { [weak self] prog in
                Task { @MainActor [weak self] in
                    self?.activeEmbeds[embedId]?.status = prog.status
                    self?.activeEmbeds[embedId]?.fraction = prog.fraction
                    self?.logProgress(url: url, batchId: batchId, status: prog.status, fraction: prog.fraction)
                }
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let entry = LibraryEntry(
                id: library.first(where: { $0.filePath == url.path })?.id ?? UUID(),
                filePath: url.path,
                fileName: fileName,
                fileKind: FileKind.from(url: url),
                mimeType: mimeType(for: url),
                sizeBytes: (attrs?[.size] as? Int64) ?? 0,
                embeddedAt: Date(),
                embedding: result.embedding,
                securityBookmark: bookmark,
                segmentEmbeddings: result.segments
            )
            db.upsert(entry, in: &library)
            activeEmbeds[embedId]?.status = "Done"
            activeEmbeds[embedId]?.fraction = 1.0
            activeEmbeds[embedId]?.isDone = true
            logFinished(url: url, batchId: batchId, outcome: .succeeded, status: "Done", fraction: 1.0, error: nil)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            activeEmbeds.removeValue(forKey: embedId)

        } catch {
            activeEmbeds[embedId]?.status = error.localizedDescription
            activeEmbeds[embedId]?.isError = true
            logFinished(url: url, batchId: batchId, outcome: .failed, status: error.localizedDescription, fraction: activeEmbeds[embedId]?.fraction ?? 0, error: error.localizedDescription)
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            activeEmbeds.removeValue(forKey: embedId)
        }
    }

    // ── Embed history ─────────────────────────────────────────────────────────
    private func logQueued(urls: [URL], batchId: UUID) {
        let now = Date()
        for url in urls {
            let path = url.standardizedFileURL.path
            if embedHistory.contains(where: { $0.batchId == batchId && $0.filePath == path }) { continue }
            embedHistory.insert(
                EmbedHistoryItem(
                    id: UUID(),
                    batchId: batchId,
                    filePath: path,
                    fileName: url.lastPathComponent,
                    createdAt: now,
                    updatedAt: now,
                    status: "Queued",
                    fraction: 0,
                    outcome: .inProgress,
                    errorMessage: nil
                ),
                at: 0
            )
        }
        trimAndPersistHistory()
    }

    private func logStarted(url: URL, batchId: UUID) {
        upsertHistory(url: url, batchId: batchId) { item in
            item.status = "Starting…"
            item.fraction = 0
            item.outcome = .inProgress
            item.errorMessage = nil
        }
    }

    private func logProgress(url: URL, batchId: UUID, status: String, fraction: Double) {
        upsertHistory(url: url, batchId: batchId) { item in
            item.status = status
            item.fraction = fraction
            item.outcome = .inProgress
        }
    }

    private func logFinished(url: URL, batchId: UUID, outcome: EmbedOutcome, status: String, fraction: Double, error: String?) {
        upsertHistory(url: url, batchId: batchId) { item in
            item.status = status
            item.fraction = fraction
            item.outcome = outcome
            item.errorMessage = error
        }
    }

    private func upsertHistory(url: URL, batchId: UUID, mutate: (inout EmbedHistoryItem) -> Void) {
        let path = url.standardizedFileURL.path
        let now = Date()
        if let idx = embedHistory.firstIndex(where: { $0.batchId == batchId && $0.filePath == path }) {
            var item = embedHistory[idx]
            item.updatedAt = now
            mutate(&item)
            embedHistory[idx] = item
        } else {
            var item = EmbedHistoryItem(
                id: UUID(),
                batchId: batchId,
                filePath: path,
                fileName: url.lastPathComponent,
                createdAt: now,
                updatedAt: now,
                status: "Starting…",
                fraction: 0,
                outcome: .inProgress,
                errorMessage: nil
            )
            mutate(&item)
            embedHistory.insert(item, at: 0)
        }
        trimAndPersistHistory()
    }

    private func trimAndPersistHistory() {
        if embedHistory.count > embedHistoryLimit {
            embedHistory = Array(embedHistory.prefix(embedHistoryLimit))
        }
        historySvc.save(embedHistory)
    }

    // ── Search ────────────────────────────────────────────────────────────────
    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !library.isEmpty else { return }
        isSearching = true

        do {
            ensureApiKeyLoaded(operationPrompt: "Vektra needs access to your Google API key to run semantic search.")
            let queryVec = try await embedSvc.embedQuery(query, settings: settings)
            let scored = library
                .map { entry -> SearchResult in
                    let avgScore = cosineSimilarity(queryVec, entry.embedding)
                    if let segments = entry.segmentEmbeddings, !segments.isEmpty {
                        var best: MediaSegmentEmbedding? = nil
                        var bestScore: Float = -1
                        for s in segments {
                            let sc = cosineSimilarity(queryVec, s.embedding)
                            if sc > bestScore {
                                bestScore = sc
                                best = s
                            }
                        }
                        let score = max(avgScore, bestScore)
                        return SearchResult(entry: entry, score: score, bestSegment: best)
                    }
                    return SearchResult(entry: entry, score: avgScore, bestSegment: nil)
                }
                .filter { $0.score > 0.1 }
                .sorted { $0.score > $1.score }
                .prefix(30)
            results = Array(scored)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
        hasSearched = true
    }

    // ── Delete ────────────────────────────────────────────────────────────────
    func delete(_ entry: LibraryEntry) {
        db.delete(id: entry.id, from: &library)
        if selectedEntry?.id == entry.id { selectedEntry = nil }
    }

    // ── Settings ──────────────────────────────────────────────────────────────
    func saveSettings() {
        do {
            try SettingsService.shared.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
