import Foundation
import AVFoundation
import Darwin

@main
struct MAITranscribeLiveTests {
    private struct Credentials {
        let batchEndpoint: String
        let batchKey: String
        let streamingEndpoint: String
        let streamingKey: String
        let deployment: String

        static func load() throws -> Credentials {
            let environment = ProcessInfo.processInfo.environment
            for (endpointName, keyName) in [("AZURE_MAI_BATCH_ENDPOINT", "AZURE_MAI_BATCH_API_KEY"),
                                            ("AZURE_MAI_ENDPOINT", "AZURE_MAI_API_KEY")] {
                guard (environment[endpointName] == nil) == (environment[keyName] == nil) else {
                    throw failure("Set both \(endpointName) and \(keyName) to override credentials safely")
                }
            }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let paths = ["Library/Preferences/com.opentypeless.app.plist",
                "Library/Containers/com.opentypeless.app/Data/Library/Preferences/com.opentypeless.app.plist"]
            var preferences: [String: Any] = [:]
            for path in paths {
                if let data = try? Data(contentsOf: home.appendingPathComponent(path)),
                   let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    preferences.merge(values) { _, latest in latest }
                }
            }
            func setting(_ name: String) -> String { preferences[name] as? String ?? "" }
            let reuseSpeech = preferences["maiTranscribeBatchUseAzureSpeech"] as? Bool ?? true
            let region = reuseSpeech ? setting("azureSpeechRegion") : setting("maiTranscribeBatchRegion")
            let independentEndpoint = setting("maiTranscribeBatchEndpoint")
            let batchEndpoint = environment["AZURE_MAI_BATCH_ENDPOINT"] ??
                (!reuseSpeech && !independentEndpoint.isEmpty ? independentEndpoint : "https://\(region).api.cognitive.microsoft.com")
            let batchKey = environment["AZURE_MAI_BATCH_API_KEY"] ??
                setting(reuseSpeech ? "azureSpeechKey" : "maiTranscribeBatchAPIKey")
            var endpoint = setting("maiTranscribeEndpoint")
            var key = setting("maiTranscribeAPIKey")
            if endpoint.isEmpty || key.isEmpty {
                endpoint = setting("gptRealtimeWhisperEndpoint")
                key = setting("gptRealtimeWhisperAPIKey")
                if endpoint.isEmpty || key.isEmpty {
                    endpoint = setting("gpt4oTranscribeEndpoint")
                    key = setting("gpt4oTranscribeAPIKey")
                }
                if var components = URLComponents(string: endpoint) {
                    components.path = ""
                    components.query = nil
                    components.fragment = nil
                    if let host = components.host, host.hasSuffix(".cognitiveservices.azure.com") {
                        components.host = host.replacingOccurrences(of: ".cognitiveservices.azure.com", with: ".services.ai.azure.com")
                    }
                    endpoint = components.string ?? endpoint
                }
            }
            return Credentials(batchEndpoint: batchEndpoint, batchKey: batchKey,
                streamingEndpoint: environment["AZURE_MAI_ENDPOINT"] ?? endpoint,
                streamingKey: environment["AZURE_MAI_API_KEY"] ?? key,
                deployment: environment["AZURE_MAI_DEPLOYMENT_NAME"] ??
                    (setting("maiTranscribeDeployment").isEmpty ? MAITranscribeConfiguration.defaultDeployment : setting("maiTranscribeDeployment")))
        }

