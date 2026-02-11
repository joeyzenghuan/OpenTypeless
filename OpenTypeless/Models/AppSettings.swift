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

    // Whisper (Azure OpenAI)
    @AppStorage("whisperEndpoint") var whisperEndpoint: String = ""
    @AppStorage("whisperDeployment") var whisperDeployment: String = "whisper"
    @AppStorage("whisperAPIKey") var whisperAPIKey: String = ""

    // GPT-4o Transcribe (Azure OpenAI)
    @AppStorage("gpt4oTranscribeEndpoint") var gpt4oTranscribeEndpoint: String = ""
    @AppStorage("gpt4oTranscribeDeployment") var gpt4oTranscribeDeployment: String = "gpt-4o-transcribe"
    @AppStorage("gpt4oTranscribeAPIKey") var gpt4oTranscribeAPIKey: String = ""
    @AppStorage("gpt4oTranscribeTemperature") var gpt4oTranscribeTemperature: Double = 0
    @AppStorage("gpt4oTranscribePrompt") var gpt4oTranscribePrompt: String = ""
    @AppStorage("gpt4oTranscribeLogprobs") var gpt4oTranscribeLogprobs: Bool = false
    @AppStorage("gpt4oTranscribeLanguage") var gpt4oTranscribeLanguage: String = ""

    // MARK: - AI Settings

    @AppStorage("aiProvider") var aiProvider: String = "openai"
    @AppStorage("openaiAPIKey") var openaiAPIKey: String = ""
    @AppStorage("claudeAPIKey") var claudeAPIKey: String = ""
    @AppStorage("ollamaEndpoint") var ollamaEndpoint: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3"

    // MARK: - Shortcuts
    // Stored as JSON strings representing KeyCombination objects.
    // Legacy string values (e.g., "fn", "fn+space") are migrated on first access.

    @AppStorage("shortcutVoiceInput") var shortcutVoiceInput: String = ""
    @AppStorage("shortcutHandsFree") var shortcutHandsFree: String = ""
    @AppStorage("shortcutTranslate") var shortcutTranslate: String = ""

    /// Retrieve the KeyCombination for voice input, migrating from legacy format if needed.
    func getVoiceInputShortcut() -> KeyCombination {
        return resolveShortcut(shortcutVoiceInput, default: .defaultVoiceInput)
    }

    /// Retrieve the KeyCombination for hands-free mode, migrating from legacy format if needed.
    func getHandsFreeShortcut() -> KeyCombination {
        return resolveShortcut(shortcutHandsFree, default: .defaultHandsFree)
    }

    /// Retrieve the KeyCombination for translate, migrating from legacy format if needed.
    func getTranslateShortcut() -> KeyCombination {
        return resolveShortcut(shortcutTranslate, default: .defaultTranslate)
    }

    /// Save a KeyCombination for a given shortcut key.
    func setShortcut(_ combo: KeyCombination, forKey key: String) {
        let json = combo.toJSON()
        UserDefaults.standard.set(json, forKey: key)
    }

    /// Resolve a stored shortcut string, handling empty, legacy, and JSON formats.
    private func resolveShortcut(_ stored: String, default defaultCombo: KeyCombination) -> KeyCombination {
        // Empty string: return default
        if stored.isEmpty {
            return defaultCombo
        }
        // Try JSON first
        if stored.hasPrefix("{"), let combo = KeyCombination.fromJSON(stored) {
            return combo
        }
        // Legacy string format (e.g., "fn", "fn+space")
        let combo = KeyCombination.fromLegacyString(stored)
        return combo.isValid ? combo : defaultCombo
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Methods

    /// Get speech provider configuration
    func getSpeechProviderConfig() -> SpeechProviderConfig {
        var config = SpeechProviderConfig()
        config.azureSubscriptionKey = azureSpeechKey.isEmpty ? nil : azureSpeechKey
        config.azureRegion = azureSpeechRegion.isEmpty ? nil : azureSpeechRegion
        config.openAIAPIKey = whisperAPIKey.isEmpty ? nil : whisperAPIKey
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
        whisperEndpoint = ""
        whisperDeployment = "whisper"
        whisperAPIKey = ""
        gpt4oTranscribeEndpoint = ""
        gpt4oTranscribeDeployment = "gpt-4o-transcribe"
        gpt4oTranscribeAPIKey = ""
        gpt4oTranscribeTemperature = 0
        gpt4oTranscribePrompt = ""
        gpt4oTranscribeLogprobs = false
        gpt4oTranscribeLanguage = ""

        aiProvider = "openai"
        openaiAPIKey = ""
        claudeAPIKey = ""
        ollamaEndpoint = "http://localhost:11434"
        ollamaModel = "llama3"

        shortcutVoiceInput = ""
        shortcutHandsFree = ""
        shortcutTranslate = ""
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
