import Foundation

#if canImport(MicrosoftCognitiveServicesSpeech)
@preconcurrency import MicrosoftCognitiveServicesSpeech
#endif

/// Azure real-time recognition with optional service-side post-stream refinement.
final class AzureSpeechProvider: SpeechRecognitionProvider {
    let name = "Azure Speech Service"
    let identifier = "azure"
    let supportsRealtime = true
    let supportsOffline = false
    let supportsRecognitionStages = true
    var usesPostStreamRefinement: Bool { AzureSpeechRefinement.isEnabled }

    var isAvailable: Bool {
        !subscriptionKey.isEmpty && !region.isEmpty
    }

    private var subscriptionKey: String
    private var region: String
    private let explicitConfiguration: Bool
    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var statusHandler: ((String) -> Void)?
    private let log = Logger.shared
    // Protect recognizer/session ownership while SDK callbacks run on background threads.
    private let stateLock = NSLock()
    private let sdkQueue = DispatchQueue(label: "OpenTypeless.AzureSpeechSDK")
    private var session: AzureSpeechSession?
    private var completedPreview: String?
    private var completedFallback: SpeechRefinementFallback?
    var lastRefinementPreview: String? { stateLock.withLock { completedPreview } }
    var lastRefinementFallback: SpeechRefinementFallback? { stateLock.withLock { completedFallback } }

    #if canImport(MicrosoftCognitiveServicesSpeech)
    private var speechRecognizer: SPXSpeechRecognizer?
    #endif

    init(subscriptionKey: String? = nil, region: String? = nil) {
        explicitConfiguration = subscriptionKey != nil || region != nil
        self.subscriptionKey = subscriptionKey ?? UserDefaults.standard.string(forKey: "azureSpeechKey") ?? ""
        self.region = region ?? UserDefaults.standard.string(forKey: "azureSpeechRegion") ?? "swedencentral"
    }

    func startRecognition(language: String) async throws {
        if !explicitConfiguration {
            subscriptionKey = UserDefaults.standard.string(forKey: "azureSpeechKey") ?? ""
            region = UserDefaults.standard.string(forKey: "azureSpeechRegion") ?? "swedencentral"
        }
        region = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isAvailable else { throw SpeechRecognitionError.apiKeyMissing }
        let refinement = usesPostStreamRefinement
        if refinement, let issue = AzureSpeechRefinement.configurationIssue(region: region, language: language) {
            throw SpeechRecognitionError.recognitionFailed(reason: issue)
        }
        emitStatus("正在连接 Azure Speech...")

        #if canImport(MicrosoftCognitiveServicesSpeech)
        let speechConfig = try SPXSpeechConfiguration(subscription: subscriptionKey, region: region)
        speechConfig.speechRecognitionLanguage = language
        if refinement {
            // Microsoft returns the refined text through Recognized for each segment.
            speechConfig.setPropertyTo("PostRefinement", by: .speechServiceResponsePostProcessingOption)
        }
        let recognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: SPXAudioConfiguration())
        let session = AzureSpeechSession(language: language, refinementEnabled: refinement)
        let traceID = session.traceID
        try Task.checkCancellation()
        let installed = stateLock.withLock { () -> Bool in
            guard self.session == nil else { return false }
            self.session = session
            self.completedPreview = nil
            self.completedFallback = nil
            self.speechRecognizer = recognizer
            return true
        }
        guard installed else { throw SpeechRecognitionError.recognitionFailed(reason: "上一轮识别尚未结束") }

