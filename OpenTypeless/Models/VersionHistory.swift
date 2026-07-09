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
