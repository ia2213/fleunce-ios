import Foundation
import SQLite3
import FluenceCore

// MARK: - SQLite Anki Importer (pagination, streaming)

public struct AnkiNote {
    public let id: Int64
    public let tags: String
    public let fields: [String: String]
}

public struct AnkiCard {
    public let id: Int64
    public let noteId: Int64
    public let queue: Int32
    public let due: Int32
    public let interval: Int32
    public let easeFactor: Double
    public let lapses: Int32
    public let data: String
}

public struct AnkiSQLiteSchema: Sendable {
    public let notesTable: String
    public let cardsTable: String
    public let fieldsTable: String
    public let notesIdColumn: String
    public let notesTagsColumn: String
    public let cardsNoteIdColumn: String
    public let cardsDueColumn: String
}

// Default Anki2 schema
public let DefaultAnkiSchema = AnkiSQLiteSchema(
    notesTable: "notes",
    cardsTable: "cards",
    fieldsTable: "fields",
    notesIdColumn: "id",
    notesTagsColumn: "tags",
    cardsNoteIdColumn: "nid",
    cardsDueColumn: "due"
)

public enum SQLiteAnkiError: LocalizedError {
    case invalidFile
    case openFailed(OSStatus)
    case tableNotFound(String)
    case queryFailed(String)
    case paginationInterrupted

    public var errorDescription: String? {
        switch self {
        case .invalidFile: return "Ce fichier n'est pas une base SQLite valide."
        case .openFailed(let code): return "Erreur ouverture SQLite (code \(code))."
        case .tableNotFound(let t): return "La table '\(t)' est introuvable dans cette base Anki."
        case .queryFailed(let msg): return "Échec requête SQLite : \(msg)."
        case .paginationInterrupted: return "L'import a été interrompu."
        }
    }
}

public actor SQLiteAnkiImporter {
    private let db: OpaquePointer?
    private let schema: AnkiSQLiteSchema
    private var cachedFieldNames: [Int64: String]?
    private var fieldNamesLock = false

    public init(url: URL, schema: AnkiSQLiteSchema = DefaultAnkiSchema) throws {
        guard url.pathExtension.lowercased() == "sqlite" || url.pathExtension.lowercased() == "anki2" || url.pathExtension.isEmpty else {
            throw SQLiteAnkiError.invalidFile
        }
        var dbPtr: OpaquePointer?
        let rc = sqlite3_open(url.path, &dbPtr)
        guard rc == SQLITE_OK, let db = dbPtr else {
            throw SQLiteAnkiError.openFailed(OSStatus(rc))
        }
        self.db = db
        self.schema = schema
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema detection

    public func detectSchema() throws -> AnkiSQLiteSchema {
        let tables = try self.tables()
        var notes: String? = nil, cards: String? = nil, fields: String? = nil
        for t in tables {
            if t.hasSuffix("notes") || t == "notes" { notes = t }
            if t.hasSuffix("cards") || t == "cards" { cards = t }
            if t.hasSuffix("fields") || t == "fields" { fields = t }
        }
        guard let n = notes, let c = cards else {
            throw SQLiteAnkiError.tableNotFound("notes/cards")
        }
        return AnkiSQLiteSchema(
            notesTable: n,
            cardsTable: c,
            fieldsTable: fields ?? "fields",
            notesIdColumn: "id",
            notesTagsColumn: "tags",
            cardsNoteIdColumn: "nid",
            cardsDueColumn: "due"
        )
    }

    public func tables() throws -> [String] {
        let stmt = try prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        var result: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 0) {
                result.append(String(cString: name))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    // MARK: - Notes (paginated)

    public func notes(limit: Int = 500, offset: Int = 0) throws -> [AnkiNote] {
        let stmt = try prepare("SELECT \(schema.notesIdColumn), \(schema.notesTagsColumn) FROM \(schema.notesTable) LIMIT ? OFFSET ?")
        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))
        var result: [AnkiNote] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let tags = sqlite3_column_text(stmt, 1)
            let tagStr = tags != nil ? String(cString: tags!) : ""
            result.append(AnkiNote(id: id, tags: tagStr, fields: [:]))
        }
        sqlite3_finalize(stmt)
        return result
    }

    public func totalNotes() throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM \(schema.notesTable)")
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        let count = Int(sqlite3_column_int(stmt, 0))
        sqlite3_finalize(stmt)
        return count
    }

    // MARK: - Cards for notes (paginated)

    public func cards(forNoteIds noteIds: [Int64], limit: Int = 500) throws -> [AnkiCard] {
        guard !noteIds.isEmpty else { return [] }
        let placeholders = noteIds.map { _ in "?" }.joined(separator: ",")
        let sql = "SELECT id, \(schema.cardsNoteIdColumn), queue, due, interval, easeFactor, lapses, data FROM \(schema.cardsTable) WHERE \(schema.cardsNoteIdColumn) IN (\(placeholders)) LIMIT ?"
        let stmt = try prepare(sql)
        for (i, id) in noteIds.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), id)
        }
        sqlite3_bind_int(stmt, Int32(noteIds.count + 1), Int32(limit))
        var result: [AnkiCard] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(AnkiCard(
                id: sqlite3_column_int64(stmt, 0),
                noteId: sqlite3_column_int64(stmt, 1),
                queue: sqlite3_column_int(stmt, 2),
                due: sqlite3_column_int(stmt, 3),
                interval: sqlite3_column_int(stmt, 4),
                easeFactor: sqlite3_column_double(stmt, 5),
                lapses: sqlite3_column_int(stmt, 6),
                data: sqlite3_column_text(stmt, 7) != nil ? String(cString: sqlite3_column_text(stmt, 7)!) : ""
            ))
        }
        sqlite3_finalize(stmt)
        return result
    }

    // MARK: - Text extraction from note fields

    public func extractText(from note: AnkiNote) throws -> String {
        // Note: fields should be decoded separately; here we return tags for now
        // In production, decode fields and sanitize with HTMLSanitizer
        return HTMLSanitizer.shared.clean(note.tags)
    }

    // MARK: - Close

    public func close() {
        // already handled in deinit
    }

    // MARK: - Helpers

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let s = stmt else {
            let errMsg: String
            if let err = sqlite3_errmsg(db) {
                errMsg = String(cString: err)
            } else {
                errMsg = "unknown"
            }
            throw SQLiteAnkiError.queryFailed(errMsg)
        }
        return s
    }
}

