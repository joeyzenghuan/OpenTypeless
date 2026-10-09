import Foundation

enum AzureSpeechRefinement {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "azureSpeechPostRefinementEnabled") as? Bool ?? true
    }

    // Monolingual GA support, checked against Microsoft Learn on 2026-09-19.
    // https://learn.microsoft.com/azure/ai-services/speech-service/regions?tabs=stt
    static let regions: Set<String> = [
        "australiaeast", "brazilsouth", "canadacentral", "centralindia", "eastus", "eastus2",
        "francecentral", "germanywestcentral", "italynorth", "japaneast", "japanwest",
        "koreacentral", "northcentralus", "northeurope", "southcentralus", "southeastasia",
        "swedencentral", "uksouth", "westus", "westus2", "westus3"
    ]
    // https://learn.microsoft.com/azure/ai-services/speech-service/language-support?tabs=stt
    static let languages: Set<String> = [
        "ar-sa", "bn-in", "cs-cz", "de-ch", "de-de", "el-gr", "en-gb", "en-in", "en-us",
        "es-es", "es-mx", "fi-fi", "fr-fr", "hi-in", "id-id", "it-it", "ja-jp", "ko-kr",
        "mr-in", "nl-nl", "pa-in", "pl-pl", "pt-br", "ru-ru", "sv-se", "te-in", "th-th",
        "tr-tr", "zh-cn"
    ]

    static func configurationIssue(region: String, language: String) -> String? {
        if !regions.contains(region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return "当前区域不在 Azure 单语言精修支持列表中。请配置支持区域的资源及对应 Key，或关闭最终精修。"
        }
        if !languages.contains(language.lowercased()) {
            return "当前识别语言不在 Azure 单语言精修支持列表中。请选择受支持的语言，或关闭最终精修。"
        }
        return nil
    }
}

/// One SDK session, isolated from subsequent recordings. All callbacks and stop/cancel
/// paths are serialized here. Refinement failures can recover previews with explicit metadata.
final class AzureSpeechSession: @unchecked Sendable {
    private struct Segment {
        var preview: String?
        var final: String?
        var duration: UInt64 = 0
    }

    let refinementEnabled: Bool
    let traceID = String(UUID().uuidString.prefix(8))
    private let language: String
    private let queue = DispatchQueue(label: "OpenTypeless.AzureSpeechSession")
    private var segments: [UInt64: Segment] = [:]
    private var sessionEnded = false
    private var stopReturned = false
    private var stopRequested = false
    private var stopDispatched = false
    private var failure: Error?
    private var cancelled = false
    private var recoverableFailureReason: String?
    private var fallback: SpeechRefinementFallback?
    private var previewEventCount = 0
    private var finalEventCount = 0
    private var ignoredEventCount = 0
    private var completed = false
    private var waiter: CheckedContinuation<String, Error>?
    private var timeout: DispatchWorkItem?

    init(language: String, refinementEnabled: Bool) {
        self.language = language
        self.refinementEnabled = refinementEnabled
    }

    var previewText: String {
        queue.sync { join(segments.keys.sorted().compactMap { segments[$0]?.preview }) }
    }

    var isActive: Bool { queue.sync { failure == nil && !completed } }

    var lastFallback: SpeechRefinementFallback? { queue.sync { fallback } }

    var canRecoverText: Bool {
        queue.sync { refinementEnabled && !cancelled && !recoveryText.isEmpty }
    }

    var diagnosticSummary: String {
        queue.sync {
            "previews=\(previewEventCount), finals=\(finalEventCount), ignored=\(ignoredEventCount), pending=\(segments.values.filter { $0.preview != nil && $0.final == nil }.count), ended=\(sessionEnded), stopReturned=\(stopReturned)"
        }
    }

