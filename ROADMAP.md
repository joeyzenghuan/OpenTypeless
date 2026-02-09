# OpenTypeless 开发规划

> 1:1 复刻 [Typeless](https://www.typeless.com/) 的开源 macOS 应用

## 项目概述

OpenTypeless 是一款 AI 驱动的语音输入助手，让用户可以在任何应用中通过语音快速输入、重写和翻译文本。

---

## 架构设计：服务抽象层

为了保证未来的可扩展性，项目采用 **Protocol-based 服务抽象层** 设计，允许用户在设置中自由切换不同的服务提供商。

### 语音识别服务 (SpeechRecognitionProvider)

```swift
protocol SpeechRecognitionProvider {
    var name: String { get }
    var supportsRealtime: Bool { get }
    var supportsOffline: Bool { get }

    func startRecognition(language: String) async throws
    func stopRecognition() async throws -> String
    func onPartialResult(_ handler: @escaping (String) -> Void)
}
```

**支持的提供商：**

| 提供商 | 实时识别 | 离线支持 | 备注 |
|--------|----------|----------|------|
| Apple Speech Framework | ✅ | ✅ | 默认，免费，隐私友好 |
| Azure Speech Service | ✅ | ❌ | 高精度，多语言，需 API Key |
| OpenAI Whisper API | ❌ | ❌ | 高精度，需 API Key |
| 本地 Whisper | ❌ | ✅ | 完全离线，需下载模型 |

### AI 处理服务 (AIProvider)

```swift
protocol AIProvider {
    var name: String { get }

    func format(text: String, context: FormatContext) async throws -> String
    func rewrite(text: String, instruction: String) async throws -> String
    func translate(text: String, to language: String) async throws -> String
}
```

**支持的提供商：**

| 提供商 | 备注 |
|--------|------|
| OpenAI (GPT-4) | 默认推荐 |
| Anthropic (Claude) | 高质量输出 |
| Azure OpenAI | 企业级 |
| 本地 LLM (Ollama) | 完全离线 |

### 设置界面预览

```
┌─────────────────────────────────────┐
│ 语音识别服务                          │
│ ┌─────────────────────────────────┐ │
│ │ ○ Apple Speech (推荐)           │ │
│ │ ○ Azure Speech Service          │ │
│ │ ○ OpenAI Whisper                │ │
│ │ ○ 本地 Whisper                  │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Azure Speech Service 设置           │
│ ┌─────────────────────────────────┐ │
│ │ API Key: ••••••••••••           │ │
│ │ Region:  eastasia               │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

## 进度总览

| 阶段 | 状态 | 完成度 |
|------|------|--------|
| 阶段 1：基础架构 | 🔲 待开始 | 0% |
| 阶段 2：语音转文字 | 🔲 待开始 | 0% |
| 阶段 3：AI 智能处理 | 🔲 待开始 | 0% |
| 阶段 4：高级功能 | 🔲 待开始 | 0% |

状态图例：🔲 待开始 | 🔨 进行中 | ✅ 已完成

---

## 阶段 1：基础架构

**目标**：搭建 macOS 菜单栏应用的基本框架

| 任务 | 状态 | 备注 |
|------|------|------|
| 1.1 创建 Xcode 项目 | 🔲 | Swift + SwiftUI |
| 1.2 菜单栏应用 (Menu Bar App) | 🔲 | NSStatusItem |
| 1.3 全局快捷键监听 | 🔲 | fn 键特殊处理 |
| 1.4 设置界面 UI | 🔲 | 快捷键、语言、账户 |
| 1.5 历史记录界面 UI | 🔲 | 列表展示 |

### 技术细节
- **框架**：Swift 5.9+ / SwiftUI
- **最低支持**：macOS 13.0+
- **快捷键库**：HotKey 或 Carbon API

---

## 阶段 2：语音转文字

**目标**：实现基础的语音识别和文字输入功能，采用可扩展的服务抽象层

| 任务 | 状态 | 备注 |
|------|------|------|
| 2.1 麦克风权限请求 | 🔲 | Info.plist 配置 |
| 2.2 音频录制模块 | 🔲 | AVAudioEngine |
| 2.3 SpeechRecognitionProvider 协议 | 🔲 | 服务抽象层 |
| 2.4 Apple Speech 实现 | 🔲 | 默认提供商 |
| 2.5 Azure Speech Service 实现 | 🔲 | 可选提供商 |
| 2.6 服务提供商设置 UI | 🔲 | 用户可切换 |
| 2.7 获取当前光标位置 | 🔲 | Accessibility API |
| 2.8 文字插入功能 | 🔲 | 模拟键盘输入 |
| 2.9 实时转录显示 | 🔲 | 浮动窗口 |

### 技术细节
- **架构**：Protocol-based 服务抽象层，支持运行时切换提供商
- **默认**：Apple Speech Framework（离线、免费、隐私友好）
- **可选**：Azure Speech Service（高精度、实时流式、多语言）
- **权限**：需要麦克风权限 + 辅助功能权限

### Azure Speech Service 集成要点
- 使用 Azure Speech SDK for iOS/macOS
- 支持实时流式识别 (Real-time Recognition)
- 需要用户配置 API Key 和 Region
- 支持自定义词汇表

---

## 阶段 3：AI 智能处理

**目标**：接入 LLM 实现智能格式化、重写、翻译

| 任务 | 状态 | 备注 |
|------|------|------|
| 3.1 LLM API 集成 | 🔲 | OpenAI / Claude |
| 3.2 智能格式化 | 🔲 | 列表、邮件、电话号码等 |
| 3.3 获取选中文本 | 🔲 | Accessibility API |
| 3.4 文本重写功能 | 🔲 | 选中 + 语音指令 |
| 3.5 翻译功能 | 🔲 | 弹窗显示结果 |
| 3.6 结果替换/插入 | 🔲 | 替换选中文本 |

### 技术细节
- **API 选择**：支持配置 OpenAI / Claude / 本地模型
- **Prompt 设计**：针对不同场景优化提示词

---

## 阶段 4：高级功能

**目标**：完善用户体验和个性化功能

| 任务 | 状态 | 备注 |
|------|------|------|
| 4.1 历史记录存储 | 🔲 | SQLite / CoreData |
| 4.2 历史记录管理 | 🔲 | 搜索、删除、导出 |
| 4.3 个人词典 | 🔲 | 自动学习 + 手动添加 |
| 4.4 多语言自动检测 | 🔲 | 语言识别 |
| 4.5 免提模式 | 🔲 | 持续监听 |
| 4.6 音频保存/回放 | 🔲 | 可选功能 |

---

## 核心功能对照

| Typeless 功能 | OpenTypeless | 状态 |
|---------------|--------------|------|
| 语音转文字 | ✓ 计划实现 | 🔲 |
| 智能格式化 | ✓ 计划实现 | 🔲 |
| 文本重写 | ✓ 计划实现 | 🔲 |
| 翻译功能 | ✓ 计划实现 | 🔲 |
| 多应用适配 | ✓ 计划实现 | 🔲 |
| 历史记录 | ✓ 计划实现 | 🔲 |
| 个人词典 | ✓ 计划实现 | 🔲 |
| 多语言支持 | ✓ 计划实现 | 🔲 |

---

## 快捷键设计

| 操作 | 快捷键 | 说明 |
|------|--------|------|
| 语音输入 | `fn` 按住 | 按住说话，释放插入 |
| 免提模式 | `fn` + `Space` | 持续监听 |
| 翻译模式 | `fn` + `←` | 翻译选中文本 |
| 停止录音 | `Esc` | 取消当前操作 |

---

## 项目结构

```
OpenTypeless/
├── OpenTypeless.xcodeproj        # Xcode 项目
├── OpenTypeless/
│   ├── App/                      # 应用入口
│   │   └── OpenTypelessApp.swift
│   ├── Views/                    # SwiftUI 视图
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   ├── HistoryView.swift
│   │   └── FloatingTranscriptView.swift
│   ├── Services/                 # 核心服务
│   │   ├── Audio/
│   │   │   └── AudioRecorder.swift
│   │   ├── Speech/               # 语音识别抽象层
│   │   │   ├── SpeechRecognitionProvider.swift  # Protocol
│   │   │   ├── SpeechRecognitionManager.swift   # 统一管理器
│   │   │   ├── Providers/
│   │   │   │   ├── AppleSpeechProvider.swift    # Apple Speech
│   │   │   │   ├── AzureSpeechProvider.swift    # Azure Speech
│   │   │   │   ├── WhisperAPIProvider.swift     # OpenAI Whisper
│   │   │   │   └── LocalWhisperProvider.swift   # 本地 Whisper
│   │   │   └── Config/
│   │   │       └── SpeechProviderConfig.swift   # 提供商配置
│   │   ├── AI/                   # AI 处理抽象层
│   │   │   ├── AIProvider.swift              # Protocol
│   │   │   ├── AIManager.swift               # 统一管理器
│   │   │   └── Providers/
│   │   │       ├── OpenAIProvider.swift
│   │   │       ├── ClaudeProvider.swift
│   │   │       └── OllamaProvider.swift
│   │   └── Accessibility/
│   │       └── AccessibilityService.swift
│   ├── Models/                   # 数据模型
│   │   ├── TranscriptionRecord.swift
│   │   ├── UserDictionary.swift
│   │   └── AppSettings.swift
│   ├── Utils/                    # 工具类
│   │   ├── HotkeyManager.swift
│   │   └── KeyboardSimulator.swift
│   └── Resources/                # 资源文件
├── ui_to_learn/                  # 参考截图
├── logs/                         # 日志
└── ROADMAP.md                    # 本文件
```

---

## 更新日志

### 2026-02-09 (v2)
- 新增服务抽象层架构设计
- 支持多语音识别提供商：Apple Speech / Azure Speech / Whisper
- 支持多 AI 提供商：OpenAI / Claude / Ollama
- 更新项目结构，体现 Protocol-based 设计
- 新增设置界面预览

### 2026-02-09 (v1)
- 创建项目规划文档
- 完成功能调研和分析
- 确定技术栈和开发阶段

---

## 下一步

开始 **阶段 1：基础架构**
- [ ] 创建 Xcode 项目
- [ ] 实现菜单栏应用基础框架
