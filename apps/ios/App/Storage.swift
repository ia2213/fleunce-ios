import Foundation
import SwiftData
import Security
import Observation
import FluenceCore

@Model final class StoredArchive {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "fluence-v2"; self.payload = payload }
}

@MainActor @Observable final class LearningStore {
    private(set) var archive = Archive()
    var error: String?
    @ObservationIgnored var onSessionInvalidation: ((UUID) -> Void)?
    let container: ModelContainer
    private var document: StoredArchive
    private let migrationBackupURL: URL?
    init(inMemory: Bool = false) throws {
        migrationBackupURL = inMemory ? nil : URL.applicationSupportDirectory
            .appendingPathComponent("Fluence", isDirectory: true)
            .appendingPathComponent("before-language-modules.json")
        container = try ModelContainer(for: StoredArchive.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none))
        let context = container.mainContext
        if let existing = try context.fetch(FetchDescriptor<StoredArchive>()).first {
            document = existing
            archive = try Archive.decode(existing.payload)
            if let legacyOwner = CredentialStore.read(for: "owner"), !legacyOwner.isEmpty {
                KeychainHelper.shared.migrateLegacyKeys(from: [.owner: legacyOwner, .groq: legacyOwner])
            }
            if let backup = migrationBackupURL,
               let root = try JSONSerialization.jsonObject(with: existing.payload) as? [String: Any], root["schemaVersion"] as? Int == 1 {
                let directory = backup.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try existing.payload.write(to: backup, options: [.atomic, .completeFileProtection])
                }
            }
            for i in archive.sessions.indices where archive.sessions[i].endedAt == nil {
                archive.sessions[i].endedAt = .now; archive.sessions[i].endReason = "App closed before finalization"
            }
        } else {
            document = StoredArchive(payload: try Archive().encoded()); context.insert(document)
        }
        persist()
    }
    var preferences: Preferences { archive.preferences }
    var language: LanguageModule { LanguageRegistry.module(for: preferences.learningLanguageID)! }
    var sessions: [SessionRecord] { archive.sessions.sorted { $0.startedAt > $1.startedAt } }
    var learningSessions: [SessionRecord] { sessions.filter { $0.languageID == language.id } }
    var learner: LearnerState { LearningEngine.project(archive.sessions, languageID: language.id, hiddenWords: archive.preferences.hiddenWords, userBaseCEFR: archive.preferences.cefrLevel) }
    func selectLanguage(_ id: String) {
        guard LanguageRegistry.module(for: id) != nil else { return }
        archive.preferences.learningLanguageID = id; persist()
    }
    func updatePreferences(_ change: (inout Preferences) -> Void) { change(&archive.preferences); persist() }
    func save(_ session: SessionRecord) {
        if let i = archive.sessions.firstIndex(where: { $0.id == session.id }) { archive.sessions[i] = session }
        else { archive.sessions.append(session) }
        persist()
    }
    func deleteSession(_ id: UUID) { onSessionInvalidation?(id); archive.sessions.removeAll { $0.id == id }; persist() }
    func hideWord(_ id: String) { archive.preferences.hiddenWords.append(id); persist() }
    func correctPassage(sessionID: UUID, passageID: String, text: String) {
        guard let index = archive.sessions.firstIndex(where: { $0.id == sessionID }),
              let passage = archive.sessions[index].passages.first(where: { $0.id == passageID && $0.speaker == .user }) else { return }
        for (offset, fragment) in passage.fragments.enumerated() {
            archive.sessions[index].correctFragment(id: fragment.id, text: offset == 0 ? String(text.prefix(10_000)) : "")
        }
        onSessionInvalidation?(sessionID)
        persist()
    }
    func deleteAll() {
        if let migrationBackupURL {
            do { try FileManager.default.removeItem(at: migrationBackupURL) }
            catch CocoaError.fileNoSuchFile { /* Most installations have no migration backup. */ }
            catch {
                self.error = "Fluence couldn’t delete the older learning backup. Your conversations are still here. Please try again."
                return
            }
        }
        archive.sessions.forEach { onSessionInvalidation?($0.id) }
        archive.sessions = []; archive.preferences.hiddenWords = []; persist()
    }
    func exportData() throws -> Data { try archive.encoded() }
    func importData(_ data: Data) throws {
        let imported = try Archive.decode(data)
        archive = try archive.merging(imported)
        persist()
    }
    private func persist() {
        do {
            document.payload = try archive.encoded()
            try container.mainContext.save()
            error = nil
            syncWidgetData()
        } catch {
            self.error = "Fluence couldn’t save your progress. Please export a backup and try again."
        }
    }
    func syncWidgetData() {
        let defaults = UserDefaults(suiteName: "group.no.william.fluence") ?? UserDefaults.standard
        defaults.set(language.name, forKey: "widget_language")
        defaults.set(learner.words.count, forKey: "widget_word_count")
        defaults.set(learningSessions.count, forKey: "widget_streak")
        let recentWords = learner.words.prefix(5).map { "\($0.lemma) - \($0.meaning)" }
        defaults.set(Array(recentWords), forKey: "widget_recent_words")
        defaults.set(learner.levelLabel, forKey: "widget_level_label")
        defaults.set(learner.capabilities.first ?? "Building vocabulary", forKey: "widget_next_goal")
    }
}

enum CredentialStore {
    private static let service = "no.william.fluence.gemini"
    private static func query(for account: String = "owner") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    
    static func read(for account: String = "owner") -> String? {
        var q = query(for: account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func hasKey(for account: String = "owner") -> Bool { read(for: account) != nil }
    static var hasKey: Bool { hasKey(for: "owner") }
    
    static func save(_ key: String, for account: String = "owner") throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { throw KeyError.invalid }
        let data = Data(value.utf8)
        let q = query(for: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQ = q; addQ[kSecValueData as String] = data
            addQ[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(addQ as CFDictionary, nil) == errSecSuccess else { throw KeyError.save }
        } else if status != errSecSuccess { throw KeyError.save }
    }
    
    static func delete(for account: String = "owner") throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.remove }
    }
    
    enum KeyError: LocalizedError {
        case invalid, save, remove
        var errorDescription: String? {
            switch self {
            case .invalid: "Entrez une clé API valide sans espaces."
            case .save: "Impossible d'enregistrer la clé dans le Keychain sécurisé d'iOS."
            case .remove: "Impossible de supprimer la clé. Déverrouillez l'iPhone et réessayez."
            }
        }
    }
}