        func redact(_ text: String) -> String {
            [batchKey, streamingKey].filter { !$0.isEmpty }.reduce(text) { result, key in
                result.replacingOccurrences(of: key, with: "[REDACTED]")
            }
        }
    }

    static func main() async {
        do {
            guard CommandLine.arguments.count == 4 else {
                throw failure("Usage: mai-live-tests <batch|streaming|all> <zh.wav> <en.wav>")
            }
            let mode = CommandLine.arguments[1]
            guard ["batch", "streaming", "all"].contains(mode) else { throw failure("Unknown test mode") }
            let credentials = try Credentials.load()
            let chineseURL = URL(fileURLWithPath: CommandLine.arguments[2])
            let englishURL = URL(fileURLWithPath: CommandLine.arguments[3])
            var failures = 0
            print("Real Azure MAI tests; only generated speech fixtures are uploaded. No settings or deployments are changed.")
            if mode != "streaming" {
                print("BATCH endpoint: \(credentials.batchEndpoint); model: \(MAITranscribeBatchConfiguration.model)")
                let cases: [(String, URL, String, String, [String], [String])] = [
                    ("Chinese / auto / verbatim", chineseURL, "auto", "verbatim", [], ["语音", "中文"]),
                    ("English / en / clean", englishURL, "en", "clean", [], ["speech", "test"]),
                    ("Chinese / zh / terminology", chineseURL, "zh", "verbatim", ["微软", "语音输入"], ["语音", "中文"]),
                    ("English / auto / verbatim", englishURL, "auto", "verbatim", [], ["speech", "test"])
                ]
                for (label, url, language, style, phrases, expected) in cases {
                    let start = Date()
                    do {
                        let configuration = MAITranscribeBatchConfiguration(endpoint: credentials.batchEndpoint,
                            apiKey: credentials.batchKey, language: language, style: style, phrases: phrases)
                        let text = try await MAITranscribeBatchClient().transcribe(audio: Data(contentsOf: url), configuration: configuration)
                        try validate(text, expected: expected)
                        print("PASS BATCH \(label) (\(elapsed(start))s): \(text)")
                    } catch {
                        failures += 1
                        print("FAIL BATCH \(label) (\(elapsed(start))s): \(credentials.redact(error.localizedDescription))")
                    }
                }
            }
            if mode != "batch" {
                print("STREAMING endpoint: \(credentials.streamingEndpoint); deployment: \(credentials.deployment)")
                for (label, url, expected) in [("Chinese / auto", chineseURL, ["语音", "中文"]),
                                              ("English / auto", englishURL, ["speech", "test"])] {
                    let start = Date()
                    do {
                        let configuration = MAITranscribeConfiguration(endpoint: credentials.streamingEndpoint,
                            deployment: credentials.deployment, apiKey: credentials.streamingKey)
                        let provider = MAITranscribeSpeechProvider(configuration: configuration)
                        provider.onStatus { print("  STATUS: \($0)") }
                        provider.onPartialResult { result in
                            print("  \(result.isFinal ? "FINAL" : "PARTIAL"): \(result.text)")
                        }
                        let text = try await provider.transcribePCM16(pcm16(at: url))
                        try validate(text, expected: expected)
                        print("PASS STREAMING \(label) (\(elapsed(start))s): \(text)")
                    } catch {
                        failures += 1
                        print("FAIL STREAMING \(label) (\(elapsed(start))s): \(credentials.redact(error.localizedDescription))")
                    }
                }
            }
            print("Real Azure tests completed: \(failures) failure(s)")
            if failures > 0 { exit(1) }
        } catch {
            print("Live test setup failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func pcm16(at url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw failure("Cannot decode the generated WAV fixture")
        }
        try file.read(into: buffer)
        guard let pcm = MAITranscribeSpeechProvider.convertToPCM16(buffer, converter: converter, targetFormat: target), !pcm.isEmpty else {
            throw failure("Cannot convert the generated WAV fixture to PCM16")
        }
        return pcm
    }

    private static func validate(_ text: String, expected: [String]) throws {
        guard !text.isEmpty, expected.allSatisfy({ text.localizedCaseInsensitiveContains($0) }) else {
            throw failure("Transcript is empty or does not match the fixture: \(text)")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MAITranscribeLiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func elapsed(_ start: Date) -> String { String(format: "%.2f", Date().timeIntervalSince(start)) }
}
