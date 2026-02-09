import Foundation
import Speech
import AVFoundation

/// Apple Speech Framework implementation
class AppleSpeechProvider: SpeechRecognitionProvider {

    // MARK: - Protocol Properties

    let name = "Apple Speech"
    let identifier = "apple"
    let supportsRealtime = true
    let supportsOffline = true

    var isAvailable: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Private Properties

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?

    private var finalTranscription: String = ""
    private var allTranscriptions: [String] = [] // Store all segments

    // MARK: - Initialization

    init() {
        requestAuthorization()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Apple Speech: Authorized")
            case .denied:
                print("Apple Speech: Denied")
            case .restricted:
                print("Apple Speech: Restricted")
            case .notDetermined:
                print("Apple Speech: Not Determined")
            @unknown default:
                break
            }
        }
    }

    // MARK: - Protocol Methods

    func startRecognition(language: String) async throws {
        // Check authorization
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechRecognitionError.notAuthorized
        }

        // Initialize recognizer for the specified language
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            throw SpeechRecognitionError.notAvailable
        }

        guard recognizer.isAvailable else {
            throw SpeechRecognitionError.notAvailable
        }

        speechRecognizer = recognizer

        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw SpeechRecognitionError.noMicrophone
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Unable to create recognition request")
        }

        request.shouldReportPartialResults = true

        // Enable on-device recognition if available (iOS 13+ / macOS 10.15+)
        if #available(macOS 10.15, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        // Setup audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        finalTranscription = ""
        allTranscriptions = []

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                // Check if it's just a cancellation
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    // Recognition was cancelled, not an error
                    print("[AppleSpeech] Recognition cancelled (expected)")
                    return
                }
                self.errorHandler?(error)
                return
            }

            if let result = result {
                let transcription = result.bestTranscription.formattedString

                // If this is a final result for this segment, save it
                if result.isFinal {
                    if !transcription.isEmpty {
                        self.allTranscriptions.append(transcription)
                        print("[AppleSpeech] Final segment: \(transcription)")
                    }
                    self.finalTranscription = self.allTranscriptions.joined(separator: " ")
                } else {
                    // For partial results, show current segment + previous segments
                    let previousText = self.allTranscriptions.joined(separator: " ")
                    let fullText = previousText.isEmpty ? transcription : previousText + " " + transcription
                    self.finalTranscription = fullText
                }

                let speechResult = SpeechRecognitionResult(
                    text: self.finalTranscription,
                    isFinal: result.isFinal,
                    confidence: result.bestTranscription.segments.last?.confidence,
                    language: language
                )

                self.partialResultHandler?(speechResult)
            }
        }
    }

    func stopRecognition() async throws -> String {
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        // End recognition request
        recognitionRequest?.endAudio()

        // Wait a moment for final results
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Cancel task
        recognitionTask?.cancel()

        // Cleanup
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil

        return finalTranscription
    }

    func cancelRecognition() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        finalTranscription = ""
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) {
        partialResultHandler = handler
    }

    func onError(_ handler: @escaping (Error) -> Void) {
        errorHandler = handler
    }
}
