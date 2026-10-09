import Foundation
import AVFoundation

final class MAITranscribeSpeechProvider: SpeechRecognitionProvider, @unchecked Sendable {
    private struct OutboundMessage {
        let text: String
        let audioBytes: Int
    }

    let name = "MAI Transcribe 2 Streaming"
    let identifier = "mai-transcribe-2-streaming"
    let supportsRealtime = true
    let supportsOffline = false

    private let defaults: UserDefaults
    private let configurationOverride: MAITranscribeConfiguration?
    private let audioEngine = AVAudioEngine()
    private let captureLock = NSLock()
    private var captureID: UUID?
    private let queue = DispatchQueue(label: "OpenTypeless.MAITranscribeProvider")
    private var captureSessionID: UUID?
    private var activeSession: MAITranscribeSession?
    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var ready = false
    private var pendingAudio: [Data] = []
    private var outbound: [OutboundMessage] = []
    private var sending = false
    private var bufferedAudioBytes = 0
    private var totalAudioBytes = 0
    private let maxBufferedAudioBytes = MAITranscribeConfiguration.sampleRate * 2 * 15
    private var partialResultHandler: ((SpeechRecognitionResult) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var statusHandler: ((String) -> Void)?
    private let log = Logger.shared

    init(defaults: UserDefaults = .standard, configuration: MAITranscribeConfiguration? = nil) {
        self.defaults = defaults
        self.configurationOverride = configuration
    }

    var isAvailable: Bool {
        let configuration = configurationOverride ?? MAITranscribeConfiguration.load(from: defaults, globalLanguage: "zh-CN")
        return (try? configuration.webSocketRequest()) != nil
    }

    func beginCapture(language: String) throws {
        captureLock.lock()
        let alreadyCapturing = captureID != nil
        captureLock.unlock()
        guard !alreadyCapturing else { return }

        let configuration = configurationOverride ?? MAITranscribeConfiguration.load(from: defaults, globalLanguage: language)
        _ = try configuration.webSocketRequest()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(MAITranscribeConfiguration.sampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw SpeechRecognitionError.noMicrophone
        }

        let sessionID = initializeSession(configuration: configuration)
        captureLock.lock()
        captureID = sessionID
        captureLock.unlock()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.captureLock.lock()
            defer { self.captureLock.unlock() }
            guard self.captureID == sessionID else { return }
            guard let data = Self.convertToPCM16(buffer, converter: converter, targetFormat: targetFormat) else {
                self.queue.async {
                    guard self.captureSessionID == sessionID else { return }
                    self.activeSession?.fail(SpeechRecognitionError.recognitionFailed(reason: "MAI 音频转换失败，请检查麦克风。"))
                }
                return
            }
            self.queue.async { [weak self] in self?.bufferAudio(data, sessionID: sessionID) }
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            log.info("Microphone capture started (16kHz mono PCM16)", tag: "MAITranscribe")
        } catch {
            cancelRecognition()
            throw SpeechRecognitionError.recognitionFailed(reason: error.localizedDescription)
        }
    }

    private func initializeSession(configuration: MAITranscribeConfiguration) -> UUID {
        let sessionID = UUID()
        let session = MAITranscribeSession(configuration: configuration) { [weak self] error in
            self?.queue.async { [weak self] in
                guard let self, self.captureSessionID == sessionID else { return }
                self.closeConnection()
                DispatchQueue.main.async { [weak self] in self?.stopAudioCapture(sessionID: sessionID) }
                if case SpeechRecognitionError.cancelled = error { return }
                self.log.info("MAI transcription failed", tag: "MAITranscribe")
                self.statusHandler?("MAI Transcribe 连接或转写错误")
                self.errorHandler?(error)
            }
        }
        queue.sync {
            closeConnection()
            activeSession = session
            captureSessionID = sessionID
            totalAudioBytes = 0
        }
        return sessionID
    }

