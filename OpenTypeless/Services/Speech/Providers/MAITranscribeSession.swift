import Foundation

struct MAITranscribeConfiguration {
    static let defaultDeployment = "mai-transcribe-2-streaming"
    static let sampleRate = 16_000

    let endpoint: String
    let deployment: String
    let apiKey: String
    let language: String?

    init(endpoint: String, deployment: String, apiKey: String, language: String = "auto", globalLanguage: String = "zh-CN") {
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deployment = deployment.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = Self.languageCode(selection: language, globalLanguage: globalLanguage)
    }

    static func languageCode(selection: String, globalLanguage: String) -> String? {
        let selectedLanguage = selection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if selectedLanguage == "auto" {
            return nil
        } else {
            let resolvedLanguage = selectedLanguage.isEmpty ? globalLanguage : selectedLanguage
            return resolvedLanguage.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first.map { String($0).lowercased() }
        }
    }

    static func load(from defaults: UserDefaults, globalLanguage: String) -> MAITranscribeConfiguration {
        MAITranscribeConfiguration(
            endpoint: defaults.string(forKey: "maiTranscribeEndpoint") ?? "",
            deployment: defaults.string(forKey: "maiTranscribeDeployment") ?? defaultDeployment,
            apiKey: defaults.string(forKey: "maiTranscribeAPIKey") ?? "",
            language: defaults.string(forKey: "maiTranscribeLanguage") ?? "auto",
            globalLanguage: globalLanguage
        )
    }

    func webSocketRequest() throws -> URLRequest {
        guard !endpoint.isEmpty, !deployment.isEmpty, !apiKey.isEmpty else {
            throw SpeechRecognitionError.recognitionFailed(reason: "请在 MAI 设置中填写 Foundry Endpoint、部署名称和 API Key。")
        }
        guard var components = URLComponents(string: endpoint),
              components.scheme == "https" || components.scheme == "wss",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI Endpoint 必须是 HTTPS 资源根地址，例如 https://your-resource.services.ai.azure.com，不能包含路径、查询参数或凭据。")
        }
        components.scheme = "wss"
        components.path = "/mai/v1/realtime"
        components.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = components.url else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI Endpoint 无效。")
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        return request
    }

    var sessionUpdate: [String: Any] {
        var transcription: [String: Any] = ["model": deployment]
        if let language { transcription["language"] = language }
        return [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Self.sampleRate],
                        "transcription": transcription,
                        "turn_detection": NSNull(),
                        "noise_reduction": NSNull()
                    ]
                ]
            ]
        ]
    }
}

final class MAITranscribeSession: @unchecked Sendable {
    private enum Phase { case idle, connecting, configuring, streaming, finishing, completed, failed }

    let id = UUID()
    let configuration: MAITranscribeConfiguration
    private let queue = DispatchQueue(label: "OpenTypeless.MAITranscribeSession")
    private let onFailure: (Error) -> Void
    private var phase = Phase.idle
    private var failure: Error?
    private var finalizedText = ""
    private var intermediateText = ""
    private var finalText = ""
    private var send: (([String: Any]) -> Void)?
    private var connectionWaiter: CheckedContinuation<Void, Error>?
    private var completionWaiter: CheckedContinuation<String, Error>?
    private var timeout: DispatchWorkItem?

    init(configuration: MAITranscribeConfiguration, onFailure: @escaping (Error) -> Void = { _ in }) {
        self.configuration = configuration
        self.onFailure = onFailure
    }

    var isReady: Bool { queue.sync { phase == .streaming || phase == .finishing } }
    var isActive: Bool { queue.sync { phase != .completed && phase != .failed } }
    var previewText: String { queue.sync { finalizedText + intermediateText } }

