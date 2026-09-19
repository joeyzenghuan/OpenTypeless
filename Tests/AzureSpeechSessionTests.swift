import Foundation
import SQLite3

private enum TestError: Error { case failed(String), serviceFailure }

@main
struct AzureSpeechSessionTests {
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestError.failed(message) }
    }

    static func expectFailure(_ session: AzureSpeechSession, stop: @escaping @Sendable () -> Void = {}) async throws {
        // Represents the clipboard sink: stopRecognition output, including marked fallback.
        var clipboard: String?
        do { clipboard = try await session.finish(timeoutSeconds: 0.03, stop: stop) }
        catch { return }
        throw TestError.failed("Failure must not produce clipboard text: \(clipboard ?? "nil")")
    }

    static func main() async throws {
        let session = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = session.receive(text: "微软语音经修", offset: 0, isFinal: false)
        let began = Date()
        let result = try await session.finish(timeoutSeconds: 2) {
            session.markStopReturned()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                _ = session.receive(text: "微软语音精修。", offset: 0, isFinal: true)
                session.markSessionEnded()
            }
        }
        try check(result == "微软语音精修。", "Only refined text reaches output")
        try check(Date().timeIntervalSince(began) >= 0.3, "Must wait beyond old 200ms delay")
        try check(session.previewText == "微软语音经修", "Preview survives finalization for history")
        try check(session.receive(text: "late", offset: 0, isFinal: false) == nil, "Late events ignored")
        print("PASS delayed refinement, clipboard output, preview preservation, late callback")

        let segments = AzureSpeechSession(language: "en-US", refinementEnabled: true)
        _ = segments.receive(text: "world", offset: 20, isFinal: false)
        _ = segments.receive(text: "hello", offset: 0, isFinal: false)
        _ = segments.receive(text: "World.", offset: 20, isFinal: true)
        _ = segments.receive(text: "Hello.", offset: 0, isFinal: true)
        let snapshot = segments.receive(text: "Hello!", offset: 0, isFinal: true)
        try check(snapshot?.stages?.previewText == "hello world", "Previews ordered by audio offset")
        try check(snapshot?.stages?.finalText == "Hello! World.", "Duplicate finals replace, not append")
        try check(segments.receive(text: "stale", offset: 0, isFinal: false) == nil, "Final cannot regress")
        segments.markSessionEnded()
        let combined = try await segments.finish { segments.markStopReturned() }
        try check(combined == "Hello! World.", "Segment ordering and word boundaries")
        print("PASS multi-segment order, duplicate final, final-before-stop, no regression")

        let shifted = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = shifted.receive(text: "中间", offset: 100, duration: 200, isFinal: false)
        _ = shifted.receive(text: "中间结果", offset: 110, duration: 400, isFinal: false)
        _ = shifted.receive(text: "最终结果。", offset: 90, duration: 440, isFinal: true)
        _ = shifted.receive(text: "第二句。", offset: 700, duration: 100, isFinal: true)
        let shiftedText = try await shifted.finish { shifted.markSessionEnded(); shifted.markStopReturned() }
        try check(shiftedText == "最终结果。第二句。", "Adjusted offsets match by audio interval")
        try check(shifted.previewText == "中间结果", "Offset revisions do not duplicate previews")
        print("PASS Azure offset drift, final-only segment, preview replacement")

        let adjacent = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = adjacent.receive(text: "第一句", offset: 100, duration: 220, isFinal: false)
        _ = adjacent.receive(text: "第一句。", offset: 90, duration: 240, isFinal: true)
        let secondPreview = adjacent.receive(text: "第二句", offset: 320, duration: 250, isFinal: false)
        try check(secondPreview?.text == "第一句。第二句", "Slightly overlapping next preview must not be discarded")
        _ = adjacent.receive(text: "第二句。", offset: 310, duration: 270, isFinal: true)
        let adjacentText = try await adjacent.finish { adjacent.markSessionEnded(); adjacent.markStopReturned() }
        try check(adjacentText == "第一句。第二句。", "Adjacent final must not delete previous finalized sentence")
        try check(adjacent.previewText == "第一句第二句", "Keep both previews for history")
        print("PASS adjacent overlapping timestamps retain both utterances")

        let queuedNext = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = queuedNext.receive(text: "第一句", offset: 100, duration: 230, isFinal: false)
        _ = queuedNext.receive(text: "第二句还在等待", offset: 320, duration: 250, isFinal: false)
        _ = queuedNext.receive(text: "第一句。", offset: 90, duration: 250, isFinal: true)
        let queuedOutput = try await queuedNext.finish { queuedNext.markSessionEnded(); queuedNext.markStopReturned() }
        try check(queuedOutput == "第一句。第二句还在等待" && queuedNext.lastFallback != nil,
                  "Earlier final must not consume adjacent pending sentence and falsely succeed")
        let reverseFinals = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = reverseFinals.receive(text: "第二句。", offset: 320, duration: 250, isFinal: true)
        _ = reverseFinals.receive(text: "第一句。", offset: 90, duration: 250, isFinal: true)
        let reverseText = try await reverseFinals.finish { reverseFinals.markSessionEnded(); reverseFinals.markStopReturned() }
        try check(reverseText == "第一句。第二句。", "Out-of-order adjacent finals remain in audio order")
        print("PASS pending next sentence and out-of-order finals are not consumed by overlap")

        let pending = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = pending.receive(text: "前", offset: 0, isFinal: false)
        _ = pending.receive(text: "前段。", offset: 0, isFinal: true)
        _ = pending.receive(text: "未精修的尾段", offset: 20, isFinal: false)
        let recovered = try await pending.finish { pending.markStopReturned(); pending.markSessionEnded() }
        try check(recovered == "前段。未精修的尾段", "Fallback keeps complete finals even if their previews were shorter")
        try check(pending.lastFallback?.reason == "Azure 未返回完整精修结果", "Missing finals carry fallback metadata")
        try check(pending.lastFallback?.refinedText == "前段。", "Fallback must not label preview as refined")
        try check(pending.receive(text: "迟到的尾段。", offset: 20, isFinal: true) == nil, "Late final cannot trigger a second output")
        let screenshot = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = screenshot.receive(text: "hello你好能听到我说话吗", offset: 10, duration: 200, isFinal: false)
        let screenshotText = try await screenshot.finish { screenshot.markSessionEnded(); screenshot.markStopReturned() }
        try check(screenshotText == "hello你好能听到我说话吗", "No Recognized callback recovers screenshot preview")
        try check(screenshot.lastFallback?.refinedText == "", "No final received must not claim refined text")
        let timedOut = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = timedOut.receive(text: "超时保留文字", offset: 0, isFinal: false)
        let timeoutText = try await timedOut.finish(timeoutSeconds: 0.03) { timedOut.markStopReturned() }
        try check(timeoutText == "超时保留文字" && timedOut.lastFallback != nil, "Timeout preserves available text")
        let serviceFailure = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = serviceFailure.receive(text: "连接断开前的文字", offset: 0, isFinal: false)
        serviceFailure.fail(TestError.serviceFailure, recoveryReason: "Azure 精修服务或连接异常")
        let serviceText = try await serviceFailure.finish(stop: {})
        try check(serviceText == "连接断开前的文字" && serviceFailure.lastFallback != nil, "Service error before release can recover")
        print("PASS missing finals, preview-only NoMatch, timeout, service failure, no duplicate delivery")

        let noText = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        try await expectFailure(noText)
        let noServiceText = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        noServiceText.fail(TestError.serviceFailure, recoveryReason: "服务异常")
        try await expectFailure(noServiceText)
        let standardMissing = AzureSpeechSession(language: "zh-CN", refinementEnabled: false)
        _ = standardMissing.receive(text: "标准模式未完成", offset: 0, isFinal: false)
        try await expectFailure(standardMissing) { standardMissing.markSessionEnded(); standardMissing.markStopReturned() }
        let failed = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = failed.receive(text: "已精修也不能在断线后部分输出", offset: 0, isFinal: true)
        failed.fail(TestError.serviceFailure)
        try await expectFailure(failed)
        let stopFailed = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        try await expectFailure(stopFailed) { stopFailed.fail(TestError.serviceFailure) }
        print("PASS empty results, standard mode, nonrecoverable errors, stop failure: no output")

        let cancelled = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = cancelled.receive(text: "取消后不能粘贴", offset: 0, isFinal: false)
        let task = Task { try await cancelled.finish(timeoutSeconds: 2, stop: {}) }
        task.cancel()
        do { _ = try await task.value; throw TestError.failed("Cancellation returned output") }
        catch is CancellationError { }
        let explicitCancel = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        _ = explicitCancel.receive(text: "取消后不能降级", offset: 0, isFinal: false)
        explicitCancel.fail(SpeechRecognitionError.cancelled)
        explicitCancel.fail(TestError.serviceFailure, recoveryReason: "迟到的服务错误")
        try await expectFailure(explicitCancel)
        try check(explicitCancel.lastFallback == nil, "Service error cannot override cancellation")
        let silent = AzureSpeechSession(language: "zh-CN", refinementEnabled: true)
        let empty = try await silent.finish { silent.markSessionEnded(); silent.markStopReturned() }
        try check(empty.isEmpty, "Silence returns no insertion text")
        let standard = AzureSpeechSession(language: "en-US", refinementEnabled: false)
        let standardEvent = standard.receive(text: "Standard.", offset: 0, isFinal: true)
        try check(standardEvent?.stages?.postRefinementEnabled == false, "Disabled mode never claims refinement")
        let standardText = try await standard.finish { standard.markSessionEnded(); standard.markStopReturned() }
        try check(standardText == "Standard.", "Disabled mode still uses final results")
        try check(standard.lastFallback == nil && session.lastFallback == nil, "Successful recognition is never marked fallback")
        print("PASS cancellation, silence, refinement disabled")

        // Both modes must expose the same two display stages across a pause.
        for postEnabled in [false, true] {
            let twoSentences = AzureSpeechSession(language: "zh-CN", refinementEnabled: postEnabled)
            _ = twoSentences.receive(text: "看一下有什么亮点", offset: 700_000, duration: 16_400_000, isFinal: false)
            let firstFinal = twoSentences.receive(text: "看一下有什么亮点。", offset: 700_000, duration: 16_400_000, isFinal: true)
            try check(firstFinal?.stages?.previewText == "看一下有什么亮点", "Keep original preview after first sentence final")
            let secondPartial = twoSentences.receive(text: "第二句话请检查", offset: 37_100_000, duration: 10_000_000, isFinal: false)
            try check(secondPartial?.stages?.previewText == "看一下有什么亮点第二句话请检查", "Top row accumulates previews across two-second silence")
            try check(secondPartial?.stages?.finalText == "看一下有什么亮点。", "Bottom row keeps first final while second sentence is partial")
            try check(secondPartial?.stages?.postRefinementEnabled == postEnabled, "Display mode matches service configuration")
            let secondFinal = twoSentences.receive(text: "第二句话，请检查最终结果。", offset: 37_100_000, duration: 20_000_000, isFinal: true)
            let expected = "看一下有什么亮点。第二句话，请检查最终结果。"
            try check(secondFinal?.stages?.finalText == expected, "Bottom row contains both finalized sentences")
            let output = try await twoSentences.finish { twoSentences.markSessionEnded(); twoSentences.markStopReturned() }
            try check(output == expected && twoSentences.lastFallback == nil, "Both modes deliver all finals once")
        }
        print("PASS standard/Post two-row snapshots across a two-second pause")

        try check(AzureSpeechRefinement.configurationIssue(region: "swedencentral", language: "zh-CN") == nil, "Current configuration supported")
        try check(AzureSpeechRefinement.configurationIssue(region: "eastasia", language: "zh-CN") != nil, "Unsupported region rejected")
        try check(AzureSpeechRefinement.configurationIssue(region: "swedencentral", language: "zh-HK") != nil, "Unsupported locale rejected")
        try testHistoryMigration()
        try testHistoryMigration(hasPreviewColumn: true)
        print("PASS region/locale validation, history migration and restart round-trip")
        print("All Azure refinement regression checks passed.")
    }

    static func testHistoryMigration(hasPreviewColumn: Bool = false) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        var raw: OpaquePointer?
        try check(sqlite3_open(url.path, &raw) == SQLITE_OK, "Open fixture DB")
        let oldID = UUID().uuidString
        let oldSchema = """
        CREATE TABLE transcription_records (
          id TEXT PRIMARY KEY, created_at REAL NOT NULL, language TEXT NOT NULL,
          recording_duration_ms INTEGER NOT NULL, audio_file_path TEXT, stt_provider_id TEXT NOT NULL,
          stt_provider_name TEXT NOT NULL, original_text TEXT NOT NULL, transcription_duration_ms INTEGER NOT NULL,
          ai_provider_name TEXT, ai_model_name TEXT, polished_text TEXT, polish_duration_ms INTEGER);
        INSERT INTO transcription_records VALUES ('\(oldID)', 0, 'zh-CN', 1000, NULL, 'azure', 'Azure', '旧记录', 100, NULL, NULL, NULL, NULL);
        """
        try check(sqlite3_exec(raw, oldSchema, nil, nil, nil) == SQLITE_OK, "Create legacy fixture")
        if hasPreviewColumn {
            try check(sqlite3_exec(raw, "ALTER TABLE transcription_records ADD COLUMN streaming_preview_text TEXT;", nil, nil, nil) == SQLITE_OK,
                      "Create previous refinement-version fixture")
        }
        sqlite3_close(raw)
        var database: HistoryDatabase? = HistoryDatabase(databaseURL: url)
        let legacy = database!.fetchRecords().first!
        try check(legacy.originalText == "旧记录" && legacy.streamingPreviewText == nil && legacy.refinementFallbackReason == nil, "Keep legacy history unchanged")
        let record = TranscriptionRecord(id: UUID(), createdAt: Date(), language: "zh-CN", recordingDurationMs: 2000,
            audioFilePath: nil, sttProviderId: "azure", sttProviderName: "Azure Speech Service", originalText: "精修结果。",
            transcriptionDurationMs: 350, aiProviderName: "AI", aiModelName: "model", polishedText: "润色结果。", polishDurationMs: 100,
            streamingPreviewText: "中间预览")
        database!.insertRecord(record)
        database = nil
        let reopened = HistoryDatabase(databaseURL: url)
        let loaded = reopened.fetchRecords().first!
        try check(reopened.recordCount() == 2 && loaded.id == record.id, "Idempotent migration and persistence")
        try check(loaded.streamingPreviewText == "中间预览" && loaded.originalText == "精修结果。" && loaded.displayText == "润色结果。", "Three distinct stages preserved")
        try check(reopened.searchRecords(query: "精修").first?.streamingPreviewText == "中间预览", "Search retains comparison metadata")
        var fallbackRecord = record
        fallbackRecord.refinementFallbackReason = "Azure 未返回完整精修结果"
        reopened.deleteRecord(id: record.id)
        reopened.insertRecord(fallbackRecord)
        let fallbackLoaded = HistoryDatabase(databaseURL: url).fetchRecords().first!
        try check(fallbackLoaded.refinementFallbackReason == fallbackRecord.refinementFallbackReason, "Fallback marker survives database reopen")
    }
}
