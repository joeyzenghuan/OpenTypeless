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

    // MARK: - Initialization

    init() {
        let defaults = UserDefaults.standard
        self.endpoint = defaults.string(forKey: "azureOpenAIEndpoint") ?? ""
        self.deploymentName = defaults.string(forKey: "azureOpenAIDeployment") ?? ""
        self.apiKey = defaults.string(forKey: "azureOpenAIKey") ?? ""
        self.apiVersion = defaults.string(forKey: "azureOpenAIVersion") ?? "2024-02-15-preview"
        self.apiType = AzureOpenAIAPIType(rawValue: defaults.string(forKey: "azureOpenAIAPIType") ?? "chat-completions") ?? .chatCompletions

        print("[AzureOpenAI] Initialized - endpoint: \(endpoint.isEmpty ? "not set" : "configured"), API type: \(apiType.displayName)")
    }

    func reloadConfig() {
        let defaults = UserDefaults.standard
        self.endpoint = defaults.string(forKey: "azureOpenAIEndpoint") ?? ""
        self.deploymentName = defaults.string(forKey: "azureOpenAIDeployment") ?? ""
        self.apiKey = defaults.string(forKey: "azureOpenAIKey") ?? ""
        self.apiVersion = defaults.string(forKey: "azureOpenAIVersion") ?? "2024-02-15-preview"
        self.apiType = AzureOpenAIAPIType(rawValue: defaults.string(forKey: "azureOpenAIAPIType") ?? "chat-completions") ?? .chatCompletions
        print("[AzureOpenAI] Config reloaded - API type: \(apiType.displayName)")
    }

    // MARK: - AI Processing

    func polish(text: String, systemPrompt: String) async throws -> String {
        guard isAvailable else {
            print("[AzureOpenAI] ❌ Not configured")
            throw AIProviderError.notConfigured
        }

        print("[AzureOpenAI] Polishing text: \(text)")
        print("[AzureOpenAI] System prompt: \(systemPrompt)")
        print("[AzureOpenAI] Using API type: \(apiType.displayName)")

        switch apiType {
        case .chatCompletions:
            return try await polishWithChatCompletions(text: text, systemPrompt: systemPrompt)
        case .responses:
            return try await polishWithResponsesAPI(text: text, systemPrompt: systemPrompt)
        }
    }

    // MARK: - Chat Completions API

    private func polishWithChatCompletions(text: String, systemPrompt: String) async throws -> String {
        // Build URL
        // Format: {endpoint}/openai/deployments/{deployment-id}/chat/completions?api-version={api-version}
        let urlString = "\(endpoint)/openai/deployments/\(deploymentName)/chat/completions?api-version=\(apiVersion)"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.apiError(message: "Invalid endpoint URL")
        }

        print("[AzureOpenAI] Chat Completions URL: \(urlString)")

        // Build request body
        let requestBody: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 2000,
            "temperature": 0.7
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        // Send request
        print("[AzureOpenAI] Sending Chat Completions request...")
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        print("[AzureOpenAI] Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AzureOpenAI] ❌ Error response: \(errorMessage)")
            throw AIProviderError.apiError(message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("[AzureOpenAI] ❌ Failed to parse response")
            if let responseStr = String(data: data, encoding: .utf8) {
                print("[AzureOpenAI] Raw response: \(responseStr)")
            }
            throw AIProviderError.invalidResponse
        }

        let polishedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[AzureOpenAI] ✅ Chat Completions result: \(polishedText)")

        return polishedText
    }

    // MARK: - Responses API

    private func polishWithResponsesAPI(text: String, systemPrompt: String) async throws -> String {
        // Build URL for Responses API
        // Format: {endpoint}/openai/v1/responses
        // Note: Responses API uses model name directly, not deployment name in URL
        let urlString = "\(endpoint)/openai/v1/responses"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.apiError(message: "Invalid endpoint URL")
        }

        print("[AzureOpenAI] Responses API URL: \(urlString)")

        // Build request body for Responses API
        // Combine system prompt and user input
        let combinedPrompt = "\(systemPrompt)\n\n请润色以下文字：\n\(text)"

        let requestBody: [String: Any] = [
            "model": deploymentName,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": combinedPrompt
                        ]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        // Debug: print request body
        if let jsonStr = String(data: jsonData, encoding: .utf8) {
            print("[AzureOpenAI] Request body: \(jsonStr)")
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        // Send request
        print("[AzureOpenAI] Sending Responses API request...")
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        print("[AzureOpenAI] Response status: \(httpResponse.statusCode)")

        // Debug: print raw response
        if let responseStr = String(data: data, encoding: .utf8) {
            print("[AzureOpenAI] Raw response: \(responseStr)")
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AzureOpenAI] ❌ Error response: \(errorMessage)")
            throw AIProviderError.apiError(message: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse Responses API response
        // Response format: { "id": "...", "output": [...], "status": "completed", ... }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[AzureOpenAI] ❌ Failed to parse JSON response")
            throw AIProviderError.invalidResponse
        }

        // Check status
        if let status = json["status"] as? String, status != "completed" {
            print("[AzureOpenAI] ⚠️ Response status: \(status)")
            if status == "failed" {
                throw AIProviderError.apiError(message: "Response generation failed")
            }
        }

        // Extract output text
        // Output format: [{ "type": "message", "content": [{ "type": "output_text", "text": "..." }] }]
        guard let output = json["output"] as? [[String: Any]],
              let firstOutput = output.first,
              let content = firstOutput["content"] as? [[String: Any]],
              let firstContent = content.first,
              let outputText = firstContent["text"] as? String else {
            print("[AzureOpenAI] ❌ Failed to extract text from response")
            throw AIProviderError.invalidResponse
        }

        let polishedText = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[AzureOpenAI] ✅ Responses API result: \(polishedText)")

        return polishedText
    }
}
