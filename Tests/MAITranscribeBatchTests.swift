import Foundation

private final class MAIBatchURLProtocol: URLProtocol {
    static var statusCode = 200
    static var payload = Data()
    static var waitsForCancellation = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard !Self.waitsForCancellation else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct MAITranscribeBatchTests {
    private static func check(_ condition: Bool, _ message: String) throws {
        try MAITranscribeSessionTests.check(condition, message)
    }

    static func run() async throws {
        try testConfiguration()
        try testMultipart()
        try await testResponses()
        print("All MAI Transcribe batch tests passed")
    }

    private static func testConfiguration() throws {
        let configuration = MAITranscribeBatchConfiguration(endpoint: " https://example.cognitiveservices.azure.com/ ",
            apiKey: " test-key ", language: "zh-CN", style: "clean", phrases: [" OpenTypeless ", "", "Azure"])
        let url = try configuration.requestURL()
        try check(url.absoluteString == "https://example.cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15",
            "Batch uses the Speech API, not the OpenAI deployment API")
        let definition = configuration.definition
        let enhanced = definition["enhancedMode"] as! [String: Any]
        let options = enhanced["modelOptions"] as! [String: Any]
        try check(enhanced["enabled"] as? Bool == true && enhanced["model"] as? String == "MAI-Transcribe-2", "Must explicitly select MAI-Transcribe-2")
        try check(options["transcribeStyle"] as? String == "clean" && options["timestamps"] as? String == "none", "Style and timestamps")
        try check(definition["locales"] as? [String] == ["zh"], "Only one locale hint")
        try check((definition["phraseList"] as? [String: Any])?["phrases"] as? [String] == ["OpenTypeless", "Azure"], "Trim terminology hints")
        let auto = MAITranscribeBatchConfiguration(endpoint: configuration.endpoint, apiKey: "key")
        try check(auto.definition["locales"] == nil && auto.definition["phraseList"] == nil, "Auto detection omits optional hints")
        let global = MAITranscribeBatchConfiguration(endpoint: configuration.endpoint, apiKey: "key", language: "", globalLanguage: "pt-BR")
        try check(global.language == "pt", "Can follow global language")
        for endpoint in ["http://example.com", "https://example.com/path", "https://example.com?key=secret",
                         "https://user:password@example.com", "https://example.com#fragment"] {
            try MAITranscribeSessionTests.expectFailure {
                _ = try MAITranscribeBatchConfiguration(endpoint: endpoint, apiKey: "key").requestURL()
            }
        }
        try MAITranscribeSessionTests.expectFailure {
            _ = try MAITranscribeBatchConfiguration(endpoint: configuration.endpoint, apiKey: " ").requestURL()
        }
        try MAITranscribeSessionTests.expectFailure {
            _ = try MAITranscribeBatchConfiguration(endpoint: configuration.endpoint, apiKey: "key", style: "unsupported").requestURL()
        }
        let suite = "OpenTypeless.MAIBatchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("shared-test-key", forKey: "azureSpeechKey")
        defaults.set("swedencentral", forKey: "azureSpeechRegion")
        let shared = MAITranscribeBatchConfiguration.load(from: defaults, globalLanguage: "zh-CN")
        try check(shared.endpoint == "https://swedencentral.api.cognitive.microsoft.com" && shared.apiKey == "shared-test-key", "Default explicitly reuses Speech credentials")
        try check(shared.timeout == 60, "Unset timeout defaults to 60 seconds")
        defaults.set(false, forKey: "maiTranscribeBatchUseAzureSpeech")
        defaults.set("https://independent.cognitiveservices.azure.com", forKey: "maiTranscribeBatchEndpoint")
        defaults.set("independent-test-key", forKey: "maiTranscribeBatchAPIKey")
        defaults.set(" one \n\n two ", forKey: "maiTranscribeBatchPhrases")
        defaults.set(999.0, forKey: "apiTimeout")
        let independent = MAITranscribeBatchConfiguration.load(from: defaults, globalLanguage: "zh-CN")
        try check(independent.apiKey == "independent-test-key" && independent.endpoint.contains("independent"), "Independent settings never silently reuse a different key")
        try check(independent.phrases == ["one", "two"] && independent.timeout == 240, "Terminology and bounded timeout")
    }

    private static func testMultipart() throws {
        let audio = Data(repeating: 1, count: 100)
        let configuration = MAITranscribeBatchConfiguration(endpoint: "https://example.com", apiKey: "secret")
        let request = try MAITranscribeBatchClient().request(audio: audio, configuration: configuration)
        try check(request.httpMethod == "POST" && request.timeoutInterval == 60, "HTTP method and timeout")
        try check(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "secret", "Speech subscription key header")
        try check(request.value(forHTTPHeaderField: "api-key") == nil && request.url?.query?.contains("secret") == false, "No OpenAI header or URL credential")
        let body = request.httpBody!
        let text = String(decoding: body, as: UTF8.self)
        let contentType = request.value(forHTTPHeaderField: "Content-Type")!
        let boundary = contentType.components(separatedBy: "boundary=")[1]
        try check(text.contains("name=\"definition\"") && text.contains("MAI-Transcribe-2") && text.contains("name=\"audio\""), "Two multipart fields and explicit model")
        try check(text.hasSuffix("\r\n--\(boundary)--\r\n") && body.range(of: audio) != nil, "Complete multipart with unchanged binary audio")
        try check(!text.contains("secret"), "Credential never appears in multipart body")
        try MAITranscribeSessionTests.expectFailure { _ = try MAITranscribeBatchClient().request(audio: Data(), configuration: configuration) }
    }

    private static func testResponses() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MAIBatchURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let client = MAITranscribeBatchClient(session: session)
        let configuration = MAITranscribeBatchConfiguration(endpoint: "https://example.com", apiKey: "key")
        let audio = Data(repeating: 0, count: 100)
        MAIBatchURLProtocol.statusCode = 200
        for payload in ["{\"combinedPhrases\":[{\"channel\":0,\"text\":\"你好，Azure。\"}]}",
                        "{\"combinedPhrases\":[{\"text\":\"你好，Azure。\"}]}"] {
            MAIBatchURLProtocol.payload = Data(payload.utf8)
            let text = try await client.transcribe(audio: audio, configuration: configuration)
            try check(text == "你好，Azure。", "Parse authoritative combined text")
        }
        MAIBatchURLProtocol.payload = Data("{\"combinedPhrases\":[]}".utf8)
        let silence = try await client.transcribe(audio: audio, configuration: configuration)
        try check(silence.isEmpty, "Silence produces no clipboard text")
        for payload in ["{}", "not-json", "{\"combinedPhrases\":[{\"channel\":1,\"text\":\"wrong channel\"}]}",
                        "{\"combinedPhrases\":[{\"channel\":0}]}"] {
            MAIBatchURLProtocol.payload = Data(payload.utf8)
            try await MAITranscribeSessionTests.expectNoOutput { try await client.transcribe(audio: audio, configuration: configuration) }
        }
        MAIBatchURLProtocol.statusCode = 403
        MAIBatchURLProtocol.payload = Data("{\"error\":{\"message\":\"Model unavailable\"}}".utf8)
        do {
            _ = try await client.transcribe(audio: audio, configuration: configuration)
            try check(false, "HTTP errors cannot return text")
        } catch {
            try check(error.localizedDescription.contains("403") && error.localizedDescription.contains("Model unavailable"), "Surface HTTP status and service error")
        }
        MAIBatchURLProtocol.waitsForCancellation = true
        defer { MAIBatchURLProtocol.waitsForCancellation = false }
        let task = Task { try await client.transcribe(audio: audio, configuration: configuration) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        try await MAITranscribeSessionTests.expectNoOutput { try await task.value }
    }
}
