import Foundation
import SwiftUI

/// App-wide settings managed via UserDefaults
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - General Settings

    @AppStorage("interfaceLanguage") var interfaceLanguage: String = "zh-Hans"
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showInDock") var showInDock: Bool = false
    @AppStorage("historyRetentionDays") var historyRetentionDays: Int = -1 // -1 = forever

    // MARK: - Speech Recognition Settings

    @AppStorage("speechProvider") var speechProvider: String = "apple"
    @AppStorage("speechLanguage") var speechLanguage: String = "zh-CN"

    // Azure Speech
    @AppStorage("azureSpeechKey") var azureSpeechKey: String = ""
    @AppStorage("azureSpeechRegion") var azureSpeechRegion: String = "eastasia"

    // Whisper
    @AppStorage("whisperAPIKey") var whisperAPIKey: String = ""
    @AppStorage("localWhisperModel") var localWhisperModel: String = "base"

    // MARK: - AI Settings

    @AppStorage("aiProvider") var aiProvider: String = "openai"
    @AppStorage("openaiAPIKey") var openaiAPIKey: String = ""
    @AppStorage("claudeAPIKey") var claudeAPIKey: String = ""
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3"

    // MARK: - Shortcuts

    @AppStorage("shortcutVoiceInput") var shortcutVoiceInput: String = "fn"
    @AppStorage("shortcutHandsFree") var shortcutHandsFree: String = "fn+space"
    @AppStorage("shortcutTranslate") var shortcutTranslate: String = "fn+left"

    // MARK: - Initialization

    private init() {}

    // MARK: - Methods

    /// Get speech provider configuration
    func getSpeechProviderConfig() -> SpeechProviderConfig {
        var config = SpeechProviderConfig()
        config.azureSubscriptionKey = azureSpeechKey.isEmpty ? nil : azureSpeechKey
        config.azureRegion = azureSpeechRegion.isEmpty ? nil : azureSpeechRegion
        config.openAIAPIKey = whisperAPIKey.isEmpty ? nil : whisperAPIKey
        config.localWhisperModelSize = SpeechProviderConfig.WhisperModelSize(rawValue: localWhisperModel)
        return config
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        interfaceLanguage = "zh-Hans"
        launchAtLogin = false
        showInDock = false
        historyRetentionDays = -1

        speechProvider = "apple"
        speechLanguage = "zh-CN"
        azureSpeechKey = ""
        azureSpeechRegion = "eastasia"
        whisperAPIKey = ""
        localWhisperModel = "base"

        aiProvider = "openai"
        openaiAPIKey = ""
        claudeAPIKey = ""
        ollamaEndpoint = "http://localhost:11434"
        ollamaModel = "llama3"
    }
}

// MARK: - Supported Languages

enum SupportedLanguage: String, CaseIterable {
    case zhCN = "zh-CN"
    case zhTW = "zh-TW"
    case enUS = "en-US"
    case enGB = "en-GB"
    case jaJP = "ja-JP"
    case koKR = "ko-KR"
    case frFR = "fr-FR"
    case deDE = "de-DE"
    case esES = "es-ES"
    case ptBR = "pt-BR"

    var displayName: String {
        switch self {
        case .zhCN: return "简体中文"
        case .zhTW: return "繁體中文"
        case .enUS: return "English (US)"
        case .enGB: return "English (UK)"
        case .jaJP: return "日本語"
        case .koKR: return "한국어"
        case .frFR: return "Français"
        case .deDE: return "Deutsch"
        case .esES: return "Español"
        case .ptBR: return "Português"
        }
    }
}
