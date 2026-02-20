import Foundation

/// Log level for the application
enum LogLevel: String, CaseIterable, Comparable {
    case off = "off"
    case info = "info"
    case debug = "debug"

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .info: return "Info"
        case .debug: return "Debug (详细)"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .off: return 0
        case .info: return 1
        case .debug: return 2
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }
}

/// Centralized logger with file output and configurable log levels
final class Logger {
    static let shared = Logger()

    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter
    private let fileDateFormatter: DateFormatter
    private var fileHandle: FileHandle?
    private var currentLogDate: String?
    private let logQueue = DispatchQueue(label: "com.opentypeless.logger", qos: .utility)

    /// Directory where log files are stored
    var logDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("OpenTypeless/Logs")
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        return logDir
    }

    private var currentLevel: LogLevel {
        let raw = UserDefaults.standard.string(forKey: "logLevel") ?? "off"
        return LogLevel(rawValue: raw) ?? .off
    }

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
    }

    deinit {
        fileHandle?.closeFile()
    }

    // MARK: - Public API

    func info(_ message: String, tag: String = "") {
        log(message, level: .info, tag: tag)
    }

    func debug(_ message: String, tag: String = "") {
        log(message, level: .debug, tag: tag)
    }

    // MARK: - Log File Management

    /// Get all log file URLs sorted by date (newest first)
    func getLogFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Read contents of a specific log file
    func readLogFile(at url: URL) -> String {
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Delete all log files
    func clearLogs() {
        for file in getLogFiles() {
            try? fileManager.removeItem(at: file)
        }
        fileHandle?.closeFile()
        fileHandle = nil
        currentLogDate = nil
    }

    // MARK: - Internal

    private func log(_ message: String, level: LogLevel, tag: String) {
        guard currentLevel >= level else { return }

        let timestamp = dateFormatter.string(from: Date())
        let levelStr = level.rawValue.uppercased()
        let prefix = tag.isEmpty ? "" : "[\(tag)] "
        let line = "[\(timestamp)] [\(levelStr)] \(prefix)\(message)\n"

        // Always print to console for Xcode debugging
        print(line, terminator: "")

        // Write to file
        logQueue.async { [weak self] in
            self?.writeToFile(line)
        }
    }

    private func writeToFile(_ line: String) {
        let today = fileDateFormatter.string(from: Date())

        // Rotate file if date changed
        if currentLogDate != today {
            fileHandle?.closeFile()
            fileHandle = nil
            currentLogDate = today
        }

        if fileHandle == nil {
            let filePath = logDirectory.appendingPathComponent("opentypeless_\(today).log")
            if !fileManager.fileExists(atPath: filePath.path) {
                fileManager.createFile(atPath: filePath.path, contents: nil)
            }
            fileHandle = FileHandle(forWritingAtPath: filePath.path)
            fileHandle?.seekToEndOfFile()
        }

        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}
