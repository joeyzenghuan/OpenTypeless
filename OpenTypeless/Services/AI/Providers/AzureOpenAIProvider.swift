import Foundation

/// API type for Azure OpenAI
enum AzureOpenAIAPIType: String {
    case chatCompletions = "chat-completions"
    case responses = "responses"

    var displayName: String {
        switch self {
        case .chatCompletions: return "Chat Completions API"
        case .responses: return "Responses API"
        }
    }
}

/// Azure OpenAI Service implementation
class AzureOpenAIProvider: AIProvider {

    // MARK: - Protocol Properties

    let name = "Azure OpenAI"
    let identifier = "azure-openai"

    var isAvailable: Bool {
        return !endpoint.isEmpty && !deploymentName.isEmpty && !apiKey.isEmpty
    }

    // MARK: - Configuration

    private var endpoint: String
    private var deploymentName: String
    private var apiKey: String
    private var apiVersion: String
    private var apiType: AzureOpenAIAPIType

    private let log = Logger.shared

    // MARK: - Initialization

    init() {
        let defaults = UserDefaults.standard
        self.endpoint = defaults.string(forKey: "azureOpenAIEndpoint") ?? ""
        self.deploymentName = defaults.string(forKey: "azureOpenAIDeployment") ?? ""
        self.apiKey = defaults.string(forKey: "azureOpenAIKey") ?? ""
        self.apiVersion = defaults.string(forKey: "azureOpenAIVersion") ?? "2024-02-15-preview"
        self.apiType = AzureOpenAIAPIType(rawValue: defaults.string(forKey: "azureOpenAIAPIType") ?? "chat-completions") ?? .chatCompletions

        log.info("Initialized - endpoint: \(endpoint.isEmpty ? "not set" : "configured"), API type: \(apiType.displayName)", tag: "AzureOpenAI")
    }

    func reloadConfig() {
        let defaults = UserDefaults.standard
        self.endpoint = defaults.string(forKey: "azureOpenAIEndpoint") ?? ""
        self.deploymentName = defaults.string(forKey: "azureOpenAIDeployment") ?? ""
        self.apiKey = defaults.string(forKey: "azureOpenAIKey") ?? ""
        self.apiVersion = defaults.string(forKey: "azureOpenAIVersion") ?? "2024-02-15-preview"
        self.apiType = AzureOpenAIAPIType(rawValue: defaults.string(forKey: "azureOpenAIAPIType") ?? "chat-completions") ?? .chatCompletions
        log.info("Config reloaded - API type: \(apiType.displayName)", tag: "AzureOpenAI")
    }

