#!/bin/bash
# EonCode — Xcode Project Generator
# Run this script on your Mac to generate the Xcode project
#
# Requirements: xcodegen (brew install xcodegen)
#
# Usage: ./generate-xcode.sh

set -e

echo "🚀 EonCode — Generating Xcode Project"
echo "======================================"

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "⚠️  xcodegen not found. Installing via Homebrew..."
    brew install xcodegen
fi

# Generate project
echo "📦 Generating EonCode.xcodeproj..."
xcodegen generate --spec project.yml

echo ""
echo "✅ Done! Opening EonCode.xcodeproj..."
open EonCode.xcodeproj
