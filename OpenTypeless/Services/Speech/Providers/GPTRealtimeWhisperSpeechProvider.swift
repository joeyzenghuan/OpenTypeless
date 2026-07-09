import Foundation
import AVFoundation

/// Azure OpenAI GPT Realtime Whisper implementation.
///
/// This provider streams 24kHz mono PCM16 microphone audio to Azure OpenAI's
/// realtime transcription endpoint and emits partial transcript updates as
/// server events arrive.
class GPTRealtimeWhisperSpeechProvider: NSObject, SpeechRecognitionProvider {
    private static let defaultDeployment = "gpt-realtime-whisper-globalstandard"

    // MARK: - Protocol Properties

    let name = "GPT Realtime Whisper"
    let identifier = "gpt-realtime-whisper"
    let supportsRealtime = true
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
    private var languageOverride: String = ""
    private var prompt: String = ""

    // MARK: - Audio

    private let inputSampleRate: Double = 24_000
    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private var targetAudioFormat: AVAudioFormat?
    private var isCapturing = false

    // MARK: - Realtime

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var isDisconnecting = false
    private var sessionConfiguredContinuation: CheckedContinuation<Void, Error>?
    private var sessionConfiguredTimeout: DispatchWorkItem?

    // MARK: - Transcript State

    private var finalTranscription = ""
    private var completedTranscripts: [String] = []
    private var currentPartial = ""
    private var currentLanguage = "zh-CN"
    private var lastTranscriptUpdateAt = Date.distantPast

    private var pendingAudioChunks: [Data] = []
    private let maxPendingAudioChunks = 80
    private let stateQueue = DispatchQueue(label: "OpenTypeless.GPTRealtimeWhisper")

    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    private let log = Logger.shared

    // MARK: - Initialization

    init(endpoint: String? = nil, deployment: String? = nil, apiKey: String? = nil) {
        self.endpoint = endpoint ?? UserDefaults.standard.string(forKey: "gptRealtimeWhisperEndpoint")
        self.deployment = deployment
            ?? UserDefaults.standard.string(forKey: "gptRealtimeWhisperDeployment")
            ?? Self.defaultDeployment
        self.apiKey = apiKey ?? UserDefaults.standard.string(forKey: "gptRealtimeWhisperAPIKey")
        self.languageOverride = UserDefaults.standard.string(forKey: "gptRealtimeWhisperLanguage") ?? ""
        self.prompt = UserDefaults.standard.string(forKey: "gptRealtimeWhisperPrompt") ?? ""

        super.init()

        log.info("Initialized - endpoint: \(self.endpoint ?? "not set"), deployment: \(self.deployment ?? "not set"), key configured: \(self.apiKey?.isEmpty == false ? "yes" : "no")", tag: "GPTRealtimeWhisper")
    }

    func reloadConfig() {
        endpoint = UserDefaults.standard.string(forKey: "gptRealtimeWhisperEndpoint")
        deployment = UserDefaults.standard.string(forKey: "gptRealtimeWhisperDeployment") ?? Self.defaultDeployment
        apiKey = UserDefaults.standard.string(forKey: "gptRealtimeWhisperAPIKey")
        languageOverride = UserDefaults.standard.string(forKey: "gptRealtimeWhisperLanguage") ?? ""
        prompt = UserDefaults.standard.string(forKey: "gptRealtimeWhisperPrompt") ?? ""
        log.info("Config reloaded", tag: "GPTRealtimeWhisper")
    }

    // MARK: - Protocol Methods

    func beginCapture(language: String) throws {
        currentLanguage = languageOverride.isEmpty ? language : languageOverride
        resetTranscriptState()

        guard !isCapturing else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to create realtime audio format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to create realtime audio converter")
        }

