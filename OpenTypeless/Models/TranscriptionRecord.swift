import Foundation

/// A single transcription record in history
struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let originalText: String
    let processedText: String?
    let language: String
    let provider: String
    let duration: TimeInterval
    let audioFilePath: String?

    // Processing metadata
    let wasFormatted: Bool
    let wasRewritten: Bool
    let wasTranslated: Bool
    let instruction: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        originalText: String,
        processedText: String? = nil,
        language: String,
        provider: String,
        duration: TimeInterval,
        audioFilePath: String? = nil,
        wasFormatted: Bool = false,
        wasRewritten: Bool = false,
        wasTranslated: Bool = false,
        instruction: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.processedText = processedText
        self.language = language
        self.provider = provider
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.wasFormatted = wasFormatted
        self.wasRewritten = wasRewritten
        self.wasTranslated = wasTranslated
        self.instruction = instruction
    }

    /// The text to display (processed if available, otherwise original)
    var displayText: String {
        return processedText ?? originalText
    }

    /// Formatted timestamp for display
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Formatted date for grouping
    var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(timestamp) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(timestamp) {
            return "昨天"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: timestamp)
        }
    }
}

// MARK: - History Manager

@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var records: [TranscriptionRecord] = []

    private let storageKey = "transcriptionHistory"
    private let maxRecords = 1000

    private init() {
        loadRecords()
    }

    // MARK: - CRUD Operations

    func addRecord(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)

        // Trim if exceeds max
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        saveRecords()
    }

    func deleteRecord(_ record: TranscriptionRecord) {
        records.removeAll { $0.id == record.id }

        // Delete associated audio file if exists
        if let audioPath = record.audioFilePath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        saveRecords()
    }

    func deleteRecords(_ ids: Set<UUID>) {
        records.removeAll { ids.contains($0.id) }
        saveRecords()
    }

    func clearAllRecords() {
        // Delete all audio files
        for record in records {
            if let audioPath = record.audioFilePath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
        }

        records.removeAll()
        saveRecords()
    }

    // MARK: - Search

    func search(query: String) -> [TranscriptionRecord] {
        guard !query.isEmpty else { return records }

        return records.filter {
            $0.originalText.localizedCaseInsensitiveContains(query) ||
            ($0.processedText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Grouping

    func recordsGroupedByDate() -> [(date: String, records: [TranscriptionRecord])] {
        let grouped = Dictionary(grouping: records) { $0.formattedDate }
        return grouped.map { (date: $0.key, records: $0.value) }
            .sorted { $0.records.first?.timestamp ?? Date() > $1.records.first?.timestamp ?? Date() }
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func saveRecords() {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    // MARK: - Cleanup

    func cleanupOldRecords(olderThan days: Int) {
        guard days > 0 else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let oldRecords = records.filter { $0.timestamp < cutoffDate }

        // Delete audio files
        for record in oldRecords {
            if let audioPath = record.audioFilePath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
        }

        records.removeAll { $0.timestamp < cutoffDate }
        saveRecords()
    }
}
