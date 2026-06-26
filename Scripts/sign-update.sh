#!/bin/bash
# sign-update.sh — Generate Sparkle appcast entry for a DMG
# Usage: ./Scripts/sign-update.sh CopyCapsule-2.0.0.dmg
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_TOOLS="$PROJECT_DIR/.build/sparkle-tools"
GENERATE_APPCAST="$SPARKLE_TOOLS/generate_appcast"

DMG_PATH="${1:-}"
if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
    echo "Usage: $0 <path-to.dmg>"
    exit 1
fi

# Download Sparkle CLI tools if not present
if [ ! -f "$GENERATE_APPCAST" ]; then
    SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-for-Swift-Package-Manager.zip"
    echo "Downloading Sparkle tools..."
    mkdir -p "$SPARKLE_TOOLS"
    curl -sL "$SPARKLE_URL" -o "$SPARKLE_TOOLS/sparkle.zip"
    unzip -o -q "$SPARKLE_TOOLS/sparkle.zip" -d "$SPARKLE_TOOLS"
    # generate_appcast is inside the bin/ directory
    if [ -f "$SPARKLE_TOOLS/bin/generate_appcast" ]; then
        cp "$SPARKLE_TOOLS/bin/generate_appcast" "$SPARKLE_TOOLS/"
    fi
    chmod +x "$SPARKLE_TOOLS/generate_appcast" 2>/dev/null || true
    echo "Sparkle tools ready."
fi

# Generate appcast entry
echo "Generating appcast signature for: $(basename "$DMG_PATH")"
"$GENERATE_APPCAST" "$PROJECT_DIR/Resources"

echo ""
echo "=== Done ==="
echo "appcast.xml updated at: Resources/appcast.xml"
echo "Upload the DMG to GitHub Releases, then commit and push appcast.xml."