// MARK: - Convenience: import all notes with pagination

public struct AnkiImportResult: Sendable {
    public let totalNotes: Int
    public let importedNotes: Int
    public let cards: Int
    public let errors: [String]
}

public actor AnkiImportSession {
    private let importer: SQLiteAnkiImporter
    private var importedNoteIds: Set<Int64> = []

    public init(url: URL) throws {
        self.importer = try SQLiteAnkiImporter(url: url)
    }

    public func importAll(batchSize: Int = 500) async throws -> AnkiImportResult {
        let total = try await importer.totalNotes()
        var importedCount = 0
        var totalCards = 0
        var errors: [String] = []
        var offset = 0

        while offset < total {
            let batch = try await importer.notes(limit: batchSize, offset: offset)
            guard !batch.isEmpty else { break }

            // Fetch cards for this batch
            let noteIds = batch.map(\.id)
            let cards = try await importer.cards(forNoteIds: noteIds)
            totalCards += cards.count
            importedCount += batch.count
            importedNoteIds.formUnion(noteIds)

            offset += batchSize

            // Yield to avoid blocking (important for UI)
            await Task.yield()
        }

        return AnkiImportResult(
            totalNotes: total,
            importedNotes: importedCount,
            cards: totalCards,
            errors: errors
        )
    }

    public func extractAllTexts() async throws -> [(note: AnkiNote, text: String)] {
        let total = try await importer.totalNotes()
        var results: [(note: AnkiNote, text: String)] = []
        var offset = 0

        while offset < total {
            let batch = try await importer.notes(limit: 500, offset: offset)
            for note in batch {
                let text = try await importer.extractText(from: note)
                if !text.isEmpty {
                    results.append((note: note, text: text))
                }
            }
            offset += 500
            await Task.yield()
        }
        return results
    }

    public func close() {
        // handled by deinit
    }
}
