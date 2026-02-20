import Foundation
import AVFoundation

/// Azure OpenAI Whisper API implementation
///
/// This provider captures audio from the microphone using AVAudioRecorder,
/// then sends the complete audio file to the Azure OpenAI Whisper API for transcription
/// when recognition is stopped.
///
/// Setup:
/// 1. Deploy a Whisper model in your Azure OpenAI resource
/// 2. Configure endpoint, deployment name, and API key in Settings
///
/// Documentation: https://learn.microsoft.com/azure/ai-services/openai/whisper-quickstart
class WhisperSpeechProvider: SpeechRecognitionProvider {

    // MARK: - Protocol Properties

    let name = "Azure OpenAI Whisper"
    let identifier = "whisper"
    let supportsRealtime = false
    let supportsOffline = false

    var isAvailable: Bool {
        guard let endpoint = endpoint, !endpoint.isEmpty,
              let deployment = deployment, !deployment.isEmpty,
              let key = apiKey, !key.isEmpty else {
            return false
        }
        return true
    }

    // MARK: - Configuration

    private var endpoint: String?
    private var deployment: String?
    private var apiKey: String?
    private let apiVersion = "2024-02-01"

    // MARK: - Private Properties

    private let log = Logger.shared

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var isRecording = false

    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    private var currentLanguage: String = "zh-CN"

    /// Path to the last saved audio file for history tracking
    private(set) var lastAudioFilePath: String?

    /// Recording settings: 16kHz mono 16-bit PCM (optimal for Whisper)
    private let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    // MARK: - Initialization

    init(endpoint: String? = nil, deployment: String? = nil, apiKey: String? = nil) {
        self.endpoint = endpoint ?? UserDefaults.standard.string(forKey: "whisperEndpoint")
        self.deployment = deployment ?? UserDefaults.standard.string(forKey: "whisperDeployment")
        self.apiKey = apiKey ?? UserDefaults.standard.string(forKey: "whisperAPIKey")

        log.info("Initialized", tag: "Whisper")
        log.debug("Endpoint: \(self.endpoint ?? "not set")", tag: "Whisper")
        log.debug("Deployment: \(self.deployment ?? "not set")", tag: "Whisper")
        log.debug("Key configured: \(self.apiKey?.isEmpty == false ? "yes" : "no")", tag: "Whisper")

        // Pre-warm the audio hardware so the first recording starts instantly
        prepareNextRecorder()
    }

    // MARK: - Configuration

    func reloadConfig() {
        self.endpoint = UserDefaults.standard.string(forKey: "whisperEndpoint")
        self.deployment = UserDefaults.standard.string(forKey: "whisperDeployment")
        self.apiKey = UserDefaults.standard.string(forKey: "whisperAPIKey")
        log.info("Config reloaded", tag: "Whisper")
    }

    // MARK: - Protocol Methods

