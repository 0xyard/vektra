import Foundation

enum EmbedOutcome: String, Codable {
    case inProgress
    case succeeded
    case failed
}

struct EmbedHistoryItem: Identifiable, Codable {
    let id: UUID
    let batchId: UUID
    let filePath: String
    let fileName: String
    let createdAt: Date
    var updatedAt: Date
    var status: String
    var fraction: Double
    var outcome: EmbedOutcome
    var errorMessage: String?
}

final class EmbedHistoryService {
    static let shared = EmbedHistoryService()

    private let url: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Vektra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("embed_history.json")
    }

    func load() -> [EmbedHistoryItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([EmbedHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    func save(_ items: [EmbedHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

