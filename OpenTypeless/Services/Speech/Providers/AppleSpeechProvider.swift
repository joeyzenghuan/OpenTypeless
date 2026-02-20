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
    private var lastPartialResult: String = "" // Track last partial to detect resets
    private var gotFinalResult = false // Signal that recognition produced a final result

    private let log = Logger.shared

    // MARK: - Initialization

    init() {
        requestAuthorization()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            switch status {
            case .authorized:
                self?.log.info("Authorization: authorized", tag: "AppleSpeech")
            case .denied:
                self?.log.info("Authorization: denied", tag: "AppleSpeech")
            case .restricted:
                self?.log.info("Authorization: restricted", tag: "AppleSpeech")
            case .notDetermined:
                self?.log.info("Authorization: not determined", tag: "AppleSpeech")
            @unknown default:
                break
            }
        }
    }

    // MARK: - Protocol Methods

    func startRecognition(language: String) async throws {
        log.info("Starting recognition - language: \(language)", tag: "AppleSpeech")

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

        log.debug("On-device recognition: \(recognizer.supportsOnDeviceRecognition ? "supported" : "not supported")", tag: "AppleSpeech")
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

        // Don't force on-device recognition — when the on-device model isn't
        // downloaded, forcing it causes silent failures with no results.
        // The system will still prefer on-device when available.
        if #available(macOS 10.15, *) {
            request.requiresOnDeviceRecognition = false
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
        lastPartialResult = ""
        gotFinalResult = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                // Check if it's just a cancellation
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    // Recognition was cancelled, not an error
                    self.log.debug("Recognition cancelled (expected)", tag: "AppleSpeech")
                    return
                }
                self.errorHandler?(error)
                return
            }

            if let result = result {
                let transcription = result.bestTranscription.formattedString

                // Detect if recognition was reset (new result is much shorter than last)
                if !self.lastPartialResult.isEmpty &&
                   transcription.count < self.lastPartialResult.count / 2 &&
                   self.lastPartialResult.count > 3 {
                    self.log.debug("Detected reset, saving segment: \(self.lastPartialResult)", tag: "AppleSpeech")
                    self.allTranscriptions.append(self.lastPartialResult)
                }

                self.lastPartialResult = transcription

                // If this is a final result for this segment, save it
                if result.isFinal {
                    if !transcription.isEmpty && !self.allTranscriptions.contains(transcription) {
                        self.allTranscriptions.append(transcription)
                        self.log.debug("Final segment: \(transcription)", tag: "AppleSpeech")
                    }
                    self.gotFinalResult = true
                }

                // Build full transcription from all segments + current partial
                let previousText = self.allTranscriptions.joined(separator: "")
                let currentText = result.isFinal ? "" : transcription
                self.finalTranscription = previousText + currentText

                let speechResult = SpeechRecognitionResult(
                    text: self.finalTranscription,
                    isFinal: result.isFinal,
                    confidence: result.bestTranscription.segments.last?.confidence,
                    language: language
                )

                self.partialResultHandler?(speechResult)
            }
        }

        log.info("Recognition started", tag: "AppleSpeech")
    }

    func stopRecognition() async throws -> String {
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        // End recognition request — tells the recognizer no more audio is coming,
        // which triggers it to finalize and produce a final result.
        recognitionRequest?.endAudio()

        // Wait for the recognition to produce a final result, with a 3-second timeout.
        // The old fixed 200ms delay was too short and often returned before any result arrived.
        for i in 0..<30 {
            if gotFinalResult {
                log.debug("Got final result after \(i * 100)ms", tag: "AppleSpeech")
                break
            }
            // Also break early if we have partial results and the task has completed
            if !lastPartialResult.isEmpty &&
               (recognitionTask?.state == .completed || recognitionTask?.state == .canceling) {
                log.debug("Task completed with partial results after \(i * 100)ms", tag: "AppleSpeech")
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Save any remaining partial result
        if !lastPartialResult.isEmpty && !allTranscriptions.contains(lastPartialResult) {
            log.debug("Saving last partial: \(lastPartialResult)", tag: "AppleSpeech")
            allTranscriptions.append(lastPartialResult)
        }

        // Build final result
        finalTranscription = allTranscriptions.joined(separator: "")
        log.debug("All segments: \(allTranscriptions)", tag: "AppleSpeech")
        log.info("Final combined: \(finalTranscription)", tag: "AppleSpeech")

        // Cancel task
        recognitionTask?.cancel()

        // Cleanup
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        lastPartialResult = ""

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
