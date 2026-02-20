import Foundation

/// A single transcription record in history
struct TranscriptionRecord: Identifiable {
    let id: UUID
    let createdAt: Date
    let language: String

    // Recording
    let recordingDurationMs: Int
    let audioFilePath: String?

    // STT
    let sttProviderId: String
    let sttProviderName: String
    let originalText: String
    let transcriptionDurationMs: Int

    // AI Polish (optional)
    let aiProviderName: String?
    let aiModelName: String?
    let polishedText: String?
    let polishDurationMs: Int?

    /// The text to display (polished if available, otherwise original)
    var displayText: String {
        return polishedText ?? originalText
    }

    /// Formatted timestamp for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Formatted date for grouping
    var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(createdAt) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(createdAt) {
            return "昨天"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: createdAt)
        }
    }
}

// MARK: - History Manager

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var records: [TranscriptionRecord] = []

    private let log = Logger.shared
    private let database = HistoryDatabase.shared

    private init() {
        loadRecords()
    }

    // MARK: - CRUD Operations

    func addRecord(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        database.insertRecord(record)
        log.debug("Record added: \(record.id), text: \(record.displayText.prefix(50))", tag: "History")
    }

    func deleteRecord(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }

        // Delete associated audio file if exists
        if let audioPath = record.audioFilePath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        database.deleteRecord(id: record.id)
    }

    func deleteRecords(_ ids: Set<UUID>) {
        records.removeAll { ids.contains($0.id) }
        for id in ids {
            database.deleteRecord(id: id)
        }
    }

    func clearAllRecords() {
        // Delete all audio files
        for record in records {
            if let audioPath = record.audioFilePath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
        }

        records.removeAll()
        database.clearAll()
    }

    // MARK: - Search

    func search(query: String) -> [TranscriptionRecord] {
        guard !query.isEmpty else { return records }
        return database.searchRecords(query: query)
    }

    // MARK: - Grouping

    func recordsGroupedByDate() -> [(date: String, records: [TranscriptionRecord])] {
        let grouped = Dictionary(grouping: records) { $0.formattedDate }
        return grouped.map { (date: $0.key, records: $0.value) }
            .sorted { $0.records.first?.createdAt ?? Date() > $1.records.first?.createdAt ?? Date() }
    }

    // MARK: - Persistence

    private func loadRecords() {
        records = database.fetchRecords(limit: 1000)
        log.info("Loaded \(records.count) records from database", tag: "History")
    }
}