    func connect(timeoutSeconds: Double = 10, send: @escaping ([String: Any]) -> Void, open: @escaping @Sendable () -> Void) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                queue.async {
                    if let failure = self.failure {
                        waiter.resume(throwing: failure)
                        return
                    }
                    guard self.phase == .idle else {
                        waiter.resume(throwing: SpeechRecognitionError.recognitionFailed(reason: "MAI 会话已启动。"))
                        return
                    }
                    self.phase = .connecting
                    self.send = send
                    self.connectionWaiter = waiter
                    self.scheduleTimeout(seconds: timeoutSeconds, reason: "MAI 连接或会话配置超时，请检查 Endpoint、部署名称和 API Key。")
                    DispatchQueue.global(qos: .userInitiated).async(execute: open)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func finish(timeoutSeconds: Double = 10) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { waiter in
                queue.async {
                    if let failure = self.failure {
                        waiter.resume(throwing: failure)
                        return
                    }
                    if self.phase == .completed {
                        waiter.resume(returning: self.finalText)
                        return
                    }
                    guard self.phase == .streaming else {
                        waiter.resume(throwing: SpeechRecognitionError.recognitionFailed(reason: "MAI 会话尚未就绪或正在结束。"))
                        return
                    }
                    self.phase = .finishing
                    self.completionWaiter = waiter
                    self.scheduleTimeout(seconds: timeoutSeconds, reason: "MAI 最终转写超时，未插入不完整的预览文本，请重试。")
                    self.send?(["type": "input_audio_buffer.commit"])
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func receive(_ event: [String: Any]) -> SpeechRecognitionResult? {
        queue.sync {
            guard phase != .failed, phase != .completed, let type = event["type"] as? String else { return nil }
            switch type {
            case "session.created":
                guard phase == .connecting else { return nil }
                phase = .configuring
                send?(configuration.sessionUpdate)
            case "session.updated":
                guard phase == .configuring else { return nil }
                phase = .streaming
                timeout?.cancel()
                timeout = nil
                connectionWaiter?.resume()
                connectionWaiter = nil
            case "conversation.item.input_audio_transcription.delta":
                guard phase == .streaming || phase == .finishing, let delta = event["delta"] as? String else { return nil }
                finalizedText += delta
                intermediateText = ""
                return result(text: finalizedText, isFinal: false)
            case "conversation.item.input_audio_transcription.intermediate":
                guard phase == .streaming || phase == .finishing, let intermediate = event["intermediate"] as? String else { return nil }
                intermediateText = intermediate
                return result(text: finalizedText + intermediateText, isFinal: false)
            case "conversation.item.input_audio_transcription.completed":
                guard phase == .finishing, let transcript = event["transcript"] as? String else { return nil }
                phase = .completed
                finalText = transcript
                finalizedText = transcript
                intermediateText = ""
                timeout?.cancel()
                timeout = nil
                completionWaiter?.resume(returning: transcript)
                completionWaiter = nil
                send = nil
                return result(text: transcript, isFinal: true)
            case "error", "conversation.item.input_audio_transcription.failed":
                let details = event["error"] as? [String: Any]
                let message = details?["message"] as? String ?? "MAI 转写服务返回错误，请检查资源、部署名称和音频格式。"
                failLocked(SpeechRecognitionError.recognitionFailed(reason: message))
            default:
                break
            }
            return nil
        }
    }

    func fail(_ error: Error) {
        queue.sync { failLocked(error) }
    }

    func cancel() {
        fail(SpeechRecognitionError.cancelled)
    }

    private func result(text: String, isFinal: Bool) -> SpeechRecognitionResult {
        SpeechRecognitionResult(text: text, isFinal: isFinal, confidence: nil, language: configuration.language)
    }

    private func scheduleTimeout(seconds: Double, reason: String) {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.failLocked(SpeechRecognitionError.recognitionFailed(reason: reason))
        }
        timeout = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func failLocked(_ error: Error) {
        guard phase != .failed, phase != .completed else { return }
        phase = .failed
        failure = error
        timeout?.cancel()
        timeout = nil
        connectionWaiter?.resume(throwing: error)
        connectionWaiter = nil
        completionWaiter?.resume(throwing: error)
        completionWaiter = nil
        send = nil
        onFailure(error)
    }
}
