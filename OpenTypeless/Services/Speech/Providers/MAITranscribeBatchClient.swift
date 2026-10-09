import Foundation

struct MAITranscribeBatchConfiguration {
    static let model = "MAI-Transcribe-2"
    let endpoint: String
    let apiKey: String
    let language: String?
    let style: String
    let phrases: [String]
    let timeout: Double

    init(endpoint: String, apiKey: String, language: String = "auto", globalLanguage: String = "zh-CN",
         style: String = "verbatim", phrases: [String] = [], timeout: Double = 60) {
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = MAITranscribeConfiguration.languageCode(selection: language, globalLanguage: globalLanguage)
        self.style = style
        self.phrases = phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.timeout = timeout.isFinite ? max(10, min(timeout, 240)) : 60
    }

    static func load(from defaults: UserDefaults, globalLanguage: String) -> MAITranscribeBatchConfiguration {
        let reuseSpeech = defaults.object(forKey: "maiTranscribeBatchUseAzureSpeech") as? Bool ?? true
        let regionKey = reuseSpeech ? "azureSpeechRegion" : "maiTranscribeBatchRegion"
        let region = (defaults.string(forKey: regionKey) ?? "swedencentral").trimmingCharacters(in: .whitespacesAndNewlines)
        let customEndpoint = reuseSpeech ? "" : (defaults.string(forKey: "maiTranscribeBatchEndpoint") ?? "")
        let endpoint = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://\(region).api.cognitive.microsoft.com" : customEndpoint
        return MAITranscribeBatchConfiguration(endpoint: endpoint,
            apiKey: defaults.string(forKey: reuseSpeech ? "azureSpeechKey" : "maiTranscribeBatchAPIKey") ?? "",
            language: defaults.string(forKey: "maiTranscribeBatchLanguage") ?? "auto", globalLanguage: globalLanguage,
            style: defaults.string(forKey: "maiTranscribeBatchStyle") ?? "verbatim",
            phrases: (defaults.string(forKey: "maiTranscribeBatchPhrases") ?? "").components(separatedBy: .newlines),
            timeout: defaults.object(forKey: "apiTimeout") as? Double ?? 60)
    }

    func requestURL() throws -> URL {
        guard !apiKey.isEmpty else {
            throw SpeechRecognitionError.recognitionFailed(reason: "请配置 Azure Speech Key，或在 MAI 非流式设置中填写独立的 API Key。")
        }
        guard style == "verbatim" || style == "clean" else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 转写风格必须是 verbatim 或 clean。")
        }
        guard var components = URLComponents(string: endpoint), components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 非流式 Endpoint 必须是 HTTPS 资源根地址，不能包含路径、查询参数或凭据。")
        }
        components.path = "/speechtotext/transcriptions:transcribe"
        components.queryItems = [URLQueryItem(name: "api-version", value: "2025-10-15")]
        guard let url = components.url else { throw SpeechRecognitionError.notAvailable }
        return url
    }

    var definition: [String: Any] {
        var definition: [String: Any] = ["enhancedMode": [
            "enabled": true, "model": Self.model,
            "modelOptions": ["transcribeStyle": style, "timestamps": "none"]
        ]]
        if let language { definition["locales"] = [language] }
        if !phrases.isEmpty { definition["phraseList"] = ["phrases": phrases] }
        return definition
    }
}

struct MAITranscribeBatchClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func request(audio: Data, configuration: MAITranscribeBatchConfiguration) throws -> URLRequest {
        guard audio.count > 44, audio.count < 250 * 1024 * 1024 else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 音频为空或超过 250 MB 限制。")
        }
        let boundary = "OpenTypeless-MAI-\(UUID().uuidString)"
        let definition = try JSONSerialization.data(withJSONObject: configuration.definition)
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"definition\"\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(definition)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: try configuration.requestURL())
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue(configuration.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    func transcribe(audio: Data, configuration: MAITranscribeBatchConfiguration) async throws -> String {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request(audio: audio, configuration: configuration))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw SpeechRecognitionError.notAvailable }
        guard response.statusCode == 200 else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let details = object?["error"] as? [String: Any]
            let message = details?["message"] as? String ?? "请检查 Key、区域、模型可用性和音频格式。"
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI HTTP \(response.statusCode)：\(message)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let combined = object["combinedPhrases"] as? [[String: Any]] else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 返回了无效的最终转写结果。")
        }
        if combined.isEmpty { return "" }
        guard let phrase = combined.first(where: { ($0["channel"] as? Int ?? 0) == 0 }),
              let text = phrase["text"] as? String else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 返回的结果缺少单声道最终文本。")
        }
        return text
    }
}
