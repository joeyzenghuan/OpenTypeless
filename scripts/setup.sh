#!/bin/bash

# OpenTypeless Project Setup Script
# This script sets up the development environment

set -e

echo "🚀 Setting up OpenTypeless development environment..."

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew is not installed. Please install it first:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# Install XcodeGen if not present
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Installing XcodeGen..."
    brew install xcodegen
else
    echo "✅ XcodeGen is already installed"
fi

# Generate Xcode project
echo "🔧 Generating Xcode project..."
cd "$(dirname "$0")/.."
xcodegen generate

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open OpenTypeless.xcodeproj in Xcode"
echo "  2. Select your development team in Signing & Capabilities"
echo "  3. Build and run (⌘R)"
echo ""
echo "📖 See README.md for more information"
