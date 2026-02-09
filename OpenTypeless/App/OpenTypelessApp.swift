import SwiftUI
import AVFoundation
import ApplicationServices
import Speech

@main
struct OpenTypelessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // Managers
    private let hotkeyManager = HotkeyManager.shared
    private let floatingPanel = FloatingPanelController.shared
    private var speechProvider: AppleSpeechProvider?
    private var aiProvider: AzureOpenAIProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("========================================")
        print("[App] OpenTypeless starting...")
        print("========================================")

        setupMenuBar()
        requestPermissions()
        setupHotkeys()
        setupSpeechRecognition()

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
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "OpenTypeless")
            button.action = #selector(togglePopover)
            print("[App] ✅ Menu bar icon created")
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())

        print("[App] ✅ Menu bar setup complete")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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

        hotkeyManager.onFnKeyDown = { [weak self] in
            print("[App] 🎤 fn key pressed - starting voice input")
            self?.startVoiceInput()
        }

        hotkeyManager.onFnKeyUp = { [weak self] in
            print("[App] 🛑 fn key released - stopping voice input")
            self?.stopVoiceInput()
        }

        hotkeyManager.startMonitoring()
        print("[App] ✅ Hotkey setup complete - Press and hold fn key to start voice input")
    }

    // MARK: - Speech Recognition Setup

    private func setupSpeechRecognition() {
        print("[App] Setting up speech recognition...")
        print("[App] Using Apple Speech Framework")

        speechProvider = AppleSpeechProvider()

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
    }

    // MARK: - Voice Input

    private func startVoiceInput() {
        print("[App] Starting voice input...")

        // Update menu bar icon
        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            self.statusItem.button?.contentTintColor = .red
        }

        // Show floating panel
        floatingPanel.showPanel()

        // Start speech recognition
        Task {
            do {
                let language = UserDefaults.standard.string(forKey: "speechLanguage") ?? "zh-CN"
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

        // Reset menu bar icon
        DispatchQueue.main.async {
            self.statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "OpenTypeless")
            self.statusItem.button?.contentTintColor = nil
        }

        // Stop speech recognition and get result
        Task {
            do {
                var result = try await speechProvider?.stopRecognition() ?? ""
                print("[App] ✅ Final transcription: \(result)")

                if result.isEmpty {
                    print("[App] ⚠️ No transcription result")
                    floatingPanel.hidePanel()
                    return
                }

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
1. 只修正错别字和语音识别错误
2. 只添加必要的标点符号
3. 不要回复、不要对话、不要解释
4. 不要添加任何额外内容
5. 直接输出修正后的原文，无任何前缀

示例：
输入：你好你吃饭了没
输出：你好，你吃饭了没？

输入：今天天气挺好的我们去公园玩吧
输出：今天天气挺好的，我们去公园玩吧。
"""
                            print("[App] Using default system prompt (saved prompt was empty)")
                        }

                        do {
                            let polishedText = try await aiProvider.polish(text: result, systemPrompt: systemPrompt)
                            print("[App] ✅ AI polished: \(polishedText)")
                            result = polishedText
                        } catch {
                            print("[App] ❌ AI polish failed: \(error)")
                            // Continue with original text if AI fails
                        }
                    } else {
                        print("[App] ⚠️ AI provider not configured, using original text")
                    }
                }

                floatingPanel.showResult(result)
                // Insert text at cursor position
                await insertText(result)

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
