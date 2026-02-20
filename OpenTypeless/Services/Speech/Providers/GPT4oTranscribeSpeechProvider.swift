import Foundation
import AVFoundation

/// Azure OpenAI GPT-4o Transcribe API implementation
///
/// This provider captures audio from the microphone using AVAudioRecorder,
/// then sends the complete audio file to the Azure OpenAI GPT-4o Transcribe API
/// for transcription when recognition is stopped.
///
/// Compared to Whisper, GPT-4o Transcribe offers better accuracy, optional
/// logprobs (confidence scores), and full prompt support.
///
/// Setup:
/// 1. Deploy a gpt-4o-transcribe model in your Azure OpenAI resource
/// 2. Configure endpoint, deployment name, and API key in Settings
///
/// Documentation: https://learn.microsoft.com/azure/ai-services/openai/whisper-quickstart
class GPT4oTranscribeSpeechProvider: SpeechRecognitionProvider {

    // MARK: - Protocol Properties

    let name = "GPT-4o Transcribe"
    let identifier = "gpt4o-transcribe"
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
    private var temperature: Double = 0
    private var prompt: String = ""
    private var logprobs: Bool = false
    private var languageOverride: String = ""
    private let apiVersion = "2025-03-01-preview"

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

    /// Recording settings: 16kHz mono 16-bit PCM (optimal for transcription)
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
        self.endpoint = endpoint ?? UserDefaults.standard.string(forKey: "gpt4oTranscribeEndpoint")
        self.deployment = deployment ?? UserDefaults.standard.string(forKey: "gpt4oTranscribeDeployment")
        self.apiKey = apiKey ?? UserDefaults.standard.string(forKey: "gpt4oTranscribeAPIKey")
        self.temperature = UserDefaults.standard.double(forKey: "gpt4oTranscribeTemperature")
        self.prompt = UserDefaults.standard.string(forKey: "gpt4oTranscribePrompt") ?? ""
        self.logprobs = UserDefaults.standard.bool(forKey: "gpt4oTranscribeLogprobs")
        self.languageOverride = UserDefaults.standard.string(forKey: "gpt4oTranscribeLanguage") ?? ""

        log.info("Initialized", tag: "GPT4o-Transcribe")
        log.debug("Endpoint: \(self.endpoint ?? "not set")", tag: "GPT4o-Transcribe")
        log.debug("Deployment: \(self.deployment ?? "not set")", tag: "GPT4o-Transcribe")
        log.debug("Key configured: \(self.apiKey?.isEmpty == false ? "yes" : "no")", tag: "GPT4o-Transcribe")
        log.debug("Temperature: \(self.temperature)", tag: "GPT4o-Transcribe")
        log.debug("Prompt: \(self.prompt.isEmpty ? "(empty)" : self.prompt.prefix(50) + "...")", tag: "GPT4o-Transcribe")
        log.debug("Logprobs: \(self.logprobs)", tag: "GPT4o-Transcribe")
        log.debug("Language override: \(self.languageOverride.isEmpty ? "(global)" : self.languageOverride)", tag: "GPT4o-Transcribe")

