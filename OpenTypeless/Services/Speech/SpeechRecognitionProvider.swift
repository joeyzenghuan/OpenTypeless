import Foundation

/// Speech recognition result
struct SpeechRecognitionResult {
    let text: String
    let isFinal: Bool
    let confidence: Float?
    let language: String?
}

/// Protocol for speech recognition providers
/// Implement this protocol to add support for new speech recognition services
protocol SpeechRecognitionProvider {
    /// Display name of the provider
    var name: String { get }

    /// Unique identifier for the provider
    var identifier: String { get }

    /// Whether this provider supports real-time streaming recognition
    var supportsRealtime: Bool { get }

    /// Whether this provider can work offline
    var supportsOffline: Bool { get }

    /// Whether the provider is currently available (e.g., has valid API key)
    var isAvailable: Bool { get }

    /// Start speech recognition
    /// - Parameter language: BCP-47 language code (e.g., "en-US", "zh-CN")
    func startRecognition(language: String) async throws

    /// Stop speech recognition and return final result
    /// - Returns: Final transcription text
    func stopRecognition() async throws -> String

    /// Cancel ongoing recognition without returning result
    func cancelRecognition()

    /// Set handler for partial (interim) results during recognition
    /// - Parameter handler: Callback with partial result
    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void)

    /// Set handler for errors during recognition
    /// - Parameter handler: Callback with error
    func onError(_ handler: @escaping (Error) -> Void)
}

/// Errors that can occur during speech recognition
enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case notAvailable
    case noMicrophone
    case networkError(underlying: Error)
    case apiKeyMissing
    case recognitionFailed(reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in System Settings."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .noMicrophone:
            return "No microphone available."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .apiKeyMissing:
            return "API key is missing. Please configure in Settings."
        case .recognitionFailed(let reason):
            return "Recognition failed: \(reason)"
        case .cancelled:
            return "Recognition was cancelled."
        }
    }
}

/// Configuration for speech recognition providers
struct SpeechProviderConfig {
    // Azure Speech Service
    var azureSubscriptionKey: String?
    var azureRegion: String?

    // OpenAI Whisper
    var openAIAPIKey: String?

    // Local Whisper
    var localWhisperModelPath: String?
    var localWhisperModelSize: WhisperModelSize?

    enum WhisperModelSize: String, CaseIterable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"
        case medium = "medium"
        case large = "large"

        var displayName: String {
            switch self {
            case .tiny: return "Tiny (75MB)"
            case .base: return "Base (142MB)"
            case .small: return "Small (466MB)"
            case .medium: return "Medium (1.5GB)"
            case .large: return "Large (3GB)"
            }
        }
    }
}