    /// Pre-create and prepare a recorder so the audio hardware is warmed up.
    /// When beginCapture() is called, record() starts instantly.
    private func prepareNextRecorder() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        recordingURL = fileURL

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: recordingSettings)
            recorder.prepareToRecord()
            audioRecorder = recorder
            log.debug("Recorder prepared: \(fileURL.lastPathComponent)", tag: "Whisper")
        } catch {
            log.info("Failed to prepare recorder: \(error)", tag: "Whisper")
            audioRecorder = nil
        }
    }

    /// Synchronously start audio recording — called before any UI work.
    /// The recorder is already prepared (audio hardware warmed up), so record() is instant.
    func beginCapture(language: String) throws {
        guard isAvailable else {
            log.info("Not configured", tag: "Whisper")
            throw SpeechRecognitionError.apiKeyMissing
        }

        currentLanguage = language

        // If no prepared recorder (shouldn't happen), create one on the fly
        if audioRecorder == nil {
            prepareNextRecorder()
        }

        guard let recorder = audioRecorder else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to initialize recorder")
        }

        guard recorder.record() else {
            log.info("AVAudioRecorder.record() returned false", tag: "Whisper")
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to start audio recording")
        }

        isRecording = true
        log.info("Recording started: \(recordingURL?.lastPathComponent ?? "?")", tag: "Whisper")
    }

    func startRecognition(language: String) async throws {
        // Recording already started by beginCapture().
        // If beginCapture wasn't called (e.g. other code paths), start here as fallback.
        if !isRecording {
            try beginCapture(language: language)
        }

        log.debug("Endpoint: \(endpoint ?? "unknown"), Deployment: \(deployment ?? "unknown")", tag: "Whisper")

        // Notify that recording has started (show a recording indicator)
        let result = SpeechRecognitionResult(
            text: "...",
            isFinal: false,
            confidence: nil,
            language: language
        )
        partialResultHandler?(result)
    }

    func stopRecognition() async throws -> String {
        log.info("Stopping recognition...", tag: "Whisper")

        // Stop recording
        isRecording = false
        audioRecorder?.stop()
        audioRecorder = nil

        guard let fileURL = recordingURL else {
            log.info("No recording URL", tag: "Whisper")
            prepareNextRecorder()
            return ""
        }

        // Read the recorded WAV file
        let wavData: Data
        do {
            wavData = try Data(contentsOf: fileURL)
        } catch {
            log.info("Failed to read recording file: \(error)", tag: "Whisper")
            return ""
        }

        log.debug("WAV data size: \(wavData.count) bytes (\(String(format: "%.1f", Double(wavData.count) / 1024 / 1024)) MB)", tag: "Whisper")

        // A valid WAV header is 44 bytes; anything less means no actual audio
        guard wavData.count > 44 else {
            log.info("No audio recorded (file too small)", tag: "Whisper")
            try? FileManager.default.removeItem(at: fileURL)
            return ""
        }

        // Check file size limit (25 MB)
        guard wavData.count <= 25 * 1024 * 1024 else {
            log.info("Audio too large (>25MB)", tag: "Whisper")
            try? FileManager.default.removeItem(at: fileURL)
            throw SpeechRecognitionError.recognitionFailed(reason: "Audio file exceeds 25MB limit. Please record a shorter clip.")
        }

        // Notify user we're transcribing
        let processingResult = SpeechRecognitionResult(
            text: "...",
            isFinal: false,
            confidence: nil,
            language: currentLanguage
        )
        partialResultHandler?(processingResult)

        // Move recording to permanent storage for history
        lastAudioFilePath = saveRecordingFile(from: fileURL)

        // Send to Whisper API
        let transcription = try await transcribeWithWhisper(audioData: wavData)
        log.info("Transcription: \(transcription)", tag: "Whisper")

        // Send final result
        let finalResult = SpeechRecognitionResult(
            text: transcription,
            isFinal: true,
            confidence: nil,
            language: currentLanguage
        )
        partialResultHandler?(finalResult)

        // Prepare recorder for next recording
        prepareNextRecorder()

        return transcription
    }

    func cancelRecognition() {
        log.info("Cancelling recognition...", tag: "Whisper")

        isRecording = false
        audioRecorder?.stop()
        audioRecorder = nil

        // Clean up temp file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        // Prepare recorder for next recording
        prepareNextRecorder()
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) {
        partialResultHandler = handler
    }

    func onError(_ handler: @escaping (Error) -> Void) {
        errorHandler = handler
    }

    // MARK: - File Management

    /// Move the temp recording file to permanent storage
    private func saveRecordingFile(from tempURL: URL) -> String? {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenTypeless/audio", isDirectory: true)

        do {
            try fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            let destPath = appSupportDir.appendingPathComponent("\(UUID().uuidString).wav")
            try fileManager.moveItem(at: tempURL, to: destPath)
            log.info("Audio saved to: \(destPath.path)", tag: "Whisper")
            return destPath.path
        } catch {
            log.info("Failed to save audio file: \(error)", tag: "Whisper")
            return nil
        }
    }

    // MARK: - Whisper API

    /// Send audio data to Azure OpenAI Whisper API for transcription
    private func transcribeWithWhisper(audioData: Data) async throws -> String {
        guard let endpoint = endpoint, let deployment = deployment, let key = apiKey else {
            throw SpeechRecognitionError.apiKeyMissing
        }

        // Build URL
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let urlString = "\(baseURL)/openai/deployments/\(deployment)/audio/transcriptions?api-version=\(apiVersion)"

        guard let url = URL(string: urlString) else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Invalid endpoint URL")
        }

        log.debug("API URL: \(urlString)", tag: "Whisper")

        // Build multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        // Build multipart body
        var body = Data()

        // File field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        // Language field (convert BCP-47 to ISO 639-1 for Whisper)
        let whisperLanguage = convertToWhisperLanguage(currentLanguage)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append("\(whisperLanguage)\r\n")

        // Response format
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("json\r\n")

        // End boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        log.debug("Sending \(audioData.count) bytes to API (language: \(whisperLanguage))...", tag: "Whisper")

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechRecognitionError.networkError(underlying: URLError(.badServerResponse))
        }

        log.info("HTTP status: \(httpResponse.statusCode)", tag: "Whisper")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.info("API error: \(errorBody)", tag: "Whisper")

            if httpResponse.statusCode == 429 {
                log.info("Rate limit reached (HTTP 429)", tag: "Whisper")
                throw SpeechRecognitionError.rateLimited
            }

            throw SpeechRecognitionError.recognitionFailed(reason: "API returned status \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse response
        struct WhisperResponse: Decodable {
            let text: String
        }

        let whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return whisperResponse.text
    }

    /// Convert BCP-47 language code to ISO 639-1 code for Whisper
    private func convertToWhisperLanguage(_ bcp47: String) -> String {
        let mapping: [String: String] = [
            "zh-CN": "zh",
            "zh-TW": "zh",
            "en-US": "en",
            "en-GB": "en",
            "ja-JP": "ja",
            "ko-KR": "ko",
            "fr-FR": "fr",
            "de-DE": "de",
            "es-ES": "es",
            "pt-BR": "pt",
        ]
        return mapping[bcp47] ?? String(bcp47.prefix(2))
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