        targetAudioFormat = targetFormat
        audioConverter = converter

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isCapturing = true
            log.info("Audio capture started - input: \(inputFormat.sampleRate)Hz, realtime: \(inputSampleRate)Hz", tag: "GPTRealtimeWhisper")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription)
        }
    }

    func startRecognition(language: String) async throws {
        log.info("Starting realtime recognition - language: \(currentLanguage)", tag: "GPTRealtimeWhisper")

        guard isAvailable else {
            throw SpeechRecognitionError.apiKeyMissing
        }

        if !isCapturing {
            try beginCapture(language: language)
        }

        reloadConfig()
        currentLanguage = languageOverride.isEmpty ? language : languageOverride

        let url = try buildWebSocketURL()
        var request = URLRequest(url: url)
        request.setValue("realtime", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        isDisconnecting = false
        isConnected = false

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        urlSession = session
        webSocketTask = task

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionConfiguredContinuation = continuation

                let timeout = DispatchWorkItem { [weak self] in
                    self?.rejectSessionConfigured(
                        SpeechRecognitionError.recognitionFailed(reason: "Timed out waiting for realtime transcription session")
                    )
                }
                sessionConfiguredTimeout = timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)

                task.resume()
            }
        } catch {
            stopAudioCapture()
            disconnectWebSocket()
            throw error
        }

        flushPendingAudio()
        log.info("Realtime recognition started", tag: "GPTRealtimeWhisper")
    }

    func stopRecognition() async throws -> String {
        log.info("Stopping realtime recognition...", tag: "GPTRealtimeWhisper")

        stopAudioCapture()

        if isConnected {
            sendJSON(["type": "input_audio_buffer.commit"])
            await waitForTranscriptSettled()
        }

        disconnectWebSocket()

        stateQueue.sync {
            if finalTranscription.isEmpty, !currentPartial.isEmpty {
                finalTranscription = completedTranscripts.joined() + currentPartial
            }
        }

        log.info("Final transcription: \(finalTranscription)", tag: "GPTRealtimeWhisper")
        return finalTranscription
    }

    func cancelRecognition() {
        log.info("Cancelling realtime recognition", tag: "GPTRealtimeWhisper")
        stopAudioCapture()
        disconnectWebSocket()
        resetTranscriptState()
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) {
        partialResultHandler = handler
    }

    func onError(_ handler: @escaping (Error) -> Void) {
        errorHandler = handler
    }

    // MARK: - Audio Handling

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let pcm16Data = convertToPCM16(buffer) else { return }

        stateQueue.async { [weak self] in
            guard let self = self else { return }

            if self.isConnected {
                self.sendAudio(pcm16Data)
            } else {
                self.pendingAudioChunks.append(pcm16Data)
                if self.pendingAudioChunks.count > self.maxPendingAudioChunks {
                    self.pendingAudioChunks.removeFirst(self.pendingAudioChunks.count - self.maxPendingAudioChunks)
                }
            }
        }
    }

    private func convertToPCM16(_ inputBuffer: AVAudioPCMBuffer) -> Data? {
        guard let converter = audioConverter,
              let targetFormat = targetAudioFormat else {
            return nil
        }

        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 32

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            log.debug("Audio conversion failed: \(conversionError.localizedDescription)", tag: "GPTRealtimeWhisper")
            return nil
        }

        guard status != .error,
              convertedBuffer.frameLength > 0,
              let channelData = convertedBuffer.floatChannelData else {
            return nil
        }

        let frameCount = Int(convertedBuffer.frameLength)
        let samples = channelData[0]
        var pcmSamples = [Int16](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let sample = max(-1.0, min(1.0, samples[frame]))
            let intSample = sample < 0 ? Int16(sample * 32768) : Int16(sample * 32767)
            pcmSamples[frame] = intSample.littleEndian
        }

        return pcmSamples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func stopAudioCapture() {
        guard isCapturing else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioConverter = nil
        targetAudioFormat = nil
        isCapturing = false

        log.info("Audio capture stopped", tag: "GPTRealtimeWhisper")
    }

    // MARK: - WebSocket

    private func buildWebSocketURL() throws -> URL {
        guard let endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              let deployment = deployment?.trimmingCharacters(in: .whitespacesAndNewlines),
              let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty, !deployment.isEmpty, !apiKey.isEmpty else {
            throw SpeechRecognitionError.apiKeyMissing
        }

        let baseURLString = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        guard let baseURL = URL(string: baseURLString),
              let host = baseURL.host else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Invalid realtime endpoint URL")
        }

        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = baseURL.port
        components.path = "/openai/v1/realtime"
        components.queryItems = [
            URLQueryItem(name: "deployment", value: deployment),
            URLQueryItem(name: "intent", value: "transcription"),
            URLQueryItem(name: "api-key", value: apiKey)
        ]

        guard let url = components.url else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Failed to build realtime WebSocket URL")
        }

        return url
    }

    private func sendSessionUpdate() {
        guard let deployment = deployment, !deployment.isEmpty else { return }

        var transcription: [String: Any] = [
            "model": deployment
        ]

        let lang = convertToRealtimeLanguage(currentLanguage)
        if !lang.isEmpty {
            transcription["language"] = lang
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            transcription["prompt"] = trimmedPrompt
        }

        let sessionConfig: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(inputSampleRate)
                        ],
                        "transcription": transcription,
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 500
                        ]
                    ]
                ]
            ]
        ]

        sendJSON(sessionConfig)
        log.debug("Session update sent - language: \(lang), prompt configured: \(!trimmedPrompt.isEmpty)", tag: "GPTRealtimeWhisper")
    }

    private func sendAudio(_ data: Data) {
        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]

        sendJSON(message)
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let webSocketTask = webSocketTask else { return }

        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let string = String(data: data, encoding: .utf8) else { return }
            webSocketTask.send(.string(string)) { [weak self] error in
                if let error {
                    self?.handleError(SpeechRecognitionError.networkError(underlying: error))
                }
            }
        } catch {
            handleError(SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription))
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                if !self.isDisconnecting {
                    self.receiveLoop()
                }

            case .failure(let error):
                if !self.isDisconnecting {
                    self.handleError(SpeechRecognitionError.networkError(underlying: error))
                    self.rejectSessionConfigured(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?

        switch message {
        case .string(let string):
            data = string.data(using: .utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard let data = data else { return }

        do {
            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            handleServerEvent(event)
        } catch {
            log.debug("Failed to parse realtime message: \(error.localizedDescription)", tag: "GPTRealtimeWhisper")
        }
    }

    private func handleServerEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            stateQueue.async { [weak self] in
                self?.isConnected = true
                self?.flushPendingAudio()
            }
            resolveSessionConfigured()
            log.info("Realtime session configured: \(type)", tag: "GPTRealtimeWhisper")

        case "input_audio_buffer.speech_started":
            log.debug("Speech started", tag: "GPTRealtimeWhisper")

        case "session.input_transcript.delta", "conversation.item.input_audio_transcription.delta":
            if let delta = event["delta"] as? String, !delta.isEmpty {
                appendTranscriptDelta(delta)
            }

        case "conversation.item.input_audio_transcription.completed":
            let transcript = event["transcript"] as? String
            completeTranscript(transcript)

        case "response.done", "session.closed":
            completeTranscript(nil)

        case "error":
            let message = extractErrorMessage(from: event)
            rejectSessionConfigured(SpeechRecognitionError.recognitionFailed(reason: message))
            handleError(SpeechRecognitionError.recognitionFailed(reason: message))

        default:
            log.debug("Unhandled realtime event: \(type)", tag: "GPTRealtimeWhisper")
        }
    }

    private func flushPendingAudio() {
        stateQueue.async { [weak self] in
            guard let self = self, self.isConnected, !self.pendingAudioChunks.isEmpty else { return }
            let chunks = self.pendingAudioChunks
            self.pendingAudioChunks.removeAll()
            chunks.forEach { self.sendAudio($0) }
            self.log.debug("Flushed \(chunks.count) pending audio chunks", tag: "GPTRealtimeWhisper")
        }
    }

    private func disconnectWebSocket() {
        isDisconnecting = true
        rejectSessionConfigured(SpeechRecognitionError.cancelled)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        pendingAudioChunks.removeAll()
    }

    // MARK: - Transcript Helpers

    private func appendTranscriptDelta(_ delta: String) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            self.currentPartial += delta
            self.finalTranscription = self.completedTranscripts.joined() + self.currentPartial
            self.lastTranscriptUpdateAt = Date()

            let result = SpeechRecognitionResult(
                text: self.finalTranscription,
                isFinal: false,
                confidence: nil,
                language: self.currentLanguage
            )
            self.partialResultHandler?(result)
        }
    }

    private func completeTranscript(_ transcript: String?) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }

            let finalSegment = (transcript?.isEmpty == false ? transcript : self.currentPartial) ?? self.currentPartial
            if !finalSegment.isEmpty {
                self.completedTranscripts.append(finalSegment)
            }

            self.currentPartial = ""
            self.finalTranscription = self.completedTranscripts.joined()
            self.lastTranscriptUpdateAt = Date()

            let result = SpeechRecognitionResult(
                text: self.finalTranscription,
                isFinal: true,
                confidence: nil,
                language: self.currentLanguage
            )
            self.partialResultHandler?(result)
        }
    }

    private func resetTranscriptState() {
        stateQueue.sync {
            finalTranscription = ""
            completedTranscripts = []
            currentPartial = ""
            pendingAudioChunks = []
            lastTranscriptUpdateAt = Date.distantPast
        }
    }

    private func waitForTranscriptSettled() async {
        let startedAt = Date()

        while Date().timeIntervalSince(startedAt) < 2.0 {
            let shouldReturn = stateQueue.sync {
                !finalTranscription.isEmpty && Date().timeIntervalSince(lastTranscriptUpdateAt) > 0.35
            }

            if shouldReturn {
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func convertToRealtimeLanguage(_ bcp47: String) -> String {
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
            "it-IT": "it",
            "pt-BR": "pt",
            "ru-RU": "ru"
        ]

        return mapping[bcp47] ?? String(bcp47.prefix(2)).lowercased()
    }

    private func extractErrorMessage(from event: [String: Any]) -> String {
        if let error = event["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            return String(describing: error)
        }

        return "Unknown realtime transcription error"
    }

    private func resolveSessionConfigured() {
        sessionConfiguredTimeout?.cancel()
        sessionConfiguredTimeout = nil
        sessionConfiguredContinuation?.resume()
        sessionConfiguredContinuation = nil
    }

    private func rejectSessionConfigured(_ error: Error) {
        sessionConfiguredTimeout?.cancel()
        sessionConfiguredTimeout = nil
        sessionConfiguredContinuation?.resume(throwing: error)
        sessionConfiguredContinuation = nil
    }

    private func handleError(_ error: Error) {
        log.info("Realtime error: \(error.localizedDescription)", tag: "GPTRealtimeWhisper")
        errorHandler?(error)
    }
}

extension GPTRealtimeWhisperSpeechProvider: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        log.info("WebSocket connected", tag: "GPTRealtimeWhisper")
        receiveLoop()
        sendSessionUpdate()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        log.info("WebSocket closed: \(closeCode.rawValue) \(reasonText)", tag: "GPTRealtimeWhisper")

        stateQueue.async { [weak self] in
            self?.isConnected = false
        }

        if !isDisconnecting {
            rejectSessionConfigured(
                SpeechRecognitionError.recognitionFailed(reason: reasonText.isEmpty ? "Realtime WebSocket closed" : reasonText)
            )
        }
    }
}
