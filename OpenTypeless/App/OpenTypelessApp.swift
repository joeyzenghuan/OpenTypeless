import SwiftUI
import AVFoundation
import ApplicationServices
import Speech

@main
struct OpenTypelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible scene — the app is driven entirely by the menu bar icon
        // and a programmatically-managed NSWindow.
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?

    // Managers
    private let hotkeyManager = HotkeyManager.shared
    private let floatingPanel = FloatingPanelController.shared
    private var speechProvider: (any SpeechRecognitionProvider)?
    private var aiProvider: AzureOpenAIProvider?
    private var settingsObserver: NSObjectProtocol?

    // Timing for history records
    private var recordingStartTime: Date?

    /// Active AI task that can be cancelled from the close button
    private var activeAITask: Task<Void, Never>?
    private var recognitionStartTask: Task<Void, Error>?
    private var voiceSessionID: UUID?
    private var isStoppingVoiceInput = false
    private var voiceUsesPostRefinement = false

    private let log = Logger.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("========================================", tag: "App")
        log.info("OpenTypeless starting...", tag: "App")
        log.info("========================================", tag: "App")

        setupMenuBar()
        requestPermissions()
        setupHotkeys()
        setupSpeechRecognition()
        observeSettingsChanges()

        log.info("App initialization complete", tag: "App")
        log.info("========================================", tag: "App")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("Shutting down...", tag: "App")
        hotkeyManager.stopMonitoring()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        log.info("Setting up menu bar...", tag: "App")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use custom Westie dog icon
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                // Fallback to SF Symbol if custom icon not found
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "OpenTypeless")
            }
            button.action = #selector(toggleMainWindow)
            log.info("Menu bar icon created", tag: "App")
        }

        // Create the main window
        let hostingController = NSHostingController(rootView: MenuBarView())
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 700, height: 520))
        window.minSize = NSSize(width: 600, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "OpenTypeless"
        mainWindow = window

        log.info("Menu bar setup complete", tag: "App")
    }

    @objc private func toggleMainWindow() {
        guard let window = mainWindow else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            // Position the window below the menu bar icon
            if let button = statusItem.button, let buttonWindow = button.window {
                let buttonRect = button.convert(button.bounds, to: nil)
                let screenRect = buttonWindow.convertToScreen(buttonRect)
                let windowWidth = window.frame.width
                let x = screenRect.midX - windowWidth / 2
                let y = screenRect.minY - window.frame.height - 4
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - Permissions

    private func requestPermissions() {
        log.info("Checking permissions...", tag: "App")

        // Request microphone permission
        log.info("Requesting microphone permission...", tag: "App")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            self?.log.info("Microphone permission: \(granted ? "granted" : "denied")", tag: "App")
        }

        // Request speech recognition permission
        log.info("Requesting speech recognition permission...", tag: "App")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            let statusStr: String
            switch status {
            case .authorized: statusStr = "authorized"
            case .denied: statusStr = "denied"
            case .restricted: statusStr = "restricted"
            case .notDetermined: statusStr = "not determined"
            @unknown default: statusStr = "unknown"
            }
            self?.log.info("Speech recognition permission: \(statusStr)", tag: "App")
        }

        // Check accessibility permission
        log.info("Checking accessibility permission...", tag: "App")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            self?.log.info("Accessibility permission: \(accessibilityEnabled ? "granted" : "denied")", tag: "App")

            if !accessibilityEnabled {
                self?.log.info("Accessibility permission required for text insertion. Go to: System Settings > Privacy & Security > Accessibility", tag: "App")
            }
        }
    }

    // MARK: - Hotkey Setup

    private func setupHotkeys() {
        log.info("Setting up hotkeys...", tag: "App")

        // Voice input: hold-to-talk
        hotkeyManager.onVoiceInputDown = { [weak self] in
            self?.log.info("Voice input shortcut pressed - starting voice input", tag: "App")
            self?.startVoiceInput()
        }

        hotkeyManager.onVoiceInputUp = { [weak self] in
            self?.log.info("Voice input shortcut released - stopping voice input", tag: "App")
            self?.stopVoiceInput()
        }

        // Hands-free mode: toggle
        hotkeyManager.onHandsFreeToggle = { [weak self] isActive in
            if isActive {
                self?.log.info("Hands-free mode ON", tag: "App")
                self?.startVoiceInput()
            } else {
                self?.log.info("Hands-free mode OFF", tag: "App")
                self?.stopVoiceInput()
            }
        }

        // Translate mode: single press
        hotkeyManager.onTranslate = { [weak self] in
            self?.log.info("Translate shortcut triggered", tag: "App")
            // TODO: Implement translate selected text
        }

        hotkeyManager.startMonitoring()
        log.info("Hotkey setup complete", tag: "App")
    }

    // MARK: - Speech Recognition Setup

    private func setupSpeechRecognition() {
        log.info("Setting up speech recognition...", tag: "App")

        // Get selected provider from settings
        let selectedProvider = UserDefaults.standard.string(forKey: "speechProvider") ?? "apple"
        log.info("Selected speech provider: \(selectedProvider)", tag: "App")

        var didFallback = false
        var fallbackFrom = ""

        switch selectedProvider {
        case "azure":
            log.info("Using Azure Speech Service", tag: "App")
            let azureProvider = AzureSpeechProvider()
            // An explicitly requested refined result must not silently fall back to Apple.
            if azureProvider.isAvailable || azureProvider.usesPostStreamRefinement {
                speechProvider = azureProvider
            } else {
                log.info("Azure Speech not configured, falling back to Apple Speech", tag: "App")
                speechProvider = AppleSpeechProvider()
                didFallback = true
                fallbackFrom = "Azure Speech Service"
            }
        case "whisper":
            log.info("Using Azure OpenAI Whisper", tag: "App")
            let whisperProvider = WhisperSpeechProvider()
            if whisperProvider.isAvailable {
                speechProvider = whisperProvider
            } else {
                log.info("Azure OpenAI Whisper not configured, falling back to Apple Speech", tag: "App")
                speechProvider = AppleSpeechProvider()
                didFallback = true
                fallbackFrom = "Azure OpenAI Whisper"
            }
        case "gpt4o-transcribe":
            log.info("Using GPT-4o Transcribe", tag: "App")
            let provider = GPT4oTranscribeSpeechProvider()
            if provider.isAvailable {
                speechProvider = provider
            } else {
                log.info("GPT-4o Transcribe not configured, falling back to Apple Speech", tag: "App")
                speechProvider = AppleSpeechProvider()
                didFallback = true
                fallbackFrom = "GPT-4o Transcribe"
            }
        case "gpt-realtime-whisper":
            log.info("Using GPT Realtime Whisper", tag: "App")
            let provider = GPTRealtimeWhisperSpeechProvider()
            if provider.isAvailable {
                speechProvider = provider
            } else {
                log.info("GPT Realtime Whisper not configured, falling back to Apple Speech", tag: "App")
                speechProvider = AppleSpeechProvider()
                didFallback = true
                fallbackFrom = "GPT Realtime Whisper"
            }
        default:
            log.info("Using Apple Speech Framework", tag: "App")
            speechProvider = AppleSpeechProvider()
        }

        // Update floating panel with provider info
        floatingPanel.providerName = speechProvider?.name ?? "Unknown"
        if didFallback {
            floatingPanel.fallbackWarning = "\(fallbackFrom) 未配置，已回退到 Apple Speech"
        } else {
            floatingPanel.fallbackWarning = nil
        }

        // Setup AI provider
        aiProvider = AzureOpenAIProvider()
        let aiEnabled = UserDefaults.standard.bool(forKey: "aiPolishEnabled")
        log.info("AI polish: \(aiEnabled ? "enabled" : "disabled")", tag: "App")

        log.info("Speech recognition setup complete", tag: "App")
        log.info("Active provider: \(speechProvider?.name ?? "unknown")", tag: "App")
    }

    // MARK: - Settings Observer

    private var lastKnownShortcuts: (String, String, String) = ("", "", "")

    private func observeSettingsChanges() {
        // Capture initial shortcut values for change detection
        lastKnownShortcuts = (
            UserDefaults.standard.string(forKey: "shortcutVoiceInput") ?? "",
            UserDefaults.standard.string(forKey: "shortcutHandsFree") ?? "",
            UserDefaults.standard.string(forKey: "shortcutTranslate") ?? ""
        )

        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Check for speech provider changes
            let current = UserDefaults.standard.string(forKey: "speechProvider") ?? "apple"
            if self.voiceSessionID == nil, current != self.speechProvider?.identifier {
                self.log.info("Speech provider setting changed to: \(current), reinitializing...", tag: "App")
                self.setupSpeechRecognition()
            }

            // Check for shortcut changes
            let newShortcuts = (
                UserDefaults.standard.string(forKey: "shortcutVoiceInput") ?? "",
                UserDefaults.standard.string(forKey: "shortcutHandsFree") ?? "",
                UserDefaults.standard.string(forKey: "shortcutTranslate") ?? ""
            )
            if newShortcuts != self.lastKnownShortcuts {
                self.lastKnownShortcuts = newShortcuts
                self.log.info("Shortcut settings changed, reloading hotkeys...", tag: "App")
                self.hotkeyManager.reloadShortcuts()
            }
        }
    }

    // MARK: - Voice Input

    private func startVoiceInput() {
        log.info("Starting voice input...", tag: "App")

        // Keep one provider/session until its final result has been delivered.
        guard voiceSessionID == nil else { return }
        setupSpeechRecognition()
        guard let provider = speechProvider else { return }
        let sessionID = UUID()
        voiceSessionID = sessionID
        isStoppingVoiceInput = false
        voiceUsesPostRefinement = provider.usesPostStreamRefinement
        configureSpeechCallbacks(provider, sessionID: sessionID)
        floatingPanel.onCancel = { [weak self] in self?.cancelVoiceInput() }

        recordingStartTime = Date()
        let language = UserDefaults.standard.string(forKey: "speechLanguage") ?? "zh-CN"

        // Begin audio capture synchronously BEFORE any UI work to minimize latency
        do {
            try provider.beginCapture(language: language)
        } catch {
            log.info("Failed to begin capture: \(error)", tag: "App")
            cancelVoiceInput()
            floatingPanel.showPanel(refinementEnabled: provider.usesPostStreamRefinement, showsRecognitionStages: provider.supportsRecognitionStages)
            floatingPanel.showError(error.localizedDescription)
            return
        }

        // Update menu bar icon (tint red when recording)
        DispatchQueue.main.async {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                self.statusItem.button?.image = image
            }
            self.statusItem.button?.contentTintColor = .red
        }

        // Show floating panel
        floatingPanel.showPanel(refinementEnabled: provider.usesPostStreamRefinement, showsRecognitionStages: provider.supportsRecognitionStages)

        let startTask = Task { try await provider.startRecognition(language: language) }
        recognitionStartTask = startTask
        Task {
            do {
                try await startTask.value
            } catch {
                guard self.voiceSessionID == sessionID else { return }
                self.cancelVoiceInput()
                self.floatingPanel.showPanel(refinementEnabled: provider.usesPostStreamRefinement, showsRecognitionStages: provider.supportsRecognitionStages)
                self.floatingPanel.showError(error.localizedDescription)
            }
        }
    }

    private func stopVoiceInput() {
        log.info("Stopping voice input...", tag: "App")

        guard let sessionID = voiceSessionID, let provider = speechProvider,
              !isStoppingVoiceInput else { return }
        isStoppingVoiceInput = true
        let startTask = recognitionStartTask
        let refinementEnabled = voiceUsesPostRefinement
        let recordingEndTime = Date()
        let recordingDurationMs = Int((recordingEndTime.timeIntervalSince(recordingStartTime ?? recordingEndTime)) * 1000)

        // Reset menu bar icon
        DispatchQueue.main.async {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                self.statusItem.button?.image = image
            }
            self.statusItem.button?.contentTintColor = nil
        }

        // Stop speech recognition and get result
        activeAITask = Task { [weak self] in
            guard let self = self else { return }
            defer {
                if self.voiceSessionID == sessionID {
                    self.voiceSessionID = nil
                    self.recognitionStartTask = nil
                    self.activeAITask = nil
                    self.isStoppingVoiceInput = false
                }
            }

            // Skip transcription if recording is too short (< 1 second) to avoid accidental triggers
            if recordingDurationMs < 1000 {
                self.log.info("Recording too short (\(recordingDurationMs)ms < 1000ms), skipping transcription", tag: "App")
                startTask?.cancel()
                provider.cancelRecognition()
                self.floatingPanel.hidePanel()
                return
            }

            do {
                self.floatingPanel.showProcessing(
                    originalText: self.floatingPanel.transcription,
                    statusMessage: refinementEnabled ? "正在等待最终精修..." : "正在等待最终识别结果..."
                )
                try await startTask?.value
                try Task.checkCancellation()
                let sttStartTime = Date()
                var result = try await provider.stopRecognition()
                let refinementFallback = provider.lastRefinementFallback
                try Task.checkCancellation()
                guard self.voiceSessionID == sessionID else { return }
                let sttEndTime = Date()
                let transcriptionDurationMs = Int(sttEndTime.timeIntervalSince(sttStartTime) * 1000)

                self.log.info("Transcription output (fallback=\(refinementFallback != nil)): \(result) (STT: \(transcriptionDurationMs)ms)", tag: "App")

                if result.isEmpty {
                    self.log.info("No transcription result", tag: "App")
                    self.floatingPanel.hidePanel()
                    return
                }

                let originalText = result
                let language = UserDefaults.standard.string(forKey: "speechLanguage") ?? "zh-CN"
                let sttProviderId = provider.identifier
                let sttProviderName = provider.name
                let audioFilePath = provider.lastAudioFilePath

                // AI polish metadata
                var aiPolishResult: AIPolishResult?

                // Check if AI polish is enabled
                let aiEnabled = UserDefaults.standard.bool(forKey: "aiPolishEnabled")

                // Recover immediately; a failed refinement must not trigger another model wait.
                if aiEnabled, refinementFallback == nil {
                    if provider.supportsRecognitionStages { self.floatingPanel.showRecognizedResult(result) }
                    self.log.info("AI polish enabled, processing...", tag: "App")
                    self.floatingPanel.showProcessing(originalText: result, statusMessage: "正在 AI 润色...")

                    // Reload AI provider config
                    self.aiProvider?.reloadConfig()

                    if let aiProvider = self.aiProvider, aiProvider.isAvailable {
                        // Get system prompt, use default if empty
                        var systemPrompt = UserDefaults.standard.string(forKey: "aiSystemPrompt") ?? ""
                        if systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            systemPrompt = """
你是一个语音转文字的后处理工具。你的唯一任务是修正和润色语音识别的原始输出。

规则：
1. 修正错别字和语音识别错误
2. 添加必要的标点符号，换行，分条列点。
3. 不要回复、不要对话、不要解释
4. 删除无效和重复的话，不要添加任何额外内容
5. 直接输出修正后的原文，无任何前缀
6. 与输入保持相同的语言。

示例：
输入：你好，你好，那什么今天你吃饭了没
输出：你好，今天你吃饭了没？

输入：你今天记得干两件事，一件是去超市买菜，另一个是去练习打球
输出：你今天记得干两件事
1. 去超市买菜
2. 练习打球

输入：GPT纹身图模型
输出：GPT文生图模型
"""
                            self.log.info("Using default system prompt (saved prompt was empty)", tag: "App")
                        }

                        do {
                            // Check for cancellation before making API call
                            try Task.checkCancellation()

                            let polishResult = try await aiProvider.polishWithMetadata(text: result, systemPrompt: systemPrompt)
                            self.log.info("AI polished: \(polishResult.text) (model: \(polishResult.modelName), \(polishResult.durationMs)ms)", tag: "App")
                            result = polishResult.text
                            aiPolishResult = polishResult
                        } catch is CancellationError {
                            guard self.voiceSessionID == sessionID else { return }
                            self.log.info("AI polish cancelled by user", tag: "App")
                            self.floatingPanel.hidePanel()
                            return
                        } catch {
                            self.log.info("AI polish failed: \(error)", tag: "App")
                            // Continue with original text if AI fails
                        }
                    } else {
                        self.log.info("AI provider not configured, using original text", tag: "App")
                    }
                }

                // Check for cancellation before inserting text
                guard !Task.isCancelled else {
                    guard self.voiceSessionID == sessionID else { return }
                    self.log.info("Task cancelled, skipping text insertion", tag: "App")
                    self.floatingPanel.hidePanel()
                    return
                }

                // Deliver the complete output before UI presentation or database work.
                // The panel's display timer must never delay the paste event.
                let finalText = result
                let delivered = await MainActor.run { () -> Bool in
                    guard !Task.isCancelled, self.voiceSessionID == sessionID else { return false }
                    let insertion = self.insertText(finalText)
                    if insertion == .failed {
                        self.floatingPanel.showError("无法写入剪贴板，请从历史记录复制")
                    } else {
                        if provider.supportsRecognitionStages, refinementFallback == nil { self.floatingPanel.showRecognizedResult(originalText) }
                        self.floatingPanel.showResult(finalText, fallback: refinementFallback, copiedOnly: insertion == .copiedOnly)
                    }
                    return true
                }
                guard delivered else { return }

                // Persist after delivery so loading/writing history cannot hold up typing.
                let record = TranscriptionRecord(
                    id: UUID(),
                    createdAt: Date(),
                    language: language,
                    recordingDurationMs: recordingDurationMs,
                    audioFilePath: audioFilePath,
                    sttProviderId: sttProviderId,
                    sttProviderName: sttProviderName,
                    originalText: originalText,
                    transcriptionDurationMs: transcriptionDurationMs,
                    aiProviderName: aiPolishResult != nil ? self.aiProvider?.name : nil,
                    aiModelName: aiPolishResult?.modelName,
                    polishedText: aiPolishResult?.text,
                    polishDurationMs: aiPolishResult?.durationMs,
                    streamingPreviewText: provider.lastRefinementPreview,
                    refinementFallbackReason: refinementFallback?.reason
                )
                await HistoryManager.shared.addRecord(record)

            } catch is CancellationError {
                guard self.voiceSessionID == sessionID else { return }
                self.log.info("Voice input task cancelled", tag: "App")
                self.floatingPanel.hidePanel()
            } catch SpeechRecognitionError.rateLimited {
                guard self.voiceSessionID == sessionID else { return }
                self.log.info("Whisper API rate limit reached (HTTP 429)", tag: "App")
                self.floatingPanel.fallbackWarning = "Whisper API 请求频率超限，请稍后再试"
                self.floatingPanel.showError("请求过于频繁，请稍等片刻后重试")
            } catch {
                guard self.voiceSessionID == sessionID else { return }
                self.log.info("Failed to stop speech recognition: \(error)", tag: "App")
                self.floatingPanel.showError(error.localizedDescription)
            }
        }

    }

    private func configureSpeechCallbacks(_ provider: any SpeechRecognitionProvider, sessionID: UUID) {
        provider.onPartialResult { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.voiceSessionID == sessionID else { return }
                self.floatingPanel.updateTranscription(result)
            }
        }
        provider.onError { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.voiceSessionID == sessionID else { return }
                self.floatingPanel.showError(error.localizedDescription)
            }
        }
        provider.onStatus { [weak self] message in
            DispatchQueue.main.async {
                guard let self, self.voiceSessionID == sessionID else { return }
                // A late connection event must not restore the recording status after release.
                if !self.isStoppingVoiceInput { self.floatingPanel.showStatus(message) }
            }
        }
    }

    private func cancelVoiceInput() {
        activeAITask?.cancel()
        recognitionStartTask?.cancel()
        speechProvider?.cancelRecognition()
        voiceSessionID = nil
        isStoppingVoiceInput = false
        recognitionStartTask = nil
        activeAITask = nil
        floatingPanel.hidePanel()
        statusItem.button?.contentTintColor = nil
    }

    // MARK: - Text Insertion

    private enum TextInsertionOutcome { case pasteRequested, copiedOnly, failed }

    @MainActor
    private func insertText(_ text: String) -> TextInsertionOutcome {
        guard !Task.isCancelled, !text.isEmpty else { return .failed }
        log.debug("Inserting recognition output", tag: "App")

        // Keep usable text on the clipboard even if macOS currently blocks automatic paste.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            log.info("Cannot write recognition output to clipboard", tag: "App")
            return .failed
        }

        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            log.info("Output copied; automatic paste blocked by accessibility permission", tag: "App")
            return .copiedOnly
        }

        // Use keyboard simulation to insert text
        log.debug("Simulating keyboard input...", tag: "App")

        // Simulate Cmd+V to paste
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: Cmd+V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return .copiedOnly
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        log.info("Clipboard paste requested", tag: "App")
        return .pasteRequested
    }
}
