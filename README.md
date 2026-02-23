# OpenTypeless

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_13.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-0.1.0-brightgreen" alt="Version">
</p>

<p align="center">
  开源的 AI 驱动语音输入助手，适用于 macOS。<br>
  按住快捷键说话，释放后自动将文字插入到任意应用中。<br>
  灵感来自 <a href="https://www.typeless.com/">Typeless</a>。
</p>

<p align="center">
  <a href="README_EN.md">English</a> | 中文
</p>

---

## 功能特性

- **语音转文字** — 按住 `fn` 键说话，松开后文字自动插入光标位置
- **多语音引擎** — 支持 Apple Speech（免费离线）、Azure Speech（实时流式）、Azure OpenAI Whisper、GPT-4o Transcribe
- **AI 智能润色** — 语音识别后可通过 LLM 自动修正错别字、添加标点、分条列点、去重
- **浮动面板** — 实时显示录音状态和识别结果，支持取消操作
- **历史记录** — SQLite 持久化存储，支持搜索、回放录音、对比原文与润色后文本
- **自定义快捷键** — 语音输入、免提模式、翻译模式均可自定义按键组合
- **多语言识别** — 支持中文、英语、日语、韩语、法语、德语、西班牙语、葡萄牙语等 10 种语言
- **菜单栏应用** — 常驻菜单栏，不占用 Dock 栏位
- **自定义 System Prompt** — AI 润色的提示词完全可自定义
- **可配置超时** — API 请求超时时间可自由设置
- **文件日志** — 支持 Info / Debug 两级日志，日志文件按天滚动，内置日志查看器

## 下载安装

