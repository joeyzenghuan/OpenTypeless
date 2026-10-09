import Foundation

struct AppVersion {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var displayName: String {
        "v\(version) (\(build))"
    }

    static var identifier: String {
        "\(version)-\(build)"
    }
}

struct VersionHistoryEntry: Identifiable {
    let version: String
    let build: String
    let date: String
    let title: String
    let changes: [String]

    var id: String { "\(version)-\(build)" }
    var displayVersion: String { "v\(version) (\(build))" }
}

enum VersionHistory {
    static let entries: [VersionHistoryEntry] = [
        VersionHistoryEntry(
            version: "0.4.0",
            build: "4",
            date: "2026-10-09",
            title: "MAI 双模式语音转写",
            changes: [
                "新增 MAI Transcribe 2 Streaming，录音时显示实时预览，停止后等待完整最终文本再插入。",
                "新增 MAI Transcribe 2 非流式转写，支持逐字或清洁文本、术语提示和录音历史保存。",
                "两种 MAI 引擎均支持自动语言检测和语言提示，非流式可共用现有 Azure Speech 配置。",
                "实时显示连接、识别和最终转写状态；错误、超时或取消时不插入不完整的预览。",
                "完成真实 Azure 中英文转写测试及 macOS 手动测试，新增两种引擎的回归测试和实测记录。"
            ]
        ),
        VersionHistoryEntry(
            version: "0.3.0",
            build: "3",
            date: "2026-09-19",
            title: "Azure 最终精修与双阶段识别展示",
            changes: [
                "Azure Speech 新增默认开启的最终精修开关，升级 Speech SDK 至 1.51.2。",
                "标准识别和精修模式均上下展示实时预览与最终结果，清楚区分识别阶段。",
                "修复多句停顿、音频时间偏移和延迟回调时的结果合并，避免遗漏后续句子。",
                "精修缺失、超时或连接异常时保留已识别文字，并在浮窗和历史记录中标明未完整精修。",
                "最终输出就绪后立即发起粘贴，浮窗继续展示；辅助功能权限未生效时保留剪贴板并提示手动粘贴。",
                "历史记录新增精修对照，并保存精修降级原因。"
            ]
        ),
        VersionHistoryEntry(
            version: "0.2.0",
            build: "2",
            date: "2026-07-09",
            title: "Realtime 语音和测试体验增强",
            changes: [
                "新增 GPT Realtime Whisper 实时语音转文字提供商。",
                "GPT Realtime Whisper 和 Azure Speech Service 增加连接状态显示和错误提示。",
                "修复浮窗抢焦点导致识别完成后无法自动粘贴的问题。",
                "新增 macOS App 图标，安装到应用程序后不再显示默认占位图标。",
                "新增版本更新历史入口，测试时可以确认当前运行版本。"
            ]
        ),
        VersionHistoryEntry(
            version: "0.1.0",
            build: "1",
            date: "2026-02-21",
            title: "初始测试版本",
            changes: [
                "提供菜单栏语音输入和全局快捷键。",
                "支持 Apple Speech、Azure Speech Service、Azure OpenAI Whisper 和 GPT-4o Transcribe。",
                "支持转写历史记录、音频保存和搜索。",
                "支持 Azure OpenAI 文本润色。"
            ]
        )
    ]
}
