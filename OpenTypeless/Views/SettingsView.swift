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
    @AppStorage("azureSpeechPostRefinementEnabled") private var azureSpeechPostRefinementEnabled = true
    @AppStorage("speechLanguage") private var speechLanguage = "zh-CN"
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
    @AppStorage("gptRealtimeWhisperEndpoint") private var gptRealtimeWhisperEndpoint = ""
    @AppStorage("gptRealtimeWhisperDeployment") private var gptRealtimeWhisperDeployment = "gpt-realtime-whisper-globalstandard"
    @AppStorage("gptRealtimeWhisperAPIKey") private var gptRealtimeWhisperAPIKey = ""
    @AppStorage("gptRealtimeWhisperLanguage") private var gptRealtimeWhisperLanguage = ""
    @AppStorage("gptRealtimeWhisperPrompt") private var gptRealtimeWhisperPrompt = ""
    @AppStorage("maiTranscribeEndpoint") private var maiTranscribeEndpoint = ""
    @AppStorage("maiTranscribeDeployment") private var maiTranscribeDeployment = "mai-transcribe-2-streaming"
    @AppStorage("maiTranscribeAPIKey") private var maiTranscribeAPIKey = ""
    @AppStorage("maiTranscribeLanguage") private var maiTranscribeLanguage = "auto"
    @AppStorage("maiTranscribeBatchUseAzureSpeech") private var maiTranscribeBatchUseAzureSpeech = true
    @AppStorage("maiTranscribeBatchEndpoint") private var maiTranscribeBatchEndpoint = ""
    @AppStorage("maiTranscribeBatchRegion") private var maiTranscribeBatchRegion = "swedencentral"
    @AppStorage("maiTranscribeBatchAPIKey") private var maiTranscribeBatchAPIKey = ""
    @AppStorage("maiTranscribeBatchLanguage") private var maiTranscribeBatchLanguage = "auto"
    @AppStorage("maiTranscribeBatchStyle") private var maiTranscribeBatchStyle = "verbatim"
    @AppStorage("maiTranscribeBatchPhrases") private var maiTranscribeBatchPhrases = ""

    var body: some View {
        Form {
            Section("语音转文本服务") {
                Picker("提供商", selection: $speechProvider) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text("GPT-4o Transcribe (推荐)")
                    }.tag("gpt4o-transcribe")

                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("GPT Realtime Whisper")
                    }.tag("gpt-realtime-whisper")

                    HStack {
                        Image(systemName: "waveform.badge.mic")
                        Text("MAI Transcribe 2 Streaming (预览)")
                    }.tag("mai-transcribe-2-streaming")

                    HStack {
                        Image(systemName: "waveform")
                        Text("MAI Transcribe 2 (非流式预览)")
                    }.tag("mai-transcribe-2")

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
                case "mai-transcribe-2-streaming":
                    ProviderInfoBox(
                        icon: "waveform.badge.mic",
                        title: "MAI Transcribe 2 Streaming",
                        description: "微软实时流式转写，支持 60 种语言和自动语言检测。按住说话时显示预览，松开后等待最终文本。需要 Microsoft Foundry 资源及模型部署。当前为公共预览，无 SLA。",
                        color: .teal
                    )
                case "mai-transcribe-2":
                    ProviderInfoBox(
                        icon: "waveform",
                        title: "MAI Transcribe 2",
                        description: "录音结束后上传完整音频进行转写，不返回实时预览。支持自动语言检测、逐字或清洁转写，以及术语提示。使用 Azure Speech Fast Transcription，无需填写 OpenAI Deployment。当前为公共预览，无 SLA。",
                        color: .teal
                    )
                case "gpt-realtime-whisper":
                    ProviderInfoBox(
                        icon: "dot.radiowaves.left.and.right",
                        title: "GPT Realtime Whisper",
                        description: "Azure OpenAI 实时流式转写。按住快捷键说话时持续输出结果，支持语言提示和转写提示词。需要部署 gpt-realtime-whisper 模型。",
                        color: .orange
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

                    Toggle("最终精修（Post-stream refinement）", isOn: $azureSpeechPostRefinementEnabled)
                    Text("实时预览保持低延迟；Azure 利用更完整的音频上下文进行第二遍识别。精修完成后立即粘贴；缺少精修结果、超时或服务连接异常时，使用已有识别文本，并标记「未完整精修」。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("使用当前识别语言的单语言精修。长句通常更受益，短句可能没有变化。独立于「AI 润色」；同时开启时，AI 会继续处理成功精修后的文本。精修失败时直接输出已有文字，不再等待 AI 润色。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if azureSpeechPostRefinementEnabled,
                       let issue = AzureSpeechRefinement.configurationIssue(region: azureSpeechRegion, language: speechLanguage) {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    Link("查看精修支持的区域与语言",
                         destination: URL(string: "https://learn.microsoft.com/azure/ai-services/speech-service/how-to-recognize-speech#post-stream-refinement")!)
                        .font(.caption)

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

            if speechProvider == "mai-transcribe-2" {
                Section("MAI Transcribe 2 非流式设置") {
                    Toggle("使用现有 Azure Speech Key 和区域", isOn: $maiTranscribeBatchUseAzureSpeech)
                    if maiTranscribeBatchUseAzureSpeech {
                        SecureField("Azure Speech Key", text: $azureSpeechKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Azure Speech Region", text: $azureSpeechRegion)
                            .textFieldStyle(.roundedBorder)
                        Text("与 Azure Speech Service 共用配置。更改此处的 Key 或区域也会影响 Azure Speech。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        SecureField("API Key", text: $maiTranscribeBatchAPIKey)
                            .textFieldStyle(.roundedBorder)
                        TextField("Region", text: $maiTranscribeBatchRegion)
                            .textFieldStyle(.roundedBorder)
                        TextField("Resource Endpoint（可选）", text: $maiTranscribeBatchEndpoint)
                            .textFieldStyle(.roundedBorder)
                        Text("可填写 https://your-resource.cognitiveservices.azure.com；留空时使用区域端点。Key 必须属于所选资源或区域。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    maiLanguagePicker(selection: $maiTranscribeBatchLanguage)

                    Picker("转写风格", selection: $maiTranscribeBatchStyle) {
                        Text("逐字保留（Verbatim）").tag("verbatim")
                        Text("清洁文本（Clean）").tag("clean")
                    }

                    Text("Clean 可去除语气词，使文本更易读；这是转写模型选项，与后续 AI 润色独立。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("术语提示（每行一个）")
                        TextEditor(text: $maiTranscribeBatchPhrases)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 60)
                            .border(Color.gray.opacity(0.3))
                    }

                    Text("默认自动检测。指定语言是强提示，混合语言录音建议自动检测。录音须短于 2 小时、小于 250 MB。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("微软 MAI Transcribe 2 文档",
                         destination: URL(string: "https://learn.microsoft.com/azure/ai-services/speech-service/mai-transcribe")!)
                        .font(.caption)
                }
            }

            if speechProvider == "mai-transcribe-2-streaming" {
                Section("MAI Transcribe 设置") {
                    TextField("Foundry Endpoint URL", text: $maiTranscribeEndpoint)
                        .textFieldStyle(.roundedBorder)

                    Text("例如: https://your-resource.services.ai.azure.com。填写资源根地址，不是 Azure OpenAI 的 /openai 路径。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Deployment Name", text: $maiTranscribeDeployment)
                        .textFieldStyle(.roundedBorder)

                    Text("填写 Foundry 中的实际部署名称；仅当部署名称与模型名一致时使用 mai-transcribe-2-streaming。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("API Key", text: $maiTranscribeAPIKey)
                        .textFieldStyle(.roundedBorder)

                    maiLanguagePicker(selection: $maiTranscribeLanguage)

                    Text("默认自动检测；指定语言时作为语言提示发送，中文使用 zh（简体）。此接入不发送 Prompt，由应用手动提交最终转写。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("单次会话最长 1 小时。最终结果超时或连接失败时不粘贴预览文本；请检查配置和网络后重试。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("微软 MAI Realtime 接入文档",
                         destination: URL(string: "https://learn.microsoft.com/azure/ai-services/speech-service/mai-transcribe-2-streaming-realtime")!)
                        .font(.caption)
                }
            }

            if speechProvider == "gpt-realtime-whisper" {
                Section("GPT Realtime Whisper 设置") {
                    TextField("Endpoint URL", text: $gptRealtimeWhisperEndpoint)
                        .textFieldStyle(.roundedBorder)

                    Text("例如: https://your-resource.cognitiveservices.azure.com")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Deployment Name", text: $gptRealtimeWhisperDeployment)
                        .textFieldStyle(.roundedBorder)

                    Text("GPT Realtime Whisper 模型的部署名称，例如: gpt-realtime-whisper-globalstandard")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("API Key", text: $gptRealtimeWhisperAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Picker("Language", selection: $gptRealtimeWhisperLanguage) {
                        Text("跟随全局设置").tag("")
                        ForEach(SupportedLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }

                    Text("可选。不设置时使用全局语音语言设置。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("转写提示词 (Prompt)")
                        TextEditor(text: $gptRealtimeWhisperPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 80)
                            .border(Color.gray.opacity(0.3))
                    }

                    Text("可选。会作为 realtime transcription prompt 发送，用于术语、上下文和输出风格引导。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("Azure OpenAI Realtime 文档",
                         destination: URL(string: "https://learn.microsoft.com/azure/ai-foundry/openai/how-to/realtime-audio")!)
                        .font(.caption)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
    }

    private func maiLanguagePicker(selection: Binding<String>) -> some View {
        Picker("Language", selection: selection) {
            Text("自动检测（支持多语言）").tag("auto")
            Text("跟随全局设置").tag("")
            Text("简体中文").tag("zh")
            Text("English").tag("en")
            Text("日本語").tag("ja")
            Text("한국어").tag("ko")
            Text("Français").tag("fr")
            Text("Deutsch").tag("de")
            Text("Español").tag("es")
            Text("Português").tag("pt")
        }
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

            Text("版本 \(AppVersion.displayName)")
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