    func transcribePCM16(_ audio: Data, language: String = "zh-CN") async throws -> String {
        guard !audio.isEmpty, audio.count.isMultiple(of: 2),
              audio.count < MAITranscribeConfiguration.sampleRate * 2 * 3600 else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 流式音频必须是非空的 16kHz 单声道 PCM16，且短于 1 小时。")
        }
        guard queue.sync(execute: { activeSession == nil || activeSession?.isActive == false }) else {
            throw SpeechRecognitionError.recognitionFailed(reason: "MAI 已有转写会话进行中。")
        }
        let configuration = configurationOverride ?? MAITranscribeConfiguration.load(from: defaults, globalLanguage: language)
        _ = try configuration.webSocketRequest()
        let sessionID = initializeSession(configuration: configuration)
        return try await withTaskCancellationHandler {
            do {
                try await startRecognition(language: language)
                let chunkBytes = MAITranscribeConfiguration.sampleRate / 50 * 2
                for offset in stride(from: 0, to: audio.count, by: chunkBytes) {
                    try Task.checkCancellation()
                    try queue.sync {
                        guard captureSessionID == sessionID, activeSession?.isActive == true else {
                            throw SpeechRecognitionError.cancelled
                        }
                        bufferAudio(audio.subdata(in: offset..<min(offset + chunkBytes, audio.count)), sessionID: sessionID)
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                return try await stopRecognition()
            } catch {
                cancelRecognition()
                throw error
            }
        } onCancel: {
            self.cancelRecognition()
        }
    }

    func startRecognition(language: String) async throws {
        try Task.checkCancellation()
        if queue.sync(execute: { activeSession == nil }) {
            try await MainActor.run { try beginCapture(language: language) }
        }
        guard let session = queue.sync(execute: { activeSession }) else {
            throw SpeechRecognitionError.cancelled
        }
        let request = try session.configuration.webSocketRequest()
        let sessionID = queue.sync { captureSessionID }
        guard let sessionID else { throw SpeechRecognitionError.cancelled }
        let client = URLSession(configuration: .ephemeral)
        let task = client.webSocketTask(with: request)
        queue.sync {
            urlSession = client
            socket = task
            statusHandler?("正在连接 MAI Transcribe...")
        }

        do {
            try await session.connect(timeoutSeconds: requestTimeout,
                send: { [weak self] message in
                    self?.queue.async { [weak self] in
                        guard let self, self.captureSessionID == sessionID else { return }
                        self.enqueue(message, audioBytes: 0)
                    }
                },
                open: { [weak self] in
                    self?.queue.async { [weak self] in
                        guard let self, self.captureSessionID == sessionID, session.isActive else { return }
                        task.resume()
                        self.receiveNext(task: task, session: session, sessionID: sessionID)
                    }
                })
            try Task.checkCancellation()
            queue.sync {
                guard captureSessionID == sessionID, session.isReady else { return }
                ready = true
                let audio = pendingAudio
                pendingAudio.removeAll()
                for chunk in audio { enqueueAudio(chunk) }
                statusHandler?("MAI Transcribe 已连接，正在听...")
                log.info("Realtime session configured", tag: "MAITranscribe")
            }
        } catch {
            session.fail(error)
            queue.sync {
                if captureSessionID == sessionID { closeConnection() }
            }
            await MainActor.run { stopAudioCapture(sessionID: sessionID) }
            throw error
        }
    }

    func stopRecognition() async throws -> String {
        guard let session = queue.sync(execute: { activeSession }),
              let sessionID = queue.sync(execute: { captureSessionID }) else {
            throw SpeechRecognitionError.cancelled
        }
        await MainActor.run { stopAudioCapture(sessionID: sessionID) }
        defer {
            queue.sync {
                if captureSessionID == sessionID { closeConnection() }
            }
        }
        try Task.checkCancellation()
        guard session.isReady else {
            return try await session.finish(timeoutSeconds: requestTimeout)
        }
        if queue.sync(execute: { totalAudioBytes == 0 }) {
            session.cancel()
            return ""
        }
        queue.sync { statusHandler?("正在等待 MAI Transcribe 最终转写...") }
        return try await session.finish(timeoutSeconds: requestTimeout)
    }

    func cancelRecognition() {
        let sessionID = queue.sync { captureSessionID }
        queue.sync { activeSession }?.cancel()
        if Thread.isMainThread {
            stopAudioCapture(sessionID: sessionID)
        } else {
            DispatchQueue.main.async { [weak self] in self?.stopAudioCapture(sessionID: sessionID) }
        }
    }

    func onPartialResult(_ handler: @escaping (SpeechRecognitionResult) -> Void) { queue.sync { partialResultHandler = handler } }
    func onError(_ handler: @escaping (Error) -> Void) { queue.sync { errorHandler = handler } }
    func onStatus(_ handler: @escaping (String) -> Void) { queue.sync { statusHandler = handler } }

    private var requestTimeout: Double {
        let configured = defaults.object(forKey: "apiTimeout") as? Double ?? 10
        return configured.isFinite ? max(10, min(configured, 240)) : 10
    }

    static func convertToPCM16(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var suppliedInput = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, let samples = converted.floatChannelData else { return nil }
        var pcm = [Int16](repeating: 0, count: Int(converted.frameLength))
        for index in pcm.indices {
            guard samples[0][index].isFinite else { return nil }
            let sample = max(-1, min(1, samples[0][index]))
            pcm[index] = (sample < 0 ? Int16(sample * 32768) : Int16(sample * 32767)).littleEndian
        }
        return pcm.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func stopAudioCapture(sessionID: UUID?) {
        captureLock.lock()
        guard let sessionID, captureID == sessionID else {
            captureLock.unlock()
            return
        }
        captureID = nil
        captureLock.unlock()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func bufferAudio(_ data: Data, sessionID: UUID) {
        guard captureSessionID == sessionID, let session = activeSession, session.isActive, !data.isEmpty else { return }
        guard bufferedAudioBytes + data.count <= maxBufferedAudioBytes else {
            session.fail(SpeechRecognitionError.recognitionFailed(reason: "MAI 音频发送积压，未丢弃音频或插入不完整文本，请检查网络后重试。"))
            return
        }
        bufferedAudioBytes += data.count
        totalAudioBytes += data.count
        let chunkBytes = MAITranscribeConfiguration.sampleRate / 50 * 2
        for offset in stride(from: 0, to: data.count, by: chunkBytes) {
            let chunk = data.subdata(in: offset..<min(offset + chunkBytes, data.count))
            if ready { enqueueAudio(chunk) } else { pendingAudio.append(chunk) }
        }
    }

    private func enqueueAudio(_ data: Data) {
        enqueue(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()], audioBytes: data.count)
    }

    private func enqueue(_ object: [String: Any], audioBytes: Int) {
        guard socket != nil, activeSession?.isActive == true else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard let text = String(data: data, encoding: .utf8) else { return }
            outbound.append(OutboundMessage(text: text, audioBytes: audioBytes))
            sendNext()
        } catch {
            activeSession?.fail(error)
        }
    }

    private func sendNext() {
        guard !sending, !outbound.isEmpty, let socket, let session = activeSession, session.isActive else { return }
        sending = true
        let message = outbound.removeFirst()
        socket.send(.string(message.text)) { [weak self] error in
            self?.queue.async { [weak self] in
                guard let self, self.socket === socket else { return }
                self.sending = false
                self.bufferedAudioBytes -= message.audioBytes
                if let error { session.fail(SpeechRecognitionError.networkError(underlying: error)) }
                else { self.sendNext() }
            }
        }
    }

    private func receiveNext(task: URLSessionWebSocketTask, session: MAITranscribeSession, sessionID: UUID) {
        task.receive { [weak self] received in
            self?.queue.async { [weak self] in
                guard let self, self.socket === task, self.captureSessionID == sessionID, session.isActive else { return }
                do {
                    let message = try received.get()
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: throw SpeechRecognitionError.recognitionFailed(reason: "MAI 返回了未知消息格式。")
                    }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw SpeechRecognitionError.recognitionFailed(reason: "MAI 返回了无效的转写事件。")
                    }
                    if let result = session.receive(event) { self.partialResultHandler?(result) }
                    if session.isActive { self.receiveNext(task: task, session: session, sessionID: sessionID) }
                } catch {
                    session.fail(SpeechRecognitionError.networkError(underlying: error))
                }
            }
        }
    }

    private func closeConnection() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        ready = false
        pendingAudio.removeAll()
        outbound.removeAll()
        sending = false
        bufferedAudioBytes = 0
        activeSession = nil
        captureSessionID = nil
    }
}
