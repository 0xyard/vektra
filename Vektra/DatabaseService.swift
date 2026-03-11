import Foundation
import Security
import LocalAuthentication

// MARK: - Keychain (API key only)

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            if let msg = SecCopyErrorMessageString(status, nil) as String? {
                return String(msg)
            }
            switch status {
            case errSecAuthFailed: return "Keychain access denied. Check that the Keychain is unlocked."
            case errSecDuplicateItem: return "Keychain item already exists."
            case errSecItemNotFound: return "Keychain item not found."
            case errSecNotAvailable: return "Keychain is not available."
            default: return "Keychain failed (error \(status))."
            }
        }
    }
}

private enum KeychainStorage {
    static let service = "io.yard.Vektra"
    static let account = "google-api-key"

    struct LoadResult {
        let status: OSStatus
        let key: String?
    }

    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary) // ignore result; ensures add won't duplicate
        let addQuery: [String: Any] = query.merging([
            kSecValueData as String: data,
        ]) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        if addStatus == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus == errSecSuccess { return }
            throw KeychainError.saveFailed(updateStatus)
        }
        throw KeychainError.saveFailed(addStatus)
    }

    static func loadAPIKey(operationPrompt: String? = nil) -> LoadResult {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let ctx = LAContext()
        if let operationPrompt {
            ctx.localizedReason = operationPrompt
            ctx.interactionNotAllowed = false
        } else {
            ctx.interactionNotAllowed = true
        }
        query[kSecUseAuthenticationContext as String] = ctx
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return LoadResult(status: status, key: nil)
        }
        return LoadResult(status: status, key: key)
    }
}

final class DatabaseService {
    static let shared = DatabaseService()

    private let dbURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Vektra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("library.json")
    }

    func loadEntries() -> [LibraryEntry] {
        guard let data = try? Data(contentsOf: dbURL),
              let entries = try? JSONDecoder().decode([LibraryEntry].self, from: data)
        else { return [] }
        return entries
    }

    func saveEntries(_ entries: [LibraryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: dbURL, options: .atomic)
    }

    func upsert(_ entry: LibraryEntry, in entries: inout [LibraryEntry]) {
        if let idx = entries.firstIndex(where: { $0.filePath == entry.filePath }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        saveEntries(entries)
    }

    func delete(id: UUID, from entries: inout [LibraryEntry]) {
        entries.removeAll { $0.id == id }
        saveEntries(entries)
    }
}

// MARK: - Settings persistence

/// Non-sensitive settings stored in UserDefaults (API key is in Keychain).
private struct PersistedSettings: Codable {
    var model: String = "gemini-embedding-2-preview"
}

final class SettingsService {
    static let shared = SettingsService()
    private let key = "vektra_settings_v1"

    /// Load non-sensitive settings without touching Keychain (avoid prompts at app launch).
    func loadNonSensitive() -> AppSettings {
        var model = "gemini-embedding-2-preview"
        if let data = UserDefaults.standard.data(forKey: key),
           let persisted = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            model = persisted.model
        } else if let data = UserDefaults.standard.data(forKey: key),
                  let old = try? JSONDecoder().decode(AppSettings.self, from: data) {
            model = old.model
        }
        return AppSettings(apiKey: "", model: model)
    }

    /// Load API key from Keychain, migrating legacy UserDefaults format once if needed.
    func loadApiKeyWithMigrationIfNeeded(operationPrompt: String? = nil) -> String {
        let first = KeychainStorage.loadAPIKey()
        if let key = first.key, !key.isEmpty { return key }
        migrateLegacyApiKeyIfPresent()
        // After migration attempt, try again. If the caller requested UI, allow it here.
        let second = KeychainStorage.loadAPIKey(operationPrompt: operationPrompt)
        return second.key ?? ""
    }

    /// If legacy settings in UserDefaults contain an API key, move it to Keychain once and clear it from UserDefaults.
    private func migrateLegacyApiKeyIfPresent() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let old = try? JSONDecoder().decode(AppSettings.self, from: data),
              !old.apiKey.isEmpty
        else { return }

        do {
            try KeychainStorage.saveAPIKey(old.apiKey)
            // Clear legacy apiKey from UserDefaults after successful migration.
            let persisted = PersistedSettings(model: old.model)
            if let newData = try? JSONEncoder().encode(persisted) {
                UserDefaults.standard.set(newData, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        } catch {
            // If Keychain save fails, keep legacy value so user can retry from Settings.
        }
    }

    func save(_ settings: AppSettings) throws {
        try KeychainStorage.saveAPIKey(settings.apiKey)
        let persisted = PersistedSettings(model: settings.model)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
