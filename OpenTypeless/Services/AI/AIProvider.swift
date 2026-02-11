import Foundation

/// Result of AI polish with metadata for history tracking
struct AIPolishResult {
    let text: String
    let modelName: String
    let durationMs: Int
}

/// Protocol for AI text processing providers
protocol AIProvider {
    var name: String { get }
    var identifier: String { get }
    var isAvailable: Bool { get }

    /// Polish/refine the transcribed text
    func polish(text: String, systemPrompt: String) async throws -> String

    /// Polish with metadata (provider name, model name, duration)
    func polishWithMetadata(text: String, systemPrompt: String) async throws -> AIPolishResult
}

/// Errors that can occur during AI processing
enum AIProviderError: LocalizedError {
    case notConfigured
    case networkError(underlying: Error)
    case invalidResponse
    case apiError(message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider is not configured. Please add your API credentials in Settings."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from AI service."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