    func receive(text: String, offset: UInt64, duration: UInt64 = 0, isFinal: Bool) -> SpeechRecognitionResult? {
        queue.sync {
            if isFinal { finalEventCount += 1 } else { previewEventCount += 1 }
            guard !completed, failure == nil, !sessionEnded, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                ignoredEventCount += 1
                return nil
            }
            var segment = segments[offset] ?? Segment()
            // Azure can adjust an utterance's offset between Recognizing and Recognized.
            // Require substantial overlap: a tiny shared boundary is a different sentence.
            let overlapping = segments.keys.filter { start in
                guard let previous = segments[start] else { return false }
                if start == offset { return true }
                guard previous.duration > 0, duration > 0 else { return false }
                let overlapStart = max(start, offset)
                let overlapEnd = min(start + previous.duration, offset + duration)
                guard overlapEnd > overlapStart else { return false }
                return Double(overlapEnd - overlapStart) / Double(min(previous.duration, duration)) >= 0.5
            }.sorted()
            if isFinal {
                // Adjacent utterances can have overlapping timestamps. Never delete an
                // already-finalized sentence just because the next sentence overlaps it.
                let matchingDrafts = overlapping.filter { segments[$0]?.final == nil || $0 == offset }
                let previews = matchingDrafts.compactMap { segments[$0]?.preview }
                if !previews.isEmpty { segment.preview = join(previews) }
                for start in matchingDrafts where start != offset { segments.removeValue(forKey: start) }
                segment.final = text
            } else {
                // Ignore stale previews fully covered by a final, while allowing a new
                // sentence whose start slightly overlaps the previous sentence's end.
                guard !overlapping.contains(where: { start in
                    guard let previous = segments[start], previous.final != nil else { return false }
                    return start == offset || offset + duration <= start + previous.duration
                }) else {
                    ignoredEventCount += 1
                    return nil
                }
                for start in overlapping where start != offset && segments[start]?.final == nil {
                    segments.removeValue(forKey: start)
                }
                segment.preview = text
            }
            segment.duration = duration
            segments[offset] = segment
            let ordered = segments.keys.sorted().compactMap { segments[$0] }
            return SpeechRecognitionResult(
                text: join(ordered.compactMap { $0.final ?? $0.preview }),
                isFinal: isFinal, confidence: nil, language: language,
                stages: SpeechRecognitionStages(
                    previewText: join(ordered.compactMap(\.preview)),
                    finalText: join(ordered.compactMap(\.final)),
                    postRefinementEnabled: refinementEnabled
                )
            )
        }
    }

    func markSessionEnded() {
        queue.sync {
            sessionEnded = true
            resolveIfReady()
        }
    }

    func markStopReturned() {
        queue.sync {
            stopReturned = true
            resolveIfReady()
        }
    }

    func fail(_ error: Error, recoveryReason: String? = nil) {
        queue.sync {
            guard !completed, !cancelled else { return }
            if error is CancellationError { cancelled = true }
            if let speechError = error as? SpeechRecognitionError, case .cancelled = speechError { cancelled = true }
            failure = error
            recoverableFailureReason = recoveryReason
            resolveIfReady()
        }
    }

    func finish(timeoutSeconds: TimeInterval = 20, stop: @escaping @Sendable () -> Void) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.stopRequested else {
                        continuation.resume(throwing: SpeechRecognitionError.recognitionFailed(reason: "重复停止识别"))
                        return
                    }
                    self.stopRequested = true
                    self.waiter = continuation
                    let timeout = DispatchWorkItem { [weak self] in
                        guard let self, !self.completed else { return }
                        self.failure = SpeechRecognitionError.recognitionFailed(
                            reason: "等待 Azure 最终结果超时，且没有可恢复的识别文本。请重试。"
                        )
                        self.recoverableFailureReason = "等待 Azure 精修超时"
                        self.resolveIfReady()
                    }
                    self.timeout = timeout
                    self.queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
                    self.resolveIfReady()
                    // SDK stop can block; never block the callback/state queue or main thread.
                    self.dispatchStop(stop)
                }
            }
        } onCancel: {
            self.fail(CancellationError())
        }
    }

    func stopOnce(_ stop: @escaping @Sendable () -> Void) {
        queue.async { self.dispatchStop(stop) }
    }

    private func dispatchStop(_ stop: @escaping @Sendable () -> Void) {
        guard !stopDispatched else { return }
        stopDispatched = true
        DispatchQueue.global(qos: .userInitiated).async(execute: stop)
    }

    private func resolveIfReady() {
        guard let waiter, !completed else { return }
        let result: Result<String, Error>
        if let failure {
            if let reason = recoverableFailureReason, let text = recover(reason: reason) {
                result = .success(text)
            } else {
                result = .failure(failure)
            }
        } else {
            // Neither a fixed delay nor a partial callback proves finalization completed.
            guard sessionEnded, stopReturned else { return }
            guard !segments.values.contains(where: { $0.preview != nil && $0.final == nil }) else {
                if let text = recover(reason: "Azure 未返回完整精修结果") {
                    result = .success(text)
                } else {
                    result = .failure(SpeechRecognitionError.recognitionFailed(
                        reason: "Azure 未返回完整的最终识别结果。请重试。"
                    ))
                }
                complete(waiter, with: result)
                return
            }
            result = .success(join(segments.keys.sorted().compactMap { segments[$0]?.final }))
        }
        complete(waiter, with: result)
    }

    // Keep completed sentences intact; use previews only for unfinished sentences.
    // A preview can be shorter than its final, so never downgrade a completed segment.
    private var recoveryText: String {
        join(segments.keys.sorted().compactMap { segments[$0]?.final ?? segments[$0]?.preview })
    }

    private func recover(reason: String) -> String? {
        guard refinementEnabled, !cancelled, !recoveryText.isEmpty else { return nil }
        fallback = SpeechRefinementFallback(reason: reason,
            refinedText: join(segments.keys.sorted().compactMap { segments[$0]?.final }))
        return recoveryText
    }

    private func complete(_ waiter: CheckedContinuation<String, Error>, with result: Result<String, Error>) {
        completed = true
        self.waiter = nil
        timeout?.cancel()
        timeout = nil
        waiter.resume(with: result)
    }

    private func join(_ texts: [String]) -> String {
        texts.joined(separator: language.hasPrefix("zh") || language.hasPrefix("ja") ? "" : " ")
    }
}
