#!/bin/bash
# build.sh — Compile CopyCapsule, create .app bundle, package DMG
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CopyCapsule"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
VERSION="${VERSION:-2.1.0}"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

echo "=== Building $APP_NAME v$VERSION ==="

cd "$PROJECT_DIR"

# 1. Build release binary with SwiftPM
swift build -c release --disable-sandbox

# 2. Locate binary
ARCH_DIR=$(ls -d "$BUILD_DIR"/*-apple-macosx 2>/dev/null | head -1)
BINARY="$ARCH_DIR/release/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    find "$BUILD_DIR" -type f -name "$APP_NAME" 2>/dev/null || echo "(no matching binary)"
    exit 1
fi

echo "Binary: $BINARY"

# 3. Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 4. Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 5. Copy Sparkle framework (auto-update engine)
SPARKLE_FW="$BUILD_DIR/arm64-apple-macosx/release/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/MacOS/"
    echo "Sparkle framework embedded"
else
    echo "Warning: Sparkle.framework not found at $SPARKLE_FW"
fi

# 5. Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# 5b. Copy app icon
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# 6. Ad-hoc code signing
echo "Signing with ad-hoc identity..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || echo "Warning: codesign failed"

echo ""
echo "=== App bundle ready ==="
echo "App: $APP_BUNDLE"
echo "Run: open \"$APP_BUNDLE\""
echo ""

# 7. Create DMG for distribution
echo "=== Creating DMG ==="
rm -f "$DMG_PATH"

# Build a staging directory with app + Applications symlink
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

# 8. Generate Sparkle appcast signature placeholder
echo "=== DMG ready ==="
echo "DMG: $DMG_PATH"
echo ""
echo "📦 Distribution package: $(basename "$DMG_PATH")"
echo "📏 Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "Next steps for release:"
echo "  1. Generate Sparkle signature:"
echo "     ./Scripts/sign-update.sh $DMG_PATH"
echo "  2. Upload DMG to GitHub Releases"
echo "  3. Update Resources/appcast.xml with new version + signature"
echo "  4. Commit and push appcast.xml"
echo ""
