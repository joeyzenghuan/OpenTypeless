# OpenTypeless

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

An open-source AI-powered voice input assistant for macOS, inspired by [Typeless](https://www.typeless.com/).

## Features

- **Voice to Text** - Hold `fn` to speak, release to insert text
- **Smart Formatting** - Auto-format lists, emails, phone numbers
- **Text Rewriting** - Select text + voice command to rewrite
- **Translation** - Translate selected text instantly
- **Multi-app Support** - Works in any application
- **History** - Save and manage transcription history
- **Personal Dictionary** - Learn your unique vocabulary
- **Multiple Providers** - Choose from Apple Speech, Azure, Whisper

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Quick Start

```bash
# Clone the repository
git clone https://github.com/joeyzenghuan/OpenTypeless.git
cd OpenTypeless

# Run setup script
./scripts/setup.sh

# Open in Xcode
open OpenTypeless.xcodeproj
```

## Manual Setup

If you prefer manual setup:

1. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```

2. Generate Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open `OpenTypeless.xcodeproj` in Xcode

4. Configure signing in Signing & Capabilities

5. Build and run (⌘R)

## Configuration

### Speech Recognition Providers

| Provider | Realtime | Offline | Setup |
|----------|----------|---------|-------|
| Apple Speech | ✅ | ✅ | Default, no setup needed |
| Azure Speech | ✅ | ❌ | Requires API key |
| OpenAI Whisper | ❌ | ❌ | Requires API key |
| Local Whisper | ❌ | ✅ | Download model |

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Voice input | Hold `fn` |
| Hands-free mode | `fn` + `Space` |
| Translate | `fn` + `←` |
| Cancel | `Esc` |

## Project Structure

```
OpenTypeless/
├── App/                    # Application entry point
├── Views/                  # SwiftUI views
├── Services/
│   ├── Speech/            # Speech recognition
│   │   ├── Providers/     # Provider implementations
│   │   └── ...
│   ├── AI/                # AI processing
│   └── Accessibility/     # System integration
├── Models/                 # Data models
├── Utils/                  # Utilities
└── Resources/              # Assets, Info.plist
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for development progress.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [Typeless](https://www.typeless.com/)
- Built with SwiftUI and Apple Speech Framework