        recognizer.addRecognizingEventHandler { [weak self, session] _, event in
            guard let self, self.isCurrent(session) else { return }
            let result = session.receive(text: event.result.text ?? "", offset: event.result.offset, duration: event.result.duration, isFinal: false)
            self.log.debug("[\(traceID)] Recognizing offset=\(event.result.offset), duration=\(event.result.duration), chars=\((event.result.text ?? "").count), accepted=\(result != nil)", tag: "AzureSpeech")
            if let result {
                self.partialResultHandler?(result)
            }
        }
        recognizer.addRecognizedEventHandler { [weak self, session] _, event in
            guard let self, self.isCurrent(session) else { return }
            self.log.debug("[\(traceID)] Recognized reason=\(event.result.reason.rawValue), id=\(event.result.resultId), offset=\(event.result.offset), duration=\(event.result.duration), chars=\((event.result.text ?? "").count)", tag: "AzureSpeech")
            if event.result.reason == .noMatch,
               let json = event.result.properties?.getPropertyBy(.speechServiceResponseJsonResult),
               let data = json.data(using: .utf8),
               let details = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                self.log.info("[\(traceID)] NoMatch status=\(details["RecognitionStatus"] as? String ?? "unknown")", tag: "AzureSpeech")
            }
            // NoMatch preserves the last preview for fallback at session completion.
            guard event.result.reason == .recognizedSpeech else { return }
            let result = session.receive(text: event.result.text ?? "", offset: event.result.offset, duration: event.result.duration, isFinal: true)
            self.log.debug("[\(traceID)] Final accepted=\(result != nil); \(session.diagnosticSummary)", tag: "AzureSpeech")
            if let result {
                self.partialResultHandler?(result)
            }
        }
        recognizer.addSessionStartedEventHandler { [weak self, session] _, _ in
            guard let self, self.isCurrent(session) else { return }
            self.emitStatus(refinement ? "正在听 · 最终精修已开启" : "Azure Speech 已连接，正在听...")
        }
        recognizer.addSessionStoppedEventHandler { [weak self, session] _, _ in
            session.markSessionEnded()
            self?.log.info("[\(traceID)] SessionStopped; \(session.diagnosticSummary)", tag: "AzureSpeech")
        }
        recognizer.addCanceledEventHandler { [weak self, session] _, event in
            guard let self, self.isCurrent(session) else { return }
            self.log.info("[\(traceID)] Canceled reason=\(event.reason.rawValue), code=\(event.errorCode.rawValue); \(session.diagnosticSummary)", tag: "AzureSpeech")
            if event.reason == .error {
                let error = SpeechRecognitionError.recognitionFailed(reason: event.errorDetails ?? "Azure Speech 连接错误")
                let recoverable: Bool
                switch event.errorCode {
                case .connectionFailure, .serviceTimeout, .serviceError, .serviceUnavailable, .tooManyRequests:
                    recoverable = true
                default:
                    recoverable = false
                }
                session.fail(error, recoveryReason: recoverable ? "Azure 精修服务或连接异常" : nil)
                if recoverable, session.canRecoverText {
                    self.emitStatus("精修中断，松开后使用已识别文本")
                } else {
                    self.errorHandler?(error)
                }
            } else if event.reason != .endOfStream {
                session.fail(SpeechRecognitionError.cancelled)
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sdkQueue.async {
                    do {
                        guard session.isActive else { throw CancellationError() }
                        try recognizer.startContinuousRecognition()
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
            try Task.checkCancellation()
            log.info("[\(traceID)] Azure recognition started; post-stream refinement: \(refinement); language=\(language), region=\(region)", tag: "AzureSpeech")
        } catch {
            session.fail(error)
            clear(session)
            session.stopOnce { [sdkQueue] in sdkQueue.sync { try? recognizer.stopContinuousRecognition() } }
            throw error
        }
        #else
        throw SpeechRecognitionError.notAvailable
        #endif
    }

    func stopRecognition() async throws -> String {
        #if canImport(MicrosoftCognitiveServicesSpeech)
        let active = stateLock.withLock { (session, speechRecognizer) }
        guard let session = active.0, let recognizer = active.1 else {
            throw SpeechRecognitionError.recognitionFailed(reason: "Azure 识别会话未启动")
        }
        emitStatus(session.refinementEnabled ? "正在等待最终精修..." : "正在等待最终识别结果...")
        log.info("[\(session.traceID)] Stop requested; \(session.diagnosticSummary)", tag: "AzureSpeech")
        defer { clear(session) }
        let text = try await session.finish { [sdkQueue, log] in
            do {
                try sdkQueue.sync { try recognizer.stopContinuousRecognition() }
                session.markStopReturned()
                log.info("[\(session.traceID)] SDK stop returned; \(session.diagnosticSummary)", tag: "AzureSpeech")
            } catch {
                session.fail(error)
            }
        }
        try Task.checkCancellation()
        stateLock.withLock {
            completedPreview = session.refinementEnabled ? session.previewText : nil
            completedFallback = session.lastFallback
        }
        log.info("[\(session.traceID)] Output ready; fallback=\(session.lastFallback?.reason ?? "none"); \(session.diagnosticSummary)", tag: "AzureSpeech")
        return text
        #else
        throw SpeechRecognitionError.notAvailable
        #endif
    }

    func cancelRecognition() {
        #if canImport(MicrosoftCognitiveServicesSpeech)
        let active = stateLock.withLock { () -> (AzureSpeechSession?, SPXSpeechRecognizer?) in
            let active = (session, speechRecognizer)
            session = nil
            speechRecognizer = nil
            return active
        }
        active.0?.fail(CancellationError())
        // Stop on a background thread so cancel remains responsive.
        if let session = active.0, let recognizer = active.1 {
            session.stopOnce { [sdkQueue] in sdkQueue.sync { try? recognizer.stopContinuousRecognition() } }
        }
        #endif
    }

    private func isCurrent(_ session: AzureSpeechSession) -> Bool {
        stateLock.withLock { self.session === session }
    }

    private func clear(_ session: AzureSpeechSession) {
        stateLock.withLock {
            guard self.session === session else { return }
            self.session = nil
            #if canImport(MicrosoftCognitiveServicesSpeech)
            speechRecognizer = nil
            #endif
        }
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) { partialResultHandler = handler }
    func onError(_ handler: @escaping (Error) -> Void) { errorHandler = handler }
    func onStatus(_ handler: @escaping (String) -> Void) { statusHandler = handler }
    private func emitStatus(_ message: String) { statusHandler?(message) }
}
