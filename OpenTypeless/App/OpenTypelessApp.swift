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

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("========================================")
        print("[App] OpenTypeless starting...")
        print("========================================")

        setupMenuBar()
        requestPermissions()
        setupHotkeys()
        setupSpeechRecognition()
        observeSettingsChanges()

        print("[App] ✅ App initialization complete")
        print("========================================")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[App] Shutting down...")
        hotkeyManager.stopMonitoring()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        print("[App] Setting up menu bar...")

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
            print("[App] ✅ Menu bar icon created")
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

        print("[App] ✅ Menu bar setup complete")
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
        print("[App] Checking permissions...")

        // Request microphone permission
        print("[App] Requesting microphone permission...")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("[App] Microphone permission: \(granted ? "✅ granted" : "❌ denied")")
        }

        // Request speech recognition permission
        print("[App] Requesting speech recognition permission...")
        SFSpeechRecognizer.requestAuthorization { status in
            let statusStr: String
            switch status {
            case .authorized: statusStr = "✅ authorized"
            case .denied: statusStr = "❌ denied"
            case .restricted: statusStr = "⚠️ restricted"
            case .notDetermined: statusStr = "⏳ not determined"
            @unknown default: statusStr = "❓ unknown"
            }
            print("[App] Speech recognition permission: \(statusStr)")
        }

        // Check accessibility permission
        print("[App] Checking accessibility permission...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
            print("[App] Accessibility permission: \(accessibilityEnabled ? "✅ granted" : "❌ denied")")

            if !accessibilityEnabled {
                print("[App] ⚠️ Accessibility permission required for text insertion.")
                print("[App]    Please go to: System Settings → Privacy & Security → Accessibility")
                print("[App]    Then add this app or Xcode (if running from Xcode)")
            }
        }
    }

    // MARK: - Hotkey Setup

    private func setupHotkeys() {
        print("[App] Setting up hotkeys...")

        // Voice input: hold-to-talk
        hotkeyManager.onVoiceInputDown = { [weak self] in
            print("[App] Voice input shortcut pressed - starting voice input")
            self?.startVoiceInput()
        }

        hotkeyManager.onVoiceInputUp = { [weak self] in
            print("[App] Voice input shortcut released - stopping voice input")
            self?.stopVoiceInput()
        }

        // Hands-free mode: toggle
        hotkeyManager.onHandsFreeToggle = { [weak self] isActive in
            if isActive {
                print("[App] Hands-free mode ON")
                self?.startVoiceInput()
            } else {
                print("[App] Hands-free mode OFF")
                self?.stopVoiceInput()
            }
        }

        // Translate mode: single press
        hotkeyManager.onTranslate = {
            print("[App] Translate shortcut triggered")
            // TODO: Implement translate selected text
        }

        hotkeyManager.startMonitoring()
        print("[App] Hotkey setup complete")
    }

    // MARK: - Speech Recognition Setup

    private func setupSpeechRecognition() {
        print("[App] Setting up speech recognition...")

        // Get selected provider from settings
        let selectedProvider = UserDefaults.standard.string(forKey: "speechProvider") ?? "apple"
        print("[App] Selected speech provider: \(selectedProvider)")

        var didFallback = false
        var fallbackFrom = ""

        switch selectedProvider {
        case "azure":
            print("[App] Using Azure Speech Service")
            let azureProvider = AzureSpeechProvider()
            if azureProvider.isAvailable {
                speechProvider = azureProvider
            } else {
                print("[App] ⚠️ Azure Speech not configured, falling back to Apple Speech")
                speechProvider = AppleSpeechProvider()
                didFallback = true
                fallbackFrom = "Azure Speech Service"
            }
        case "whisper":
            print("[App] Using Azure OpenAI Whisper")
            let whisperProvider = WhisperSpeechProvider()
            if whisperProvider.isAvailable {
                speechProvider = whisperProvider
            } else {
                print("[App] Azure OpenAI Whisper not configured, falling back to Apple Speech")
                speechProvider = AppleSpeechProvider()
                didFallback = true
                fallbackFrom = "Azure OpenAI Whisper"
            }
        case "local-whisper":
            print("[App] Local Whisper not implemented yet, using Apple Speech")
            speechProvider = AppleSpeechProvider()
            didFallback = true
            fallbackFrom = "Local Whisper"
        default:
            print("[App] Using Apple Speech Framework")
            speechProvider = AppleSpeechProvider()
        }

        // Update floating panel with provider info
        floatingPanel.providerName = speechProvider?.name ?? "Unknown"
        if didFallback {
            floatingPanel.fallbackWarning = "\(fallbackFrom) 未配置，已回退到 Apple Speech"
        } else {
            floatingPanel.fallbackWarning = nil
        }

        speechProvider?.onPartialResult { [weak self] result in
            print("[App] Partial result: \(result.text)")
            self?.floatingPanel.updateTranscription(result.text)
        }

        speechProvider?.onError { error in
            print("[App] ❌ Speech recognition error: \(error.localizedDescription)")
        }

        // Setup AI provider
        aiProvider = AzureOpenAIProvider()
        let aiEnabled = UserDefaults.standard.bool(forKey: "aiPolishEnabled")
        print("[App] AI polish: \(aiEnabled ? "enabled" : "disabled")")

        print("[App] ✅ Speech recognition setup complete")
        print("[App] Active provider: \(speechProvider?.name ?? "unknown")")
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
            if current != self.speechProvider?.identifier {
                print("[App] Speech provider setting changed to: \(current), reinitializing...")
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
                print("[App] Shortcut settings changed, reloading hotkeys...")
                self.hotkeyManager.reloadShortcuts()
            }
        }
    }

    // MARK: - Voice Input

    private func startVoiceInput() {
        print("[App] Starting voice input...")

        // Clear any previous error/warning so it doesn't persist across attempts
        floatingPanel.fallbackWarning = nil

        recordingStartTime = Date()
        let language = UserDefaults.standard.string(forKey: "speechLanguage") ?? "zh-CN"

        // Begin audio capture synchronously BEFORE any UI work to minimize latency
        do {
            try speechProvider?.beginCapture(language: language)
        } catch {
            print("[App] ❌ Failed to begin capture: \(error)")
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
        floatingPanel.showPanel()

        // Complete async recognition setup
        Task {
            do {
                print("[App] Starting recognition with language: \(language)")
                try await speechProvider?.startRecognition(language: language)
                print("[App] ✅ Speech recognition started")
            } catch {
                print("[App] ❌ Failed to start speech recognition: \(error)")
                floatingPanel.showError(error.localizedDescription)
            }
        }
    }

    private func stopVoiceInput() {
        print("[App] Stopping voice input...")

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
        Task {
            // Skip transcription if recording is too short (< 1 second) to avoid accidental triggers
            if recordingDurationMs < 1000 {
                print("[App] ⚠️ Recording too short (\(recordingDurationMs)ms < 1000ms), skipping transcription")
                speechProvider?.cancelRecognition()
                floatingPanel.hidePanel()
                return
            }

            do {
                let sttStartTime = Date()
                var result = try await speechProvider?.stopRecognition() ?? ""
                let sttEndTime = Date()
                let transcriptionDurationMs = Int(sttEndTime.timeIntervalSince(sttStartTime) * 1000)

                print("[App] ✅ Final transcription: \(result) (STT: \(transcriptionDurationMs)ms)")

                if result.isEmpty {
                    print("[App] ⚠️ No transcription result")
                    floatingPanel.hidePanel()
                    return
                }

                let originalText = result
                let language = UserDefaults.standard.string(forKey: "speechLanguage") ?? "zh-CN"
                let sttProviderId = speechProvider?.identifier ?? "unknown"
                let sttProviderName = speechProvider?.name ?? "Unknown"
                let audioFilePath = speechProvider?.lastAudioFilePath

                // AI polish metadata
                var aiPolishResult: AIPolishResult?

                // Check if AI polish is enabled
                let aiEnabled = UserDefaults.standard.bool(forKey: "aiPolishEnabled")

                if aiEnabled {
                    print("[App] 🤖 AI polish enabled, processing...")
                    floatingPanel.updateTranscription("正在润色: \(result)")

                    // Reload AI provider config
                    aiProvider?.reloadConfig()

                    if let aiProvider = aiProvider, aiProvider.isAvailable {
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
                            print("[App] Using default system prompt (saved prompt was empty)")
                        }

                        do {
                            let polishResult = try await aiProvider.polishWithMetadata(text: result, systemPrompt: systemPrompt)
                            print("[App] ✅ AI polished: \(polishResult.text) (model: \(polishResult.modelName), \(polishResult.durationMs)ms)")
                            result = polishResult.text
                            aiPolishResult = polishResult
                        } catch {
                            print("[App] ❌ AI polish failed: \(error)")
                            // Continue with original text if AI fails
                        }
                    } else {
                        print("[App] ⚠️ AI provider not configured, using original text")
                    }
                }

                // Save history record
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
                    aiProviderName: aiPolishResult != nil ? aiProvider?.name : nil,
                    aiModelName: aiPolishResult?.modelName,
                    polishedText: aiPolishResult?.text,
                    polishDurationMs: aiPolishResult?.durationMs
                )
                await HistoryManager.shared.addRecord(record)

                floatingPanel.showResult(result)
                // Insert text at cursor position
                await insertText(result)

            } catch SpeechRecognitionError.rateLimited {
                print("[App] ⚠️ Whisper API rate limit reached (HTTP 429)")
                floatingPanel.fallbackWarning = "Whisper API 请求频率超限，请稍后再试"
                floatingPanel.showError("请求过于频繁，请稍等片刻后重试")
            } catch {
                print("[App] ❌ Failed to stop speech recognition: \(error)")
                floatingPanel.showError(error.localizedDescription)
            }
        }
    }

    // MARK: - Text Insertion

    @MainActor
    private func insertText(_ text: String) async {
        print("[App] Inserting text: \(text)")

        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            print("[App] ❌ Cannot insert text - accessibility permission not granted")
            return
        }

        // Use keyboard simulation to insert text
        print("[App] Simulating keyboard input...")

        // Copy text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V to paste
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: Cmd+V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        // Key up: Cmd+V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        print("[App] ✅ Text inserted via clipboard paste")
    }
}
