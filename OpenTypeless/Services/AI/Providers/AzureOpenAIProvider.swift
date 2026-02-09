import Foundation

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

    // MARK: - Initialization

    init() {
        let defaults = UserDefaults.standard
        self.endpoint = defaults.string(forKey: "azureOpenAIEndpoint") ?? ""
        self.deploymentName = defaults.string(forKey: "azureOpenAIDeployment") ?? ""
        self.apiKey = defaults.string(forKey: "azureOpenAIKey") ?? ""
        self.apiVersion = defaults.string(forKey: "azureOpenAIVersion") ?? "2024-02-15-preview"

        print("[AzureOpenAI] Initialized - endpoint: \(endpoint.isEmpty ? "not set" : "configured")")
    }

    func reloadConfig() {
        let defaults = UserDefaults.standard
        self.endpoint = defaults.string(forKey: "azureOpenAIEndpoint") ?? ""
        self.deploymentName = defaults.string(forKey: "azureOpenAIDeployment") ?? ""
        self.apiKey = defaults.string(forKey: "azureOpenAIKey") ?? ""
        self.apiVersion = defaults.string(forKey: "azureOpenAIVersion") ?? "2024-02-15-preview"
        print("[AzureOpenAI] Config reloaded")
    }

    // MARK: - AI Processing

    func polish(text: String, systemPrompt: String) async throws -> String {
        guard isAvailable else {
            print("[AzureOpenAI] ❌ Not configured")
            throw AIProviderError.notConfigured
        }

        print("[AzureOpenAI] Polishing text: \(text)")
        print("[AzureOpenAI] System prompt: \(systemPrompt)")

        // Build URL
        // Format: {endpoint}/openai/deployments/{deployment-id}/chat/completions?api-version={api-version}
        let urlString = "\(endpoint)/openai/deployments/\(deploymentName)/chat/completions?api-version=\(apiVersion)"

        guard let url = URL(string: urlString) else {
            throw AIProviderError.apiError(message: "Invalid endpoint URL")
        }

        print("[AzureOpenAI] Request URL: \(urlString)")

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
        print("[AzureOpenAI] Sending request...")
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
            throw AIProviderError.invalidResponse
        }

        let polishedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[AzureOpenAI] ✅ Polished result: \(polishedText)")

        return polishedText
    }
}
