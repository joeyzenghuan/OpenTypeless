import Foundation
import Combine

/// Manages speech recognition providers and handles switching between them
@MainActor
class SpeechRecognitionManager: ObservableObject {
    static let shared = SpeechRecognitionManager()

    // MARK: - Published Properties

    @Published private(set) var currentProvider: SpeechRecognitionProvider?
    @Published private(set) var isRecognizing: Bool = false
    @Published private(set) var partialResult: String = ""
    @Published private(set) var error: Error?

    // MARK: - Private Properties

    private var providers: [String: SpeechRecognitionProvider] = [:]
    private var config: SpeechProviderConfig = SpeechProviderConfig()

    // MARK: - Initialization

    private init() {
        setupProviders()
        loadConfiguration()
    }

    // MARK: - Provider Management

    /// Register all available providers
    private func setupProviders() {
        // Register Apple Speech provider (always available on macOS)
        let appleProvider = AppleSpeechProvider()
        providers[appleProvider.identifier] = appleProvider

        // Other providers will be registered when their dependencies are available
        // providers["azure"] = AzureSpeechProvider(config: config)
        // providers["whisper"] = WhisperAPIProvider(config: config)
        // providers["local-whisper"] = LocalWhisperProvider(config: config)
    }

    /// Load configuration from UserDefaults
    private func loadConfiguration() {
        let defaults = UserDefaults.standard

        config.azureSubscriptionKey = defaults.string(forKey: "azureSpeechKey")
        config.azureRegion = defaults.string(forKey: "azureSpeechRegion")
        config.openAIAPIKey = defaults.string(forKey: "whisperAPIKey")

        // Set default provider
        let providerID = defaults.string(forKey: "speechProvider") ?? "apple"
        selectProvider(identifier: providerID)
    }

    /// Select a provider by identifier
    /// - Parameter identifier: Provider identifier (e.g., "apple", "azure")
    func selectProvider(identifier: String) {
        guard let provider = providers[identifier] else {
            print("Provider \(identifier) not found, falling back to Apple Speech")
            currentProvider = providers["apple"]
            return
        }

        if provider.isAvailable {
            currentProvider = provider
            setupProviderCallbacks()
        } else {
            print("Provider \(identifier) is not available")
            error = SpeechRecognitionError.notAvailable
        }
    }

    /// Setup callbacks for the current provider
    private func setupProviderCallbacks() {
        currentProvider?.onPartialResult { [weak self] result in
            Task { @MainActor in
                self?.partialResult = result.text
            }
        }

        currentProvider?.onError { [weak self] error in
            Task { @MainActor in
                self?.error = error
                self?.isRecognizing = false
            }
        }
    }

    /// Get all registered providers
    func availableProviders() -> [SpeechRecognitionProvider] {
        return Array(providers.values)
    }

    // MARK: - Recognition Control

    /// Start speech recognition with the current provider
    /// - Parameter language: BCP-47 language code
    func startRecognition(language: String = "en-US") async throws {
        guard let provider = currentProvider else {
            throw SpeechRecognitionError.notAvailable
        }

        guard !isRecognizing else { return }

        partialResult = ""
        error = nil
        isRecognizing = true

        try await provider.startRecognition(language: language)
    }

    /// Stop recognition and return final result
    /// - Returns: Final transcription text
    func stopRecognition() async throws -> String {
        guard let provider = currentProvider else {
            throw SpeechRecognitionError.notAvailable
        }

        guard isRecognizing else { return "" }

        let result = try await provider.stopRecognition()
        isRecognizing = false
        partialResult = ""

        return result
    }

    /// Cancel ongoing recognition
    func cancelRecognition() {
        currentProvider?.cancelRecognition()
        isRecognizing = false
        partialResult = ""
    }

    // MARK: - Configuration

    /// Update provider configuration
    func updateConfig(_ newConfig: SpeechProviderConfig) {
        config = newConfig

        // Save to UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(config.azureSubscriptionKey, forKey: "azureSpeechKey")
        defaults.set(config.azureRegion, forKey: "azureSpeechRegion")
        defaults.set(config.openAIAPIKey, forKey: "whisperAPIKey")

        // Reinitialize providers that need updated config
        setupProviders()
    }
}
