import Foundation
import AVFoundation

#if canImport(MicrosoftCognitiveServicesSpeech)
import MicrosoftCognitiveServicesSpeech
#endif

/// Azure Speech Service implementation using Microsoft Cognitive Services Speech SDK
///
/// Setup:
/// 1. Create an Azure account and Speech resource
/// 2. Get the subscription key and region
/// 3. Configure in Settings > Speech Recognition > Azure Speech Service
///
/// Documentation: https://learn.microsoft.com/azure/cognitive-services/speech-service/
class AzureSpeechProvider: SpeechRecognitionProvider {

    // MARK: - Protocol Properties

    let name = "Azure Speech Service"
    let identifier = "azure"
    let supportsRealtime = true
    let supportsOffline = false

    var isAvailable: Bool {
        guard let key = subscriptionKey, !key.isEmpty,
              let reg = region, !reg.isEmpty else {
            return false
        }
        return true
    }

    // MARK: - Configuration

    private var subscriptionKey: String?
    private var region: String?

    // MARK: - Private Properties

    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var finalTranscription: String = ""
    private var allTranscriptions: [String] = []
    private var isRecognizing: Bool = false

    #if canImport(MicrosoftCognitiveServicesSpeech)
    private var speechRecognizer: SPXSpeechRecognizer?
    #endif

    // MARK: - Initialization

    init(subscriptionKey: String? = nil, region: String? = nil) {
        self.subscriptionKey = subscriptionKey ?? UserDefaults.standard.string(forKey: "azureSpeechKey")
        self.region = region ?? UserDefaults.standard.string(forKey: "azureSpeechRegion")

        print("[AzureSpeech] Initialized")
        print("[AzureSpeech] Region: \(self.region ?? "not set")")
        print("[AzureSpeech] Key configured: \(self.subscriptionKey?.isEmpty == false ? "yes" : "no")")
    }

    // MARK: - Configuration

    func configure(subscriptionKey: String, region: String) {
        self.subscriptionKey = subscriptionKey
        self.region = region
    }

    func reloadConfig() {
        self.subscriptionKey = UserDefaults.standard.string(forKey: "azureSpeechKey")
        self.region = UserDefaults.standard.string(forKey: "azureSpeechRegion")
        print("[AzureSpeech] Config reloaded")
    }

    // MARK: - Protocol Methods

    func startRecognition(language: String) async throws {
        print("[AzureSpeech] ========================================")
        print("[AzureSpeech] Starting recognition")
        print("[AzureSpeech] Provider: Azure Speech Service (cloud)")
        print("[AzureSpeech] Language: \(language)")
        print("[AzureSpeech] Region: \(region ?? "unknown")")
        print("[AzureSpeech] ========================================")

        guard isAvailable else {
            print("[AzureSpeech] ❌ Not configured")
            throw SpeechRecognitionError.apiKeyMissing
        }

        #if canImport(MicrosoftCognitiveServicesSpeech)
        try await startAzureRecognition(language: language)
        #else
        print("[AzureSpeech] ❌ Azure Speech SDK not available")
        print("[AzureSpeech] Please run 'pod install' and open .xcworkspace")
        throw SpeechRecognitionError.notAvailable
        #endif
    }

    func stopRecognition() async throws -> String {
        print("[AzureSpeech] Stopping recognition...")

        #if canImport(MicrosoftCognitiveServicesSpeech)
        return try await stopAzureRecognition()
        #else
        return finalTranscription
        #endif
    }

    func cancelRecognition() {
        print("[AzureSpeech] Cancelling recognition...")

        #if canImport(MicrosoftCognitiveServicesSpeech)
        cancelAzureRecognition()
        #endif

        finalTranscription = ""
        allTranscriptions = []
        isRecognizing = false
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) {
        partialResultHandler = handler
    }

    func onError(_ handler: @escaping (Error) -> Void) {
        errorHandler = handler
    }

    // MARK: - Azure Speech SDK Implementation

    #if canImport(MicrosoftCognitiveServicesSpeech)

