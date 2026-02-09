import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            SpeechProviderSettingsView()
                .tabItem {
                    Label("语音识别", systemImage: "mic")
                }

            AIProviderSettingsView()
                .tabItem {
                    Label("AI 服务", systemImage: "brain")
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
        .frame(width: 550, height: 500)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "zh-Hans"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false

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
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Speech Provider Settings

struct SpeechProviderSettingsView: View {
    @AppStorage("speechProvider") private var speechProvider = "apple"
    @AppStorage("azureSpeechKey") private var azureSpeechKey = ""
    @AppStorage("azureSpeechRegion") private var azureSpeechRegion = "eastasia"
    @AppStorage("whisperAPIKey") private var whisperAPIKey = ""

    var body: some View {
        Form {
            Section("语音识别服务") {
                Picker("提供商", selection: $speechProvider) {
                    HStack {
                        Image(systemName: "apple.logo")
                        Text("Apple Speech (推荐)")
                    }.tag("apple")

                    HStack {
                        Image(systemName: "cloud")
                        Text("Azure Speech Service")
                    }.tag("azure")

                    HStack {
                        Image(systemName: "waveform")
                        Text("OpenAI Whisper")
                    }.tag("whisper")

                    HStack {
                        Image(systemName: "desktopcomputer")
                        Text("本地 Whisper")
                    }.tag("local-whisper")
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
                        title: "OpenAI Whisper API",
                        description: "高精度多语言识别。需要 OpenAI API Key，按使用量计费。",
                        color: .purple
                    )
                case "local-whisper":
                    ProviderInfoBox(
                        icon: "desktopcomputer",
                        title: "本地 Whisper",
                        description: "完全离线运行。需要下载模型文件（约 1-3GB）。",
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

                    Link("获取 Azure Speech API Key",
                         destination: URL(string: "https://azure.microsoft.com/products/cognitive-services/speech-services")!)
                        .font(.caption)
                }
            }

            // Whisper API Settings
            if speechProvider == "whisper" {
                Section("OpenAI Whisper 设置") {
                    SecureField("API Key", text: $whisperAPIKey)

                    Link("获取 OpenAI API Key",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            }

            // Local Whisper Settings
            if speechProvider == "local-whisper" {
                Section("本地 Whisper 设置") {
                    HStack {
                        Text("模型")
                        Spacer()
                        Picker("", selection: .constant("base")) {
                            Text("Tiny (75MB)").tag("tiny")
                            Text("Base (142MB)").tag("base")
                            Text("Small (466MB)").tag("small")
                            Text("Medium (1.5GB)").tag("medium")
                        }
                        .frame(width: 150)
                    }

                    Button("下载模型") {
                        // Download model
                    }
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
你是一个文本润色助手。请对用户的语音转文字内容进行优化：
1. 修正明显的语音识别错误
2. 添加适当的标点符号
3. 保持原意不变，使文字更通顺
4. 不要添加额外的内容或解释
5. 直接输出润色后的文字，不要有任何前缀或说明
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
你是一个文本润色助手。请对用户的语音转文字内容进行优化：
1. 修正明显的语音识别错误
2. 添加适当的标点符号
3. 保持原意不变，使文字更通顺
4. 不要添加额外的内容或解释
5. 直接输出润色后的文字，不要有任何前缀或说明
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
    var body: some View {
        Form {
            Section("键盘快捷键") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("语音输入")
                        Text("按住说话，释放后插入文本模式")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("fn")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("免提模式")
                        Text("无需按住，再次按下停止")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("fn")
                        Text("+")
                        Text("Space")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("翻译模式")
                        Text("翻译选中的文本")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("fn")
                        Text("+")
                        Text("←")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("OpenTypeless")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("版本 0.1.0")
                .foregroundColor(.secondary)

            Text("AI 驱动的语音输入助手")
                .font(.headline)

            Link("GitHub", destination: URL(string: "https://github.com/joeyzenghuan/OpenTypeless")!)

            Spacer()

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