        // Pre-warm the audio hardware so the first recording starts instantly
        prepareNextRecorder()
    }

    // MARK: - Configuration

    func reloadConfig() {
        self.endpoint = UserDefaults.standard.string(forKey: "gpt4oTranscribeEndpoint")
        self.deployment = UserDefaults.standard.string(forKey: "gpt4oTranscribeDeployment")
        self.apiKey = UserDefaults.standard.string(forKey: "gpt4oTranscribeAPIKey")
        self.temperature = UserDefaults.standard.double(forKey: "gpt4oTranscribeTemperature")
        self.prompt = UserDefaults.standard.string(forKey: "gpt4oTranscribePrompt") ?? ""
        self.logprobs = UserDefaults.standard.bool(forKey: "gpt4oTranscribeLogprobs")
        self.languageOverride = UserDefaults.standard.string(forKey: "gpt4oTranscribeLanguage") ?? ""
        log.info("Config reloaded", tag: "GPT4o-Transcribe")
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
            log.debug("Recorder prepared: \(fileURL.lastPathComponent)", tag: "GPT4o-Transcribe")
        } catch {
            log.info("Failed to prepare recorder: \(error)", tag: "GPT4o-Transcribe")
            audioRecorder = nil
        }
    }

    /// Synchronously start audio recording — called before any UI work.
    /// The recorder is already prepared (audio hardware warmed up), so record() is instant.
    func beginCapture(language: String) throws {
        guard isAvailable else {
            log.info("Not configured", tag: "GPT4o-Transcribe")
            throw SpeechRecognitionError.apiKeyMissing
        }

        currentLanguage = languageOverride.isEmpty ? language : languageOverride

        // If no prepared recorder (shouldn't happen), create one on the fly
        if audioRecorder == nil {
            prepareNextRecorder()
        }

        guard let recorder = audioRecorder else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to initialize recorder")
        }

        guard recorder.record() else {
            log.info("AVAudioRecorder.record() returned false", tag: "GPT4o-Transcribe")
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to start audio recording")
        }

        isRecording = true
        log.info("Recording started: \(recordingURL?.lastPathComponent ?? "?")", tag: "GPT4o-Transcribe")
    }

    func startRecognition(language: String) async throws {
        // Recording already started by beginCapture().
        // If beginCapture wasn't called (e.g. other code paths), start here as fallback.
        if !isRecording {
            try beginCapture(language: language)
        }

        log.debug("Endpoint: \(endpoint ?? "unknown"), Deployment: \(deployment ?? "unknown")", tag: "GPT4o-Transcribe")

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
        log.info("Stopping recognition...", tag: "GPT4o-Transcribe")

        // Stop recording
        isRecording = false
        audioRecorder?.stop()
        audioRecorder = nil

        guard let fileURL = recordingURL else {
            log.info("No recording URL", tag: "GPT4o-Transcribe")
            prepareNextRecorder()
            return ""
        }

        // Read the recorded WAV file
        let wavData: Data
        do {
            wavData = try Data(contentsOf: fileURL)
        } catch {
            log.info("Failed to read recording file: \(error)", tag: "GPT4o-Transcribe")
            return ""
        }

        log.debug("WAV data size: \(wavData.count) bytes (\(String(format: "%.1f", Double(wavData.count) / 1024 / 1024)) MB)", tag: "GPT4o-Transcribe")

        // A valid WAV header is 44 bytes; anything less means no actual audio
        guard wavData.count > 44 else {
            log.info("No audio recorded (file too small)", tag: "GPT4o-Transcribe")
            try? FileManager.default.removeItem(at: fileURL)
            return ""
        }

        // Check file size limit (25 MB)
        guard wavData.count <= 25 * 1024 * 1024 else {
            log.info("Audio too large (>25MB)", tag: "GPT4o-Transcribe")
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

        // Send to GPT-4o Transcribe API
        let transcription = try await transcribeWithGPT4o(audioData: wavData)
        log.info("Transcription: \(transcription)", tag: "GPT4o-Transcribe")

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
        log.info("Cancelling recognition...", tag: "GPT4o-Transcribe")

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
            log.info("Audio saved to: \(destPath.path)", tag: "GPT4o-Transcribe")
            return destPath.path
        } catch {
            log.info("Failed to save audio file: \(error)", tag: "GPT4o-Transcribe")
            return nil
        }
    }

    // MARK: - GPT-4o Transcribe API

    /// Send audio data to Azure OpenAI GPT-4o Transcribe API for transcription
    private func transcribeWithGPT4o(audioData: Data) async throws -> String {
        guard let endpoint = endpoint, let deployment = deployment, let key = apiKey else {
            throw SpeechRecognitionError.apiKeyMissing
        }

        // Build URL
        let baseURL = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let urlString = "\(baseURL)/openai/deployments/\(deployment)/audio/transcriptions?api-version=\(apiVersion)"

        guard let url = URL(string: urlString) else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Invalid endpoint URL")
        }

        log.debug("API URL: \(urlString)", tag: "GPT4o-Transcribe")

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

        // Language field (convert BCP-47 to ISO 639-1)
        let lang = convertToWhisperLanguage(currentLanguage)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append("\(lang)\r\n")

        // Response format
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("json\r\n")

        // Temperature (when non-zero)
        if temperature > 0 {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
            body.append("\(temperature)\r\n")
        }

        // Prompt (when non-empty)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            body.append("\(trimmedPrompt)\r\n")
        }

        // Logprobs (when enabled)
        if logprobs {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"include[]\"\r\n\r\n")
            body.append("logprobs\r\n")
        }

        // End boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        log.debug("Sending \(audioData.count) bytes to API (language: \(lang), temperature: \(temperature), logprobs: \(logprobs))...", tag: "GPT4o-Transcribe")

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechRecognitionError.networkError(underlying: URLError(.badServerResponse))
        }

        log.info("HTTP status: \(httpResponse.statusCode)", tag: "GPT4o-Transcribe")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.info("API error: \(errorBody)", tag: "GPT4o-Transcribe")

            if httpResponse.statusCode == 429 {
                log.info("Rate limit reached (HTTP 429)", tag: "GPT4o-Transcribe")
                throw SpeechRecognitionError.rateLimited
            }

            throw SpeechRecognitionError.recognitionFailed(reason: "API returned status \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse response
        struct GPT4oTranscribeResponse: Decodable {
            let text: String
            let logprobs: Logprobs?

            struct Logprobs: Decodable {
                let tokens: [Token]?

                struct Token: Decodable {
                    let token: String?
                    let logprob: Double?
                }
            }
        }

        let transcribeResponse = try JSONDecoder().decode(GPT4oTranscribeResponse.self, from: data)

        // Log average confidence when logprobs are available
        if let logprobsData = transcribeResponse.logprobs, let tokens = logprobsData.tokens, !tokens.isEmpty {
            let logprobValues = tokens.compactMap { $0.logprob }
            if !logprobValues.isEmpty {
                let avgLogprob = logprobValues.reduce(0, +) / Double(logprobValues.count)
                let avgConfidence = exp(avgLogprob)
                log.debug("Average confidence: \(String(format: "%.2f%%", avgConfidence * 100)) (avg logprob: \(String(format: "%.4f", avgLogprob)), \(logprobValues.count) tokens)", tag: "GPT4o-Transcribe")
            }
        }

        return transcribeResponse.text
    }

    /// Convert BCP-47 language code to ISO 639-1 code
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
