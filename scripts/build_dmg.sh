#!/usr/bin/env bash
# VibeRadar DMG builder
# Usage: ./scripts/build_dmg.sh
# Requires: create-dmg (brew install create-dmg)
set -e

APP_NAME="VibeRadar"
VERSION=$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
BUILD_DIR="build/macos/Build/Products/Release"
DIST_DIR="dist"

echo "Building $APP_NAME v$VERSION..."

# Build release
flutter build macos --release

mkdir -p "$DIST_DIR"

# Create DMG
create-dmg \
  --volname "$APP_NAME $VERSION" \
  --volicon "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 190 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 425 190 \
  "$DIST_DIR/$APP_NAME-$VERSION.dmg" \
  "$BUILD_DIR/$APP_NAME.app"

echo "✓ DMG created: $DIST_DIR/$APP_NAME-$VERSION.dmg"