从 [Releases](https://github.com/joeyzenghuan/OpenTypeless/releases) 下载最新的 `OpenTypeless.zip`，解压后将 `OpenTypeless.app` 拖入 `Applications` 文件夹。

> 首次打开时 macOS 可能提示"无法验证开发者"。请前往 **系统设置 → 隐私与安全性**，点击"仍要打开"。

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- 麦克风权限
- 辅助功能权限（用于文字插入）

### 开启辅助功能权限

OpenTypeless 通过模拟键盘粘贴（Cmd+V）来插入文字，需要辅助功能权限。请前往 **系统设置 → 隐私与安全性 → 辅助功能**，点击 `+` 添加 OpenTypeless 并开启开关：

<p align="center">
  <img src="docs/accessibility-setup.png" width="600" alt="辅助功能权限设置">
</p>

## 语音识别引擎

| 引擎 | 实时识别 | 离线 | 说明 |
|------|:------:|:----:|------|
| Apple Speech | ✅ | ✅ | 默认，免费，隐私友好，无需配置 |
| Azure Speech Service | ✅ | ❌ | 高精度、实时流式、100+ 语言，需 Azure 订阅 |
| Azure OpenAI Whisper | ❌ | ❌ | 高精度多语言，录音结束后整段转写，需部署 Whisper 模型 |
| GPT-4o Transcribe | ❌ | ❌ | 比 Whisper 更高精度，支持置信度评分和提示词引导（推荐） |

## AI 润色引擎

| 引擎 | 说明 |
|------|------|
| Azure OpenAI | 已实现，支持 Chat Completions API 和 Responses API |
| OpenAI (GPT-4) | 设置界面已就绪，Provider 待实现 |
| Anthropic (Claude) | 设置界面已就绪，Provider 待实现 |
| 本地 LLM (Ollama) | 设置界面已就绪，Provider 待实现 |

## 快捷键

| 操作 | 默认快捷键 | 说明 |
|------|-----------|------|
| 语音输入 | 按住 `fn` | 按住说话，释放后插入文字 |
| 免提模式 | `fn` + `Space` | 按一次开始，再按一次停止 |
| 翻译模式 | `fn` + `←` | 翻译选中文本（待实现） |

所有快捷键均可在设置中自定义，支持 fn、⌘、⌥、⌃、⇧ 及其任意组合。

## 从源码构建

### 前置条件

- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [CocoaPods](https://cocoapods.org/)

### 快速开始

```bash
git clone https://github.com/joeyzenghuan/OpenTypeless.git
cd OpenTypeless

# 运行 setup 脚本（安装 XcodeGen 并生成 Xcode 项目）
./scripts/setup.sh

# 安装 CocoaPods 依赖
pod install

# 打开 Xcode 工作区
open OpenTypeless.xcworkspace
```

### 手动设置

```bash
brew install xcodegen
xcodegen generate
pod install
open OpenTypeless.xcworkspace
```

在 Xcode 中配置 **Signing & Capabilities** 后，按 `⌘R` 运行。

## 项目结构

```
OpenTypeless/
├── App/                          # 应用入口 (AppDelegate + Menu Bar)
├── Views/
│   ├── MenuBarView.swift         # 主窗口（首页、历史记录、设置侧边栏）
│   ├── SettingsView.swift        # 设置页（语音/AI/通用/快捷键/关于）
│   └── FloatingTranscriptView.swift  # 浮动面板（录音状态 + 识别结果）
├── Services/
│   ├── Speech/
│   │   ├── SpeechRecognitionProvider.swift  # 语音识别 Protocol
│   │   ├── SpeechRecognitionManager.swift   # 统一管理器
│   │   └── Providers/
│   │       ├── AppleSpeechProvider.swift     # Apple Speech Framework
│   │       ├── AzureSpeechProvider.swift     # Azure Speech SDK
│   │       ├── WhisperSpeechProvider.swift   # Azure OpenAI Whisper
│   │       └── GPT4oTranscribeSpeechProvider.swift  # GPT-4o Transcribe
│   ├── AI/
│   │   ├── AIProvider.swift                 # AI 润色 Protocol
│   │   └── Providers/
│   │       └── AzureOpenAIProvider.swift     # Azure OpenAI (Chat Completions + Responses)
│   └── Database/
│       └── HistoryDatabase.swift            # SQLite 历史记录存储
├── Models/
│   ├── AppSettings.swift          # 应用设置 (UserDefaults)
│   ├── KeyCombination.swift       # 快捷键组合模型
│   └── TranscriptionRecord.swift  # 转录记录模型 + HistoryManager
├── Utils/
│   ├── HotkeyManager.swift        # 全局快捷键监听
│   └── Logger.swift               # 文件日志系统
└── Resources/
    ├── Info.plist
    ├── OpenTypeless.entitlements
    └── Assets.xcassets/            # 应用图标（Westie 狗狗）
```

## 架构设计

项目采用 **Protocol-based 服务抽象层**，语音识别和 AI 润色均通过 Protocol 定义接口，支持运行时切换 Provider。

```
用户按住快捷键
    → HotkeyManager 检测
    → SpeechRecognitionProvider.startRecognition()
    → FloatingPanel 显示实时结果
用户松开快捷键
    → SpeechRecognitionProvider.stopRecognition()
    → AIProvider.polish() (可选)
    → 通过剪贴板 + Cmd+V 插入文字
    → HistoryDatabase 保存记录
```

## 配置说明

所有配置通过应用内设置界面管理，存储在 `UserDefaults` 中。主要配置项：

- **语音识别引擎** — 选择 STT Provider 并填写对应 API Key
- **AI 润色** — 开关、Provider 选择、Azure OpenAI 端点/Key/部署名、API 类型
- **System Prompt** — AI 润色的系统提示词，可完全自定义
- **快捷键** — 三种操作的按键组合
- **通用** — 界面语言、API 超时、日志级别

## 许可证

MIT License

## 致谢

- 灵感来自 [Typeless](https://www.typeless.com/)
- 基于 SwiftUI + Apple Speech Framework 构建
- Azure Speech SDK via [CocoaPods](https://cocoapods.org/)
