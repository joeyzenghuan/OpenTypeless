import Foundation
import AVFoundation

private enum MAITestError: Error { case failed(String), networkFailure }

private final class MAIMessageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [[String: Any]] = []

    func append(_ message: [String: Any]) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    var snapshot: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

@main
struct MAITranscribeSessionTests {
    static let prefix = "conversation.item.input_audio_transcription."

    static var configuration: MAITranscribeConfiguration {
        MAITranscribeConfiguration(endpoint: "https://example.services.ai.azure.com/",
            deployment: "my-mai-deployment", apiKey: "test-key")
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw MAITestError.failed(message) }
    }

    static func expectFailure(_ operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw MAITestError.failed("Expected a validation failure")
    }

    static func expectNoOutput(_ operation: () async throws -> String) async throws {
        do { _ = try await operation() } catch { return }
        throw MAITestError.failed("Failure or cancellation must not return clipboard text")
    }

    fileprivate static func connect(_ session: MAITranscribeSession, recorder: MAIMessageRecorder = MAIMessageRecorder(),
                        onCommit: @escaping @Sendable () -> Void = {}) async throws {
        try await session.connect(timeoutSeconds: 1, send: { message in
            recorder.append(message)
            if message["type"] as? String == "session.update" {
                DispatchQueue.global().async { _ = session.receive(["type": "session.updated"]) }
            } else if message["type"] as? String == "input_audio_buffer.commit" {
                DispatchQueue.global().async(execute: onCommit)
            }
        }, open: {
            _ = session.receive(["type": "session.created"])
        })
    }

    static func main() async throws {
        try testConfiguration()
        try testAudioConversion()
        try await testHandshake()
        try await testTranscripts()
        try await testDelayedFinalWithoutPreview()
        try await testFailureAndTimeout()
        try await testCancellation()
        try await MAITranscribeBatchTests.run()
        print("All MAI Transcribe tests passed")
    }

    static func testConfiguration() throws {
        let request = try configuration.webSocketRequest()
        try check(request.url?.absoluteString == "wss://example.services.ai.azure.com/mai/v1/realtime?intent=transcription",
            "MAI uses its own endpoint without OpenAI deployment query parameters")
        try check(request.value(forHTTPHeaderField: "api-key") == "test-key", "Key belongs in the authentication header")
        try check(request.url?.query?.contains("test-key") == false, "Key must not appear in the URL")
        let trimmed = MAITranscribeConfiguration(endpoint: " https://example.services.ai.azure.com ",
            deployment: " custom-deployment ", apiKey: " secret ", language: "pt-BR")
        try check(try trimmed.webSocketRequest().value(forHTTPHeaderField: "api-key") == "secret", "Trim pasted settings")
        try check(trimmed.deployment == "custom-deployment" && trimmed.language == "pt", "Deployment and language hints")
        let input = ((configuration.sessionUpdate["session"] as! [String: Any])["audio"] as! [String: Any])["input"] as! [String: Any]
        let transcription = input["transcription"] as! [String: Any]
        let format = input["format"] as! [String: Any]
        try check(transcription["model"] as? String == "my-mai-deployment", "Model field is the actual deployment name")
        try check(transcription["language"] == nil && transcription["prompt"] == nil, "Auto language omits the field; the live Azure gateway rejects explicit null")
        try check(input["turn_detection"] is NSNull && input["noise_reduction"] is NSNull, "Explicitly disable server-side detection")
        try check(format["type"] as? String == "audio/pcm" && format["rate"] as? Int == 16_000, "16kHz raw PCM configuration")
        _ = try JSONSerialization.data(withJSONObject: configuration.sessionUpdate)
        let chinese = MAITranscribeConfiguration(endpoint: configuration.endpoint,
            deployment: configuration.deployment, apiKey: configuration.apiKey, language: "", globalLanguage: "zh-TW")
        try check(chinese.language == "zh", "Following global language uses the service language code")
        let chineseInput = ((chinese.sessionUpdate["session"] as! [String: Any])["audio"] as! [String: Any])["input"] as! [String: Any]
        try check((chineseInput["transcription"] as? [String: Any])?["language"] as? String == "zh", "Explicit language hint is sent, unlike auto detection")
        for endpoint in ["http://example.com", "ws://example.com", "https://example.com/openai/v1/realtime",
                         "https://user:secret@example.com", "https://example.com?api-key=secret", "https://example.com#fragment"] {
            try expectFailure {
                _ = try MAITranscribeConfiguration(endpoint: endpoint, deployment: "deployment", apiKey: "key").webSocketRequest()
            }
        }
        try expectFailure {
            _ = try MAITranscribeConfiguration(endpoint: configuration.endpoint, deployment: " ", apiKey: "key").webSocketRequest()
        }
        let suite = "OpenTypeless.MAITest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let loaded = MAITranscribeConfiguration.load(from: defaults, globalLanguage: "en-US")
        try check(loaded.language == nil && loaded.deployment == MAITranscribeConfiguration.defaultDeployment, "Fresh settings default to auto")
        defaults.set("", forKey: "maiTranscribeLanguage")
        try check(MAITranscribeConfiguration.load(from: defaults, globalLanguage: "en-US").language == "en", "Saved global-language selection")
        print("PASS secure endpoint, header authentication, JSON configuration, auto/global language, defaults")
    }

    static func testHandshake() async throws {
        let session = MAITranscribeSession(configuration: configuration)
        let recorder = MAIMessageRecorder()
        try await session.connect(timeoutSeconds: 1, send: { message in
            recorder.append(message)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                _ = session.receive(["type": "session.updated"])
            }
        }, open: {
            _ = session.receive(["type": "session.created"])
            recorder.append(["readyAfterCreated": session.isReady])
            _ = session.receive(["type": "session.created"])
        })
        try check(session.isReady, "Ready only after session.updated")
        try check(recorder.snapshot.contains { $0["readyAfterCreated"] as? Bool == false }, "session.created is not configuration acknowledgement")
        try check(recorder.snapshot.filter { $0["type"] as? String == "session.update" }.count == 1, "Duplicate created must not reconfigure")
        session.cancel()

        let outOfOrder = MAITranscribeSession(configuration: configuration)
        do {
            try await outOfOrder.connect(timeoutSeconds: 0.03, send: { _ in }, open: {
                _ = outOfOrder.receive(["type": "session.updated"])
            })
            throw MAITestError.failed("Unsolicited session.updated must not release audio")
        } catch is SpeechRecognitionError {}
        print("PASS handshake ordering, duplicate configuration, configuration timeout")
    }

    static func testAudioConversion() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 5)!
        input.frameLength = 5
        let samples: [Float] = [-2, -0.5, 0, 0.5, 2]
        for index in samples.indices { input.floatChannelData![0][index] = samples[index] }
        let converter = AVAudioConverter(from: format, to: format)!
        guard let encoded = MAITranscribeSpeechProvider.convertToPCM16(input, converter: converter, targetFormat: format) else {
            throw MAITestError.failed("PCM conversion failed")
        }
        let decoded = encoded.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Int16(littleEndian: $0) }
        }
        try check(decoded == [Int16.min, -16384, 0, 16383, Int16.max], "Signed PCM16 clipping and little-endian samples")
        try check(encoded.count == 10, "Raw PCM has no WAV header")

        let microphoneFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let microphone = AVAudioPCMBuffer(pcmFormat: microphoneFormat, frameCapacity: 960)!
        microphone.frameLength = 960
        for channel in 0..<2 {
            for frame in 0..<960 { microphone.floatChannelData![channel][frame] = 0.25 }
        }
        let resampler = AVAudioConverter(from: microphoneFormat, to: format)!
        let mono = MAITranscribeSpeechProvider.convertToPCM16(microphone, converter: resampler, targetFormat: format)
        try check(mono != nil && mono!.count > 0 && mono!.count <= 640 && mono!.count % 2 == 0,
            "48kHz stereo microphone resamples to 16kHz mono PCM16")
        print("PASS raw PCM16 encoding, clipping, byte order, stereo downmix and resampling")
    }

    static func testTranscripts() async throws {
        let session = MAITranscribeSession(configuration: configuration)
        let recorder = MAIMessageRecorder()
        try await connect(session, recorder: recorder) {
            _ = session.receive(["type": "input_audio_buffer.committed"])
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                _ = session.receive(["type": prefix + "completed", "transcript": "Hello there!"])
            }
        }
        _ = session.receive(["type": prefix + "delta", "delta": "Hello"])
        _ = session.receive(["type": prefix + "intermediate", "intermediate": " world"])
        try check(session.previewText == "Hello world", "Intermediate suffix follows the finalized prefix")
        let revised = session.receive(["type": prefix + "intermediate", "intermediate": " there"])
        try check(revised?.text == "Hello there", "Intermediate replaces, never appends")
        let delta = session.receive(["type": prefix + "delta", "delta": " there!"])
        try check(delta?.text == "Hello there!" && delta?.isFinal == false, "Delta clears stale suffix but is not session completion")
        _ = session.receive(["type": prefix + "intermediate", "intermediate": " extra"])
        _ = session.receive(["type": prefix + "intermediate", "intermediate": ""])
        try check(session.previewText == "Hello there!", "Empty suffix clears a stale hypothesis")
        try check(session.receive(["type": prefix + "completed", "transcript": "premature"]) == nil, "No output before explicit commit")
        let began = Date()
        let text = try await session.finish(timeoutSeconds: 1)
        try check(text == "Hello there!" && Date().timeIntervalSince(began) >= 0.3, "Commit acknowledgement must not substitute for delayed completed")
        try check(recorder.snapshot.filter { $0["type"] as? String == "input_audio_buffer.commit" }.count == 1, "Commit exactly once")
        try check(session.receive(["type": prefix + "completed", "transcript": "duplicate"]) == nil, "Ignore duplicate completions")
        try check(session.receive(["type": prefix + "delta", "delta": "late"]) == nil, "Ignore late callbacks")
        try check(try await session.finish() == "Hello there!", "Repeated finish cannot duplicate final text")
        print("PASS MAI-specific suffix replacement, exact whitespace, explicit commit, delayed final, late events")

        let chinese = MAITranscribeSession(configuration: configuration)
        try await connect(chinese) {
            _ = chinese.receive(["type": prefix + "completed", "transcript": "微软语音转写。"])
        }
        _ = chinese.receive(["type": prefix + "delta", "delta": "微软"])
        _ = chinese.receive(["type": prefix + "delta", "delta": "语音"])
        _ = chinese.receive(["type": prefix + "intermediate", "intermediate": "转换"])
        try check(chinese.previewText == "微软语音转换", "No fabricated spaces in Chinese")
        try check(try await chinese.finish() == "微软语音转写。", "Authoritative final replaces the preview")
        print("PASS Chinese boundaries and final correction")
    }

    static func testDelayedFinalWithoutPreview() async throws {
        let session = MAITranscribeSession(configuration: configuration)
        try await connect(session) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.9) {
                _ = session.receive(["type": prefix + "completed", "transcript": "Delayed transcript"])
            }
        }
        try check(try await session.finish(timeoutSeconds: 2) == "Delayed transcript", "Silence or absent partials must not cause premature empty output")
        print("PASS final without partials after the previous early-return window")
    }

    static func testFailureAndTimeout() async throws {
        let timedOut = MAITranscribeSession(configuration: configuration)
        try await connect(timedOut)
        _ = timedOut.receive(["type": prefix + "delta", "delta": "Incomplete preview"])
        try await expectNoOutput { try await timedOut.finish(timeoutSeconds: 0.03) }
        try check(timedOut.receive(["type": prefix + "completed", "transcript": "late"]) == nil, "Timeout is terminal")

        let failed = MAITranscribeSession(configuration: configuration)
        try await connect(failed) { failed.fail(MAITestError.networkFailure) }
        _ = failed.receive(["type": prefix + "intermediate", "intermediate": "Preview"])
        try await expectNoOutput { try await failed.finish() }

        let serverError = MAITranscribeSession(configuration: configuration)
        try await connect(serverError) {
            _ = serverError.receive(["type": prefix + "failed", "error": ["message": "Invalid deployment"]])
        }
        try await expectNoOutput { try await serverError.finish() }

        let empty = MAITranscribeSession(configuration: configuration)
        try await connect(empty) { _ = empty.receive(["type": prefix + "completed", "transcript": ""]) }
        try check(try await empty.finish() == "", "A valid empty final is not a timeout")
        print("PASS final timeout, network failure, server failure, empty final, no preview fallback")
    }

    static func testCancellation() async throws {
        let beforeStart = MAITranscribeSession(configuration: configuration)
        beforeStart.cancel()
        do {
            try await connect(beforeStart)
            throw MAITestError.failed("Cancellation before start must survive connect")
        } catch is SpeechRecognitionError {}

        let connecting = MAITranscribeSession(configuration: configuration)
        let connectionTask = Task {
            try await connecting.connect(timeoutSeconds: 1, send: { _ in }, open: {})
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        connectionTask.cancel()
        do {
            try await connectionTask.value
            throw MAITestError.failed("Cancelled connection must not succeed")
        } catch is SpeechRecognitionError {} catch is CancellationError {}

        let finishing = MAITranscribeSession(configuration: configuration)
        try await connect(finishing)
        _ = finishing.receive(["type": prefix + "intermediate", "intermediate": "Cancelled preview"])
        let finishTask = Task { try await finishing.finish() }
        try await Task.sleep(nanoseconds: 10_000_000)
        finishTask.cancel()
        try await expectNoOutput { try await finishTask.value }
        try check(finishing.receive(["type": prefix + "completed", "transcript": "late"]) == nil, "Cancelled session ignores a late final")

        let next = MAITranscribeSession(configuration: configuration)
        try await connect(next) { _ = next.receive(["type": prefix + "completed", "transcript": "New session"] ) }
        try check(try await next.finish() == "New session", "Cancelled session cannot contaminate the next recording")
        print("PASS cancellation before start, during connection/final wait, and session isolation")
    }
}
