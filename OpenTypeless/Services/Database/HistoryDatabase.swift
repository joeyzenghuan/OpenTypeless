import Foundation
import SQLite3

/// Thin wrapper around SQLite3 C API for persisting transcription records
class HistoryDatabase {
    static let shared = HistoryDatabase()

    private var db: OpaquePointer?

    private init() {
        openDatabase()
        createTableIfNeeded()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Setup

    private func openDatabase() {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenTypeless", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)

        let dbPath = appSupportDir.appendingPathComponent("history.sqlite").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let errmsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("[History] Failed to open database: \(errmsg)")
            db = nil
        } else {
            print("[History] Database opened at \(dbPath)")
            // Enable WAL mode for better concurrent performance
            execute("PRAGMA journal_mode=WAL;")
        }
    }

    private func createTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS transcription_records (
            id                        TEXT PRIMARY KEY,
            created_at                REAL NOT NULL,
            language                  TEXT NOT NULL,
            recording_duration_ms     INTEGER NOT NULL,
            audio_file_path           TEXT,
            stt_provider_id           TEXT NOT NULL,
            stt_provider_name         TEXT NOT NULL,
            original_text             TEXT NOT NULL,
            transcription_duration_ms INTEGER NOT NULL,
            ai_provider_name          TEXT,
            ai_model_name             TEXT,
            polished_text             TEXT,
            polish_duration_ms        INTEGER
        );
        """
        execute(sql)
    }

    // MARK: - Insert

    func insertRecord(_ record: TranscriptionRecord) {
        let sql = """
        INSERT INTO transcription_records (
            id, created_at, language,
            recording_duration_ms, audio_file_path,
            stt_provider_id, stt_provider_name, original_text, transcription_duration_ms,
            ai_provider_name, ai_model_name, polished_text, polish_duration_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("insertRecord prepare")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.id.uuidString.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, record.language.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(record.recordingDurationMs))
        bindOptionalText(stmt, index: 5, value: record.audioFilePath)
        sqlite3_bind_text(stmt, 6, record.sttProviderId.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, record.sttProviderName.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, record.originalText.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 9, Int32(record.transcriptionDurationMs))
        bindOptionalText(stmt, index: 10, value: record.aiProviderName)
        bindOptionalText(stmt, index: 11, value: record.aiModelName)
        bindOptionalText(stmt, index: 12, value: record.polishedText)
        bindOptionalInt(stmt, index: 13, value: record.polishDurationMs)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logError("insertRecord step")
        } else {
            print("[History] Record inserted: \(record.id)")
        }
    }

    // MARK: - Fetch

    func fetchRecords(limit: Int = 100, offset: Int = 0) -> [TranscriptionRecord] {
        let sql = "SELECT * FROM transcription_records ORDER BY created_at DESC LIMIT ? OFFSET ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("fetchRecords prepare")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))

        var records: [TranscriptionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = readRecord(from: stmt) {
                records.append(record)
            }
        }
        return records
    }

    // MARK: - Search

    func searchRecords(query: String) -> [TranscriptionRecord] {
        let sql = """
        SELECT * FROM transcription_records
        WHERE original_text LIKE ? OR polished_text LIKE ?
        ORDER BY created_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("searchRecords prepare")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, pattern.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, pattern.cString(using: .utf8), -1, SQLITE_TRANSIENT)

        var records: [TranscriptionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = readRecord(from: stmt) {
                records.append(record)
            }
        }
        return records
    }

    // MARK: - Delete

    func deleteRecord(id: UUID) {
        let sql = "DELETE FROM transcription_records WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("deleteRecord prepare")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id.uuidString.cString(using: .utf8), -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) != SQLITE_DONE {
            logError("deleteRecord step")
        }
    }

    func clearAll() {
        execute("DELETE FROM transcription_records;")
        print("[History] All records cleared")
    }

    // MARK: - Count

    func recordCount() -> Int {
        let sql = "SELECT COUNT(*) FROM transcription_records;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logError("recordCount prepare")
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    // MARK: - Helpers

    /// SQLite transient destructor – tells SQLite to copy the string immediately
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func execute(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            logError("execute: \(sql.prefix(60))")
        }
    }

    private func logError(_ context: String) {
        let errmsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        print("[History] SQLite error (\(context)): \(errmsg)")
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value.cString(using: .utf8), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, index: Int32, value: Int?) {
        if let value = value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readRecord(from stmt: OpaquePointer?) -> TranscriptionRecord? {
        guard let idStr = columnText(stmt, 0),
              let id = UUID(uuidString: idStr) else { return nil }

        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        let language = columnText(stmt, 2) ?? ""
        let recordingDurationMs = Int(sqlite3_column_int(stmt, 3))
        let audioFilePath = columnText(stmt, 4)
        let sttProviderId = columnText(stmt, 5) ?? ""
        let sttProviderName = columnText(stmt, 6) ?? ""
        let originalText = columnText(stmt, 7) ?? ""
        let transcriptionDurationMs = Int(sqlite3_column_int(stmt, 8))
        let aiProviderName = columnText(stmt, 9)
        let aiModelName = columnText(stmt, 10)
        let polishedText = columnText(stmt, 11)
        let polishDurationMs: Int? = sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 12))

        return TranscriptionRecord(
            id: id,
            createdAt: createdAt,
            language: language,
            recordingDurationMs: recordingDurationMs,
            audioFilePath: audioFilePath,
            sttProviderId: sttProviderId,
            sttProviderName: sttProviderName,
            originalText: originalText,
            transcriptionDurationMs: transcriptionDurationMs,
            aiProviderName: aiProviderName,
            aiModelName: aiModelName,
            polishedText: polishedText,
            polishDurationMs: polishDurationMs
        )
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}