    private func startAzureRecognition(language: String) async throws {
        guard let key = subscriptionKey, let reg = region else {
            throw SpeechRecognitionError.apiKeyMissing
        }

        // Create speech configuration
        let speechConfig: SPXSpeechConfiguration
        do {
            speechConfig = try SPXSpeechConfiguration(subscription: key, region: reg)
        } catch {
            print("[AzureSpeech] ❌ Failed to create speech config: \(error)")
            throw SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription)
        }

        // Set recognition language
        speechConfig.speechRecognitionLanguage = language
        print("[AzureSpeech] Speech config created with language: \(language)")

        // Create audio configuration (from default microphone)
        let audioConfig = SPXAudioConfiguration()
        print("[AzureSpeech] Audio config created (default microphone)")

        // Create speech recognizer
        do {
            speechRecognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
        } catch {
            print("[AzureSpeech] ❌ Failed to create recognizer: \(error)")
            throw SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription)
        }

        guard let recognizer = speechRecognizer else {
            throw SpeechRecognitionError.notAvailable
        }

        // Reset state
        finalTranscription = ""
        allTranscriptions = []
        isRecognizing = true

        // Add recognizing event handler (partial results)
        recognizer.addRecognizingEventHandler { [weak self] _, evt in
            guard let self = self else { return }
            let text = evt.result.text ?? ""
            print("[AzureSpeech] Recognizing: \(text)")

            // Update transcription
            let previousText = self.allTranscriptions.joined(separator: "")
            let fullText = previousText + text
            self.finalTranscription = fullText

            let result = SpeechRecognitionResult(
                text: fullText,
                isFinal: false,
                confidence: nil,
                language: language
            )
            self.partialResultHandler?(result)
        }

        // Add recognized event handler (final results for each utterance)
        recognizer.addRecognizedEventHandler { [weak self] _, evt in
            guard let self = self else { return }
            let text = evt.result.text ?? ""

            if !text.isEmpty {
                print("[AzureSpeech] Recognized: \(text)")
                self.allTranscriptions.append(text)
                self.finalTranscription = self.allTranscriptions.joined(separator: "")

                let result = SpeechRecognitionResult(
                    text: self.finalTranscription,
                    isFinal: true,
                    confidence: nil,
                    language: language
                )
                self.partialResultHandler?(result)
            }
        }

        // Add canceled event handler
        recognizer.addCanceledEventHandler { [weak self] _, evt in
            guard let self = self else { return }
            print("[AzureSpeech] Canceled: \(evt.reason.rawValue)")

            if evt.reason == SPXCancellationReason.error {
                let errorDetails = evt.errorDetails ?? "Unknown error"
                print("[AzureSpeech] ❌ Error: \(errorDetails)")
                self.errorHandler?(SpeechRecognitionError.recognitionFailed(reason: errorDetails))
            }
        }

        // Start continuous recognition
        print("[AzureSpeech] Starting continuous recognition...")
        do {
            try recognizer.startContinuousRecognition()
            print("[AzureSpeech] ✅ Continuous recognition started")
        } catch {
            print("[AzureSpeech] ❌ Failed to start recognition: \(error)")
            throw SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription)
        }
    }

    private func stopAzureRecognition() async throws -> String {
        guard let recognizer = speechRecognizer else {
            return finalTranscription
        }

        // Stop continuous recognition
        do {
            try recognizer.stopContinuousRecognition()
            print("[AzureSpeech] ✅ Continuous recognition stopped")
        } catch {
            print("[AzureSpeech] ❌ Failed to stop recognition: \(error)")
        }

        // Wait a moment for final results
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        isRecognizing = false
        speechRecognizer = nil

        print("[AzureSpeech] All segments: \(allTranscriptions)")
        print("[AzureSpeech] Final combined: \(finalTranscription)")

        return finalTranscription
    }

    private func cancelAzureRecognition() {
        guard let recognizer = speechRecognizer else { return }

        do {
            try recognizer.stopContinuousRecognition()
        } catch {
            print("[AzureSpeech] Error stopping recognition: \(error)")
        }

        isRecognizing = false
        speechRecognizer = nil
    }

    #endif
}