    /// Read timeout from user settings (default 10s)
    private var timeout: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "apiTimeout")
        return value > 0 ? value : 10.0
    }

    // MARK: - AI Processing

    func polish(text: String, systemPrompt: String) async throws -> String {
        let result = try await polishWithMetadata(text: text, systemPrompt: systemPrompt)
        return result.text
    }

    func polishWithMetadata(text: String, systemPrompt: String) async throws -> AIPolishResult {
        guard isAvailable else {
            log.info("Not configured", tag: "AzureOpenAI")
            throw AIProviderError.notConfigured
        }

        log.info("Polishing text (\(text.count) chars), API type: \(apiType.displayName)", tag: "AzureOpenAI")
        log.debug("Input text: \(text)", tag: "AzureOpenAI")
        log.debug("System prompt: \(systemPrompt)", tag: "AzureOpenAI")

        let startTime = Date()
        let polishedText: String
        switch apiType {
        case .chatCompletions:
            polishedText = try await polishWithChatCompletions(text: text, systemPrompt: systemPrompt)
        case .responses:
            polishedText = try await polishWithResponsesAPI(text: text, systemPrompt: systemPrompt)
        }
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        log.info("Polish took \(durationMs)ms", tag: "AzureOpenAI")
        return AIPolishResult(text: polishedText, modelName: deploymentName, durationMs: durationMs)
    }

    // MARK: - Chat Completions API

    private func polishWithChatCompletions(text: String, systemPrompt: String) async throws -> String {
        // Build URL
        let urlString = "\(endpoint)/openai/deployments/\(deploymentName)/chat/completions?api-version=\(apiVersion)"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.apiError(message: "Invalid endpoint URL")
        }

        log.debug("Chat Completions URL: \(urlString)", tag: "AzureOpenAI")

        // Build request body
        let requestBody: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 2000,
            "temperature": 0.7
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)

        if let jsonStr = String(data: jsonData, encoding: .utf8) {
            log.debug("REQUEST BODY (Chat Completions):\n\(jsonStr)", tag: "AzureOpenAI")
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData
        request.timeoutInterval = timeout

        // Send request
        log.info("Sending Chat Completions request (timeout: \(timeout)s)...", tag: "AzureOpenAI")
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        log.info("Response status: \(httpResponse.statusCode)", tag: "AzureOpenAI")

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.info("Error response: \(errorMessage)", tag: "AzureOpenAI")
            throw AIProviderError.apiError(message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            log.info("Failed to parse response", tag: "AzureOpenAI")
            if let responseStr = String(data: data, encoding: .utf8) {
                log.debug("Raw response: \(responseStr)", tag: "AzureOpenAI")
            }
            throw AIProviderError.invalidResponse
        }

        let polishedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("Chat Completions result: \(polishedText)", tag: "AzureOpenAI")

        return polishedText
    }

    // MARK: - Responses API

    private func polishWithResponsesAPI(text: String, systemPrompt: String) async throws -> String {
        // Build URL for Responses API
        let urlString = "\(endpoint)/openai/v1/responses"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.apiError(message: "Invalid endpoint URL")
        }

        log.debug("Responses API URL: \(urlString)", tag: "AzureOpenAI")

        // Build request body
        let combinedInput = "\(systemPrompt)\n\n请润色以下文字：\n\(text)"

        let requestBody: [String: Any] = [
            "model": deploymentName,
            "input": combinedInput
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted)

        if let jsonStr = String(data: jsonData, encoding: .utf8) {
            log.debug("REQUEST BODY (Responses API):\n\(jsonStr)", tag: "AzureOpenAI")
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData
        request.timeoutInterval = timeout

        // Send request
        log.info("Sending Responses API request (timeout: \(timeout)s)...", tag: "AzureOpenAI")
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        log.info("Response status: \(httpResponse.statusCode)", tag: "AzureOpenAI")

        // Debug: log raw response
        if let responseStr = String(data: data, encoding: .utf8) {
            log.debug("Raw response: \(responseStr)", tag: "AzureOpenAI")
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.info("Error response: \(errorMessage)", tag: "AzureOpenAI")
            throw AIProviderError.apiError(message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse Responses API response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.info("Failed to parse JSON response", tag: "AzureOpenAI")
            throw AIProviderError.invalidResponse
        }

        // Check status
        if let status = json["status"] as? String, status != "completed" {
            log.info("Response status: \(status)", tag: "AzureOpenAI")
            if status == "failed" {
                throw AIProviderError.apiError(message: "Response generation failed")
            }
        }

        // Extract output text - try different response formats
        var outputText: String?

        // Format 1: output[].content[].text
        if let output = json["output"] as? [[String: Any]],
           let firstOutput = output.first,
           let content = firstOutput["content"] as? [[String: Any]],
           let firstContent = content.first,
           let text = firstContent["text"] as? String {
            outputText = text
        }

        // Format 2: output[].text (simpler format)
        if outputText == nil,
           let output = json["output"] as? [[String: Any]],
           let firstOutput = output.first,
           let text = firstOutput["text"] as? String {
            outputText = text
        }

        // Format 3: output_text (direct)
        if outputText == nil,
           let text = json["output_text"] as? String {
            outputText = text
        }

        guard let finalText = outputText else {
            log.info("Failed to extract text from response", tag: "AzureOpenAI")
            log.debug("Response structure: \(json)", tag: "AzureOpenAI")
            throw AIProviderError.invalidResponse
        }

        let polishedText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("Responses API result: \(polishedText)", tag: "AzureOpenAI")

        return polishedText
    }
}
