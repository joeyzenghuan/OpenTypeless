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

    private let log = Logger.shared

    #if canImport(MicrosoftCognitiveServicesSpeech)
    private var speechRecognizer: SPXSpeechRecognizer?
    #endif

    // MARK: - Initialization

    init(subscriptionKey: String? = nil, region: String? = nil) {
        self.subscriptionKey = subscriptionKey ?? UserDefaults.standard.string(forKey: "azureSpeechKey")
        self.region = region ?? UserDefaults.standard.string(forKey: "azureSpeechRegion")

        log.info("Initialized - region: \(self.region ?? "not set"), key configured: \(self.subscriptionKey?.isEmpty == false ? "yes" : "no")", tag: "AzureSpeech")
    }

    // MARK: - Configuration

    func configure(subscriptionKey: String, region: String) {
        self.subscriptionKey = subscriptionKey
        self.region = region
    }

    func reloadConfig() {
        self.subscriptionKey = UserDefaults.standard.string(forKey: "azureSpeechKey")
        self.region = UserDefaults.standard.string(forKey: "azureSpeechRegion")
        log.info("Config reloaded", tag: "AzureSpeech")
    }

    // MARK: - Protocol Methods

    func startRecognition(language: String) async throws {
        log.info("Starting recognition - language: \(language), region: \(region ?? "unknown")", tag: "AzureSpeech")

        guard isAvailable else {
            log.info("Not configured", tag: "AzureSpeech")
            throw SpeechRecognitionError.apiKeyMissing
        }

        #if canImport(MicrosoftCognitiveServicesSpeech)
        try await startAzureRecognition(language: language)
        #else
        log.info("Azure Speech SDK not available - run 'pod install' and open .xcworkspace", tag: "AzureSpeech")
        throw SpeechRecognitionError.notAvailable
        #endif
    }

    func stopRecognition() async throws -> String {
        log.info("Stopping recognition...", tag: "AzureSpeech")

        #if canImport(MicrosoftCognitiveServicesSpeech)
        return try await stopAzureRecognition()
        #else
        return finalTranscription
        #endif
    }

    func cancelRecognition() {
        log.info("Cancelling recognition...", tag: "AzureSpeech")

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
            log.info("Failed to create speech config: \(error)", tag: "AzureSpeech")
            throw SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription)
        }

        // Set recognition language
        speechConfig.speechRecognitionLanguage = language
        log.debug("Speech config created with language: \(language)", tag: "AzureSpeech")

        // Create audio configuration (from default microphone)
        let audioConfig = SPXAudioConfiguration()
        log.debug("Audio config created (default microphone)", tag: "AzureSpeech")

        // Create speech recognizer
        do {
            speechRecognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
        } catch {
            log.info("Failed to create recognizer: \(error)", tag: "AzureSpeech")
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
            self.log.debug("Recognizing: \(text)", tag: "AzureSpeech")

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
                self.log.debug("Recognized: \(text)", tag: "AzureSpeech")
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
            self.log.info("Canceled: \(evt.reason.rawValue)", tag: "AzureSpeech")

            if evt.reason == SPXCancellationReason.error {
                let errorDetails = evt.errorDetails ?? "Unknown error"
                self.log.info("Error: \(errorDetails)", tag: "AzureSpeech")
                self.errorHandler?(SpeechRecognitionError.recognitionFailed(reason: errorDetails))
            }
        }

        // Start continuous recognition
        log.info("Starting continuous recognition...", tag: "AzureSpeech")
        do {
            try recognizer.startContinuousRecognition()
            log.info("Continuous recognition started", tag: "AzureSpeech")
        } catch {
            log.info("Failed to start recognition: \(error)", tag: "AzureSpeech")
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
            log.info("Continuous recognition stopped", tag: "AzureSpeech")
        } catch {
            log.info("Failed to stop recognition: \(error)", tag: "AzureSpeech")
        }

        // Wait a moment for final results
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        isRecognizing = false
        speechRecognizer = nil

        log.debug("All segments: \(allTranscriptions)", tag: "AzureSpeech")
        log.info("Final combined: \(finalTranscription)", tag: "AzureSpeech")

        return finalTranscription
    }

    private func cancelAzureRecognition() {
        guard let recognizer = speechRecognizer else { return }

        do {
            try recognizer.stopContinuousRecognition()
        } catch {
            log.info("Error stopping recognition: \(error)", tag: "AzureSpeech")
        }

        isRecognizing = false
        speechRecognizer = nil
    }

    #endif
}
