# CLAUDE.md

This file provides context for Claude Code when working on the OpenTypeless project.

## Project Overview

OpenTypeless is a native macOS menu bar app (Swift 5.9+ / SwiftUI) that provides AI-powered voice input. Users hold a hotkey to speak, and on release the transcribed (and optionally AI-polished) text is inserted at the cursor position via clipboard paste.

## Tech Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Target**: macOS 13.0+
- **Project Generation**: XcodeGen (`project.yml`)
- **Dependency Manager**: CocoaPods
- **External Dependencies**: `MicrosoftCognitiveServicesSpeech-macOS` (~> 1.40)
- **Database**: SQLite3 (C API, no ORM)
- **Build System**: Xcode 15.0+

## Architecture

Protocol-based service abstraction layer with two key protocols:

- `SpeechRecognitionProvider` — defines the interface for speech-to-text engines
- `AIProvider` — defines the interface for AI text polish engines

Providers are selected at runtime based on `UserDefaults` settings. The app delegates provider management to `AppDelegate` rather than using `SpeechRecognitionManager` directly.

### Key Singletons

- `AppSettings.shared` — all user preferences via `@AppStorage`
- `FloatingPanelController.shared` — floating panel UI state
- `HotkeyManager.shared` — global keyboard shortcut monitoring
- `HistoryManager.shared` — in-memory cache + SQLite persistence
- `HistoryDatabase.shared` — raw SQLite operations
- `Logger.shared` — file-based logging with daily rotation

## Build & Run

```bash
# First time setup
./scripts/setup.sh    # installs XcodeGen, generates .xcodeproj
pod install           # installs Azure Speech SDK
open OpenTypeless.xcworkspace

# Regenerate Xcode project after changing project.yml
xcodegen generate
```

Always open `.xcworkspace` (not `.xcodeproj`) when CocoaPods are involved.

## Project Layout

```
OpenTypeless/
├── project.yml                    # XcodeGen project definition
├── Podfile                        # CocoaPods dependencies
├── scripts/setup.sh               # Dev environment setup
├── OpenTypeless/
│   ├── App/OpenTypelessApp.swift  # @main entry + AppDelegate
│   ├── Views/                     # SwiftUI views
│   ├── Services/Speech/Providers/ # STT provider implementations
│   ├── Services/AI/Providers/     # AI provider implementations
│   ├── Services/Database/         # SQLite history storage
│   ├── Models/                    # Data models + settings
│   ├── Utils/                     # HotkeyManager, Logger
│   └── Resources/                 # Info.plist, entitlements, assets
└── releases/                      # .app release builds
```

## Speech Recognition Providers

| Provider | File | Identifier | Real-time |
|----------|------|------------|-----------|
| Apple Speech | `AppleSpeechProvider.swift` | `apple` | Yes |
| Azure Speech | `AzureSpeechProvider.swift` | `azure` | Yes |
| Whisper | `WhisperSpeechProvider.swift` | `whisper` | No |
| GPT-4o Transcribe | `GPT4oTranscribeSpeechProvider.swift` | `gpt4o-transcribe` | No |

Non-realtime providers (Whisper, GPT-4o) record audio to a WAV file, then upload for transcription on stop.

## AI Providers

Only `AzureOpenAIProvider` is implemented. It supports both Chat Completions API and Responses API. Other providers (OpenAI, Claude, Ollama) have settings UI but no backend implementation yet.

## Important Patterns

- Text insertion uses **clipboard + simulated Cmd+V** (requires Accessibility permission)
- Non-realtime STT providers use `beginCapture()` for low-latency audio start, then `startRecognition()` for async setup
- The floating panel auto-hides after 1.5s on success, 2.0s on error
- Recording shorter than 1 second is discarded to avoid accidental triggers
- Shortcuts are stored as JSON-serialized `KeyCombination` objects in UserDefaults, with legacy string format migration
- Azure Speech SDK is conditionally imported with `#if canImport(MicrosoftCognitiveServicesSpeech)`
- Log files are stored in `~/Library/Application Support/OpenTypeless/Logs/`
- History database is at `~/Library/Application Support/OpenTypeless/history.sqlite`
- Audio recordings are saved in `~/Library/Application Support/OpenTypeless/audio/`

## Entitlements

- `com.apple.security.app-sandbox` — App Sandbox enabled
- `com.apple.security.device.audio-input` — Microphone access
- `com.apple.security.network.client` — Outbound network access

## Common Tasks

- **Add a new STT provider**: Implement `SpeechRecognitionProvider` protocol, add case in `AppDelegate.setupSpeechRecognition()`, add settings UI in `SpeechProviderSettingsView`
- **Add a new AI provider**: Implement `AIProvider` protocol, wire it up in `AppDelegate`, add settings UI in `AIProviderSettingsView`
- **Change default shortcuts**: Modify `KeyCombination.defaultVoiceInput`, `.defaultHandsFree`, `.defaultTranslate`
- **Modify the floating panel**: Edit `FloatingTranscriptView` and `FloatingPanelController`
