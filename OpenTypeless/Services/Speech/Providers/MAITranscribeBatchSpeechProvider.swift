import Foundation
import AVFoundation

final class MAITranscribeBatchSpeechProvider: SpeechRecognitionProvider, @unchecked Sendable {
    let name = "MAI Transcribe 2"
    let identifier = "mai-transcribe-2"
    let supportsRealtime = false
    let supportsOffline = false

    private let defaults: UserDefaults
    private let client: MAITranscribeBatchClient
    private let queue = DispatchQueue(label: "OpenTypeless.MAITranscribeBatchProvider")
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingID: UUID?
    private var configuration: MAITranscribeBatchConfiguration?
    private var upload: Task<String, Error>?
    private var savedAudioPath: String?
    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var statusHandler: ((String) -> Void)?

    init(defaults: UserDefaults = .standard, client: MAITranscribeBatchClient = MAITranscribeBatchClient()) {
        self.defaults = defaults
        self.client = client
    }

    var isAvailable: Bool {
        (try? MAITranscribeBatchConfiguration.load(from: defaults, globalLanguage: "zh-CN").requestURL()) != nil
    }

    var lastAudioFilePath: String? { queue.sync { savedAudioPath } }

    func beginCapture(language: String) throws {
        try queue.sync {
            guard recordingID == nil else { return }
            let configuration = MAITranscribeBatchConfiguration.load(from: defaults, globalLanguage: language)
            _ = try configuration.requestURL()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            guard recorder.prepareToRecord(), recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                throw SpeechRecognitionError.recognitionFailed(reason: "MAI 无法开始录音，请检查麦克风权限。")
            }
            self.configuration = configuration
            self.recorder = recorder
            recordingURL = url
            recordingID = UUID()
            savedAudioPath = nil
            statusHandler?("MAI Transcribe 2 正在录音，松开后上传转写...")
        }
    }

    func startRecognition(language: String) async throws {
        try Task.checkCancellation()
        if queue.sync(execute: { recordingID == nil }) { try beginCapture(language: language) }
    }

    func stopRecognition() async throws -> String {
        let snapshot = try queue.sync { () throws -> (UUID, URL, MAITranscribeBatchConfiguration) in
            guard let id = recordingID, let url = recordingURL, let configuration = self.configuration else {
                throw SpeechRecognitionError.cancelled
            }
            let duration = recorder?.currentTime ?? 0
            recorder?.stop()
            recorder = nil
            guard duration < 7200 else {
                try? FileManager.default.removeItem(at: url)
                recordingURL = nil
                recordingID = nil
                throw SpeechRecognitionError.recognitionFailed(reason: "MAI 非流式录音必须短于 2 小时。")
            }
            statusHandler?("正在上传音频并等待 MAI Transcribe 2 最终转写...")
            return (id, url, configuration)
        }
        let (id, url, configuration) = snapshot
        var savedURL: URL?
        defer {
            try? FileManager.default.removeItem(at: url)
            queue.sync {
                if recordingID == id {
                    recordingID = nil
                    recordingURL = nil
                    upload = nil
                }
            }
        }
        do {
            try Task.checkCancellation()
            let audio = try Data(contentsOf: url)
            let client = self.client
            let task = Task { try await client.transcribe(audio: audio, configuration: configuration) }
            queue.sync {
                if recordingID == id { upload = task } else { task.cancel() }
            }
            let text = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard queue.sync(execute: { recordingID == id }) else { throw SpeechRecognitionError.cancelled }
            if !text.isEmpty {
                do {
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("OpenTypeless/audio", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let destination = directory.appendingPathComponent("\(UUID().uuidString).wav")
                    try FileManager.default.moveItem(at: url, to: destination)
                    savedURL = destination
                } catch {
                    Logger.shared.info("Unable to save MAI audio history; transcription remains available", tag: "MAITranscribe")
                }
            }
            try Task.checkCancellation()
            let handler = try queue.sync { () throws -> ((SpeechRecognitionResult) -> Void)? in
                guard recordingID == id else { throw SpeechRecognitionError.cancelled }
                savedAudioPath = savedURL?.path
                return partialResultHandler
            }
            handler?(SpeechRecognitionResult(text: text, isFinal: true, confidence: nil, language: configuration.language))
            return text
        } catch {
            if let savedURL { try? FileManager.default.removeItem(at: savedURL) }
            let handler = queue.sync { recordingID == id ? errorHandler : nil }
            switch error {
            case is CancellationError, SpeechRecognitionError.cancelled: break
            default: handler?(error)
            }
            throw error
        }
    }

    func cancelRecognition() {
        queue.sync {
            upload?.cancel()
            upload = nil
            recorder?.stop()
            recorder = nil
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            recordingURL = nil
            recordingID = nil
            savedAudioPath = nil
        }
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) { queue.sync { partialResultHandler = handler } }
    func onError(_ handler: @escaping (Error) -> Void) { queue.sync { errorHandler = handler } }
    func onStatus(_ handler: @escaping (String) -> Void) { queue.sync { statusHandler = handler } }
}
