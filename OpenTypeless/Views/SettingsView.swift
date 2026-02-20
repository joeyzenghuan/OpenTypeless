import SwiftUI

// MARK: - Settings Tab View (embedded in main window sidebar)

struct SettingsTabView: View {
    var body: some View {
        TabView {
            SpeechProviderSettingsView()
                .tabItem {
                    Label("语音转文本", systemImage: "mic")
                }

            AIProviderSettingsView()
                .tabItem {
                    Label("AI 润色", systemImage: "brain")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Keep SettingsView for backward compatibility / preview
struct SettingsView: View {
    var body: some View {
        SettingsTabView()
            .frame(width: 550, height: 500)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "zh-Hans"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("apiTimeout") private var apiTimeout: Double = 10.0
    @AppStorage("logLevel") private var logLevel = "off"
    @State private var showingLogViewer = false

    var body: some View {
        Form {
            Section {
                Picker("界面语言", selection: $interfaceLanguage) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }

                Toggle("登录时启动", isOn: $launchAtLogin)
                Toggle("在 Dock 中显示", isOn: $showInDock)
            }

            Section {
                HStack {
                    Text("历史记录保存时长")
                    Spacer()
                    Picker("", selection: .constant("forever")) {
                        Text("永久").tag("forever")
                        Text("30 天").tag("30days")
                        Text("7 天").tag("7days")
                    }
                    .frame(width: 120)
                }
            }

            Section("API 设置") {
                HStack {
                    Text("模型请求超时")
                    Spacer()
                    TextField("", value: $apiTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("秒")
                        .foregroundColor(.secondary)
                }
                Text("默认 10 秒。如果模型响应较慢可适当增大此值。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("日志") {
                Picker("日志级别", selection: $logLevel) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }

                Text("Info: 记录关键操作事件。Debug: 记录所有详细信息，包括请求/响应内容。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("查看日志") {
                        showingLogViewer = true
                    }

                    Button("打开日志文件夹") {
                        NSWorkspace.shared.open(Logger.shared.logDirectory)
                    }

                    Spacer()

                    Button("清除日志") {
                        Logger.shared.clearLogs()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showingLogViewer) {
            LogViewerView()
        }
    }
}

// MARK: - Log Viewer

struct LogViewerView: View {
    @State private var logFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var logContent: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("应用日志")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding()

            Divider()

            HSplitView {
                // File list
                List(logFiles, id: \.absoluteString, selection: $selectedFile) { file in
                    Text(file.lastPathComponent)
                        .font(.system(size: 12, design: .monospaced))
                }
                .frame(minWidth: 180, maxWidth: 200)
                .onChange(of: selectedFile) { newValue in
                    if let url = newValue {
                        logContent = Logger.shared.readLogFile(at: url)
                    }
                }

                // Log content
                ScrollView {
                    Text(logContent)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(minWidth: 400)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(width: 700, height: 500)
        .onAppear {
            logFiles = Logger.shared.getLogFiles()
            if let first = logFiles.first {
                selectedFile = first
                logContent = Logger.shared.readLogFile(at: first)
            }
        }
    }
}

// MARK: - Speech Provider Settings

struct SpeechProviderSettingsView: View {
    @AppStorage("speechProvider") private var speechProvider = "apple"
    @AppStorage("azureSpeechKey") private var azureSpeechKey = ""
    @AppStorage("azureSpeechRegion") private var azureSpeechRegion = "swedencentral"
    @AppStorage("whisperEndpoint") private var whisperEndpoint = ""
    @AppStorage("whisperDeployment") private var whisperDeployment = "whisper"
    @AppStorage("whisperAPIKey") private var whisperAPIKey = ""
    @AppStorage("gpt4oTranscribeEndpoint") private var gpt4oTranscribeEndpoint = ""
    @AppStorage("gpt4oTranscribeDeployment") private var gpt4oTranscribeDeployment = "gpt-4o-transcribe"
    @AppStorage("gpt4oTranscribeAPIKey") private var gpt4oTranscribeAPIKey = ""
    @AppStorage("gpt4oTranscribeTemperature") private var gpt4oTranscribeTemperature: Double = 0
    @AppStorage("gpt4oTranscribePrompt") private var gpt4oTranscribePrompt = ""
    @AppStorage("gpt4oTranscribeLogprobs") private var gpt4oTranscribeLogprobs = false
    @AppStorage("gpt4oTranscribeLanguage") private var gpt4oTranscribeLanguage = ""

    var body: some View {
        Form {
            Section("语音转文本服务") {
                Picker("提供商", selection: $speechProvider) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text("GPT-4o Transcribe (推荐)")
                    }.tag("gpt4o-transcribe")

                    HStack {
                        Image(systemName: "cloud")
                        Text("Azure Speech Service")
                    }.tag("azure")

                    HStack {
                        Image(systemName: "waveform")
                        Text("Azure OpenAI Whisper")
                    }.tag("whisper")

                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Apple Speech (本地)")
                    }.tag("apple")
                }
                .pickerStyle(.radioGroup)

                // Provider descriptions
                switch speechProvider {
                case "apple":
                    ProviderInfoBox(
                        icon: "checkmark.shield",
                        title: "Apple Speech Framework",
                        description: "免费、离线、隐私友好。使用系统内置语音识别，无需网络连接。",
                        color: .green
                    )
                case "azure":
                    ProviderInfoBox(
                        icon: "cloud",
                        title: "Azure Speech Service",
                        description: "高精度、实时流式、支持 100+ 语言和方言。需要 Azure 订阅。",
                        color: .blue
                    )
                case "whisper":
                    ProviderInfoBox(
                        icon: "waveform",
                        title: "Azure OpenAI Whisper",
                        description: "高精度多语言识别。录音结束后发送完整音频进行转写，非实时流式。需要 Azure OpenAI 资源并部署 Whisper 模型。",
                        color: .purple
                    )
                case "gpt4o-transcribe":
                    ProviderInfoBox(
                        icon: "brain.head.profile",
                        title: "GPT-4o Transcribe",
                        description: "比 Whisper 更高精度的转写模型。支持可选的置信度评分（logprobs）和提示词引导。需要 Azure OpenAI 资源并部署 gpt-4o-transcribe 模型。",
                        color: .indigo
                    )
                default:
                    EmptyView()
                }
            }

            // Azure Settings
            if speechProvider == "azure" {
                Section("Azure Speech Service 设置") {
                    SecureField("API Key", text: $azureSpeechKey)
                    TextField("Region", text: $azureSpeechRegion)
                        .textFieldStyle(.roundedBorder)

                    Link("获取 Azure Speech API Key",
                         destination: URL(string: "https://azure.microsoft.com/products/cognitive-services/speech-services")!)
                        .font(.caption)
                }
            }

            // Whisper API Settings
            if speechProvider == "whisper" {
                Section("Azure OpenAI Whisper 设置") {
                    TextField("Endpoint URL", text: $whisperEndpoint)
                        .textFieldStyle(.roundedBorder)

                    Text("例如: https://your-resource.openai.azure.com")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Deployment Name", text: $whisperDeployment)
                        .textFieldStyle(.roundedBorder)

                    Text("Whisper 模型的部署名称，例如: whisper")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("API Key", text: $whisperAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Link("Azure OpenAI Whisper 文档",
                         destination: URL(string: "https://learn.microsoft.com/azure/ai-services/openai/whisper-quickstart")!)
                        .font(.caption)
                }
            }

            // GPT-4o Transcribe Settings
            if speechProvider == "gpt4o-transcribe" {
                Section("GPT-4o Transcribe 设置") {
                    TextField("Endpoint URL", text: $gpt4oTranscribeEndpoint)
                        .textFieldStyle(.roundedBorder)

                    Text("例如: https://your-resource.openai.azure.com")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Deployment Name", text: $gpt4oTranscribeDeployment)
                        .textFieldStyle(.roundedBorder)

                    Text("GPT-4o Transcribe 模型的部署名称，例如: gpt-4o-transcribe")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("API Key", text: $gpt4oTranscribeAPIKey)
                        .textFieldStyle(.roundedBorder)

                    // Language override
                    Picker("Language", selection: $gpt4oTranscribeLanguage) {
                        Text("跟随全局设置").tag("")
                        ForEach(SupportedLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }

                    Text("可选。不设置时使用全局语音语言设置。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Temperature slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", gpt4oTranscribeTemperature))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $gpt4oTranscribeTemperature, in: 0...1, step: 0.05)
                    }

                    Text("控制转写的随机性。0 表示确定性输出，较高值增加多样性。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Transcription prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("转写提示词 (Prompt)")
                        TextEditor(text: $gpt4oTranscribePrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 60)
                            .border(Color.gray.opacity(0.3))
                    }

                    Text("可选提示词，用于引导模型的转写风格或术语。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Logprobs toggle
                    Toggle("启用置信度评分 (Logprobs)", isOn: $gpt4oTranscribeLogprobs)

                    Text("启用后，API 返回每个 token 的置信度评分，日志中可查看平均置信度。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("Azure OpenAI 文档",
                         destination: URL(string: "https://learn.microsoft.com/azure/ai-services/openai/whisper-quickstart")!)
                        .font(.caption)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ProviderInfoBox: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - AI Provider Settings

struct AIProviderSettingsView: View {
    @AppStorage("aiPolishEnabled") private var aiPolishEnabled = false
    @AppStorage("aiProvider") private var aiProvider = "azure-openai"

    // Azure OpenAI settings
    @AppStorage("azureOpenAIEndpoint") private var azureOpenAIEndpoint = ""
    @AppStorage("azureOpenAIDeployment") private var azureOpenAIDeployment = ""
    @AppStorage("azureOpenAIKey") private var azureOpenAIKey = ""
    @AppStorage("azureOpenAIVersion") private var azureOpenAIVersion = "2024-02-15-preview"
    @AppStorage("azureOpenAIAPIType") private var azureOpenAIAPIType = "chat-completions"

    // System Prompt
    @AppStorage("aiSystemPrompt") private var aiSystemPrompt = """
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

    // Other providers
    @AppStorage("openaiAPIKey") private var openaiAPIKey = ""
    @AppStorage("claudeAPIKey") private var claudeAPIKey = ""
    @AppStorage("ollamaEndpoint") private var ollamaEndpoint = "http://localhost:11434"

    var body: some View {
        Form {
            // Enable/Disable AI Polish
            Section {
                Toggle("启用 AI 润色", isOn: $aiPolishEnabled)

                if aiPolishEnabled {
                    Text("语音识别后，AI 将自动优化文字")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if aiPolishEnabled {
                // Provider Selection
                Section("AI 服务提供商") {
                    Picker("提供商", selection: $aiProvider) {
                        Text("Azure OpenAI").tag("azure-openai")
                        Text("OpenAI (GPT-4)").tag("openai")
                        Text("Anthropic (Claude)").tag("claude")
                        Text("本地 LLM (Ollama)").tag("ollama")
                    }
                    .pickerStyle(.radioGroup)
                }

                // Azure OpenAI Settings
                if aiProvider == "azure-openai" {
                    Section("Azure OpenAI 设置") {
                        // API Type Selection
                        Picker("API 类型", selection: $azureOpenAIAPIType) {
                            Text("Chat Completions API").tag("chat-completions")
                            Text("Responses API").tag("responses")
                        }
                        .pickerStyle(.segmented)

                        if azureOpenAIAPIType == "chat-completions" {
                            Text("传统的对话补全 API，兼容性好")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("新一代 API，支持更多功能（需要 2025-04-01-preview 或更新版本）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        TextField("Endpoint URL", text: $azureOpenAIEndpoint)
                            .textFieldStyle(.roundedBorder)

                        Text("例如: https://your-resource.openai.azure.com")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Deployment / Model Name", text: $azureOpenAIDeployment)
                            .textFieldStyle(.roundedBorder)

                        Text("例如: gpt-4o, gpt-4.1")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SecureField("API Key", text: $azureOpenAIKey)
                            .textFieldStyle(.roundedBorder)

                        if azureOpenAIAPIType == "chat-completions" {
                            TextField("API Version", text: $azureOpenAIVersion)
                                .textFieldStyle(.roundedBorder)
                        }

                        Link("Azure OpenAI 文档",
                             destination: URL(string: "https://learn.microsoft.com/azure/ai-services/openai/")!)
                            .font(.caption)
                    }
                }

                // OpenAI Settings
                if aiProvider == "openai" {
                    Section("OpenAI 设置") {
                        SecureField("API Key", text: $openaiAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Link("获取 API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                }

                // Claude Settings
                if aiProvider == "claude" {
                    Section("Anthropic 设置") {
                        SecureField("API Key", text: $claudeAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Link("获取 API Key", destination: URL(string: "https://console.anthropic.com/")!)
                            .font(.caption)
                    }
                }

                // Ollama Settings
                if aiProvider == "ollama" {
                    Section("Ollama 设置") {
                        TextField("Endpoint", text: $ollamaEndpoint)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Text("模型")
                            Spacer()
                            Picker("", selection: .constant("llama3")) {
                                Text("Llama 3").tag("llama3")
                                Text("Mistral").tag("mistral")
                                Text("Qwen").tag("qwen")
                            }
                            .frame(width: 120)
                        }
                    }
                }

                // System Prompt
                Section("润色提示词 (System Prompt)") {
                    TextEditor(text: $aiSystemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 120)
                        .border(Color.gray.opacity(0.3))

                    Button("恢复默认提示词") {
                        aiSystemPrompt = """
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
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcut Settings

struct ShortcutSettingsView: View {
    @AppStorage("shortcutVoiceInput") private var shortcutVoiceInput: String = ""
    @AppStorage("shortcutHandsFree") private var shortcutHandsFree: String = ""
    @AppStorage("shortcutTranslate") private var shortcutTranslate: String = ""

    var body: some View {
        Form {
            Section("键盘快捷键") {
                ShortcutRow(
                    title: "语音输入",
                    subtitle: "按住说话，释放后插入文本",
                    defaultCombo: .defaultVoiceInput,
                    storageKey: "shortcutVoiceInput",
                    storedValue: $shortcutVoiceInput
                )

                ShortcutRow(
                    title: "免提模式",
                    subtitle: "按一次开始，再按一次停止",
                    defaultCombo: .defaultHandsFree,
                    storageKey: "shortcutHandsFree",
                    storedValue: $shortcutHandsFree
                )

                ShortcutRow(
                    title: "翻译模式",
                    subtitle: "翻译选中的文本",
                    defaultCombo: .defaultTranslate,
                    storageKey: "shortcutTranslate",
                    storedValue: $shortcutTranslate
                )
            }

            Section {
                HStack {
                    Spacer()
                    Button("恢复默认快捷键") {
                        shortcutVoiceInput = ""
                        shortcutHandsFree = ""
                        shortcutTranslate = ""
                        HotkeyManager.shared.reloadShortcuts()
                    }
                    .font(.caption)
                    Spacer()
                }
            }

            Section("说明") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("点击快捷键区域，然后按下想要的按键组合即可设置。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("支持 fn、\u{2318}Command、\u{2325}Option、\u{2303}Control、\u{21E7}Shift 及其组合。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("可以单独使用修饰键（如 fn），也可以组合修饰键 + 普通键（如 \u{2318}\u{21E7}R）。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcut Row

/// A single row in the shortcut settings list with label and a recorder field.
struct ShortcutRow: View {
    let title: String
    let subtitle: String
    let defaultCombo: KeyCombination
    let storageKey: String
    @Binding var storedValue: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ShortcutRecorderView(
                currentCombo: resolvedCombo,
                onRecord: { combo in
                    storedValue = combo.toJSON()
                    HotkeyManager.shared.reloadShortcuts()
                },
                onClear: {
                    storedValue = ""
                    HotkeyManager.shared.reloadShortcuts()
                }
            )
        }
    }

    private var resolvedCombo: KeyCombination {
        if storedValue.isEmpty {
            return defaultCombo
        }
        if storedValue.hasPrefix("{"), let combo = KeyCombination.fromJSON(storedValue) {
            return combo
        }
        let combo = KeyCombination.fromLegacyString(storedValue)
        return combo.isValid ? combo : defaultCombo
    }
}

// MARK: - Shortcut Recorder View

/// An interactive key recorder field. Click to start recording, press a key combination,
/// and the shortcut is captured. Supports modifier-only shortcuts (wait for a brief timeout
/// after modifiers are pressed without a regular key) and modifier+key combos.
struct ShortcutRecorderView: View {
    let currentCombo: KeyCombination
    let onRecord: (KeyCombination) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var pendingModifiers: NSEvent.ModifierFlags = []
    @State private var localMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var modifierTimer: Timer?

    /// How long to wait after modifier keys are pressed before accepting a modifier-only shortcut.
    private let modifierOnlyDelay: TimeInterval = 0.8

    var body: some View {
        HStack(spacing: 4) {
            if isRecording {
                Text("按下快捷键...")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
            } else {
                Text(currentCombo.displayString)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 80)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }
        .contextMenu {
            Button("清除快捷键") {
                onClear()
            }
        }
    }

    private func startRecording() {
        isRecording = true
        pendingModifiers = []

        // Temporarily stop the global hotkey manager so it doesn't interfere with recording
        HotkeyManager.shared.stopMonitoring()

        // Monitor key events locally (for when the settings window is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            self.handleRecordedKeyEvent(event)
            return nil // Consume the event
        }

        // Monitor flags changed for modifier-only shortcuts
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            self.handleRecordedFlagsChanged(event)
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        pendingModifiers = []
        modifierTimer?.invalidate()
        modifierTimer = nil

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }

        // Restart global hotkey monitoring
        HotkeyManager.shared.startMonitoring()
    }

    private func handleRecordedKeyEvent(_ event: NSEvent) {
        // Cancel any pending modifier-only timer
        modifierTimer?.invalidate()
        modifierTimer = nil

        // Escape key cancels recording
        if event.keyCode == 53 { // kVK_Escape
            stopRecording()
            return
        }

        // Build combination from event
        let combo = KeyCombination.fromEvent(event)

        if combo.isValid {
            onRecord(combo)
            stopRecording()
        }
    }

    private func handleRecordedFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])

        if !flags.isEmpty {
            // Modifiers are held: start/restart the timer
            pendingModifiers = flags
            modifierTimer?.invalidate()
            modifierTimer = Timer.scheduledTimer(withTimeInterval: modifierOnlyDelay, repeats: false) { _ in
                DispatchQueue.main.async {
                    // Accept as modifier-only shortcut
                    let combo = KeyCombination.fromModifierFlags(self.pendingModifiers)
                    if combo.isValid {
                        self.onRecord(combo)
                    }
                    self.stopRecording()
                }
            }
        } else {
            // All modifiers released
            if !pendingModifiers.isEmpty {
                // If the timer hasn't fired yet but modifiers were released,
                // accept as modifier-only shortcut immediately
                modifierTimer?.invalidate()
                modifierTimer = nil
                let combo = KeyCombination.fromModifierFlags(pendingModifiers)
                if combo.isValid {
                    onRecord(combo)
                }
                stopRecording()
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("MenuBarIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)

            Text("OpenTypeless")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("版本 0.1.0")
                .foregroundColor(.secondary)

            Text("AI 驱动的语音输入助手")
                .font(.headline)

            Link("GitHub", destination: URL(string: "https://github.com/joeyzenghuan/OpenTypeless")!)

            Spacer()

            Button("退出 OpenTypeless") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(.red)

            Text("Made with ❤️")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    SettingsView()
}
