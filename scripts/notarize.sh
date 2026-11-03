#!/usr/bin/env bash
# VibeRadar notarization script
# Usage: ./scripts/notarize.sh <path-to-dmg> <apple-id> <team-id>
# Requires: Xcode + Apple Developer account
set -e

DMG_PATH="$1"
APPLE_ID="$2"
TEAM_ID="$3"

if [ -z "$DMG_PATH" ] || [ -z "$APPLE_ID" ] || [ -z "$TEAM_ID" ]; then
  echo "Usage: ./scripts/notarize.sh <dmg-path> <apple-id> <team-id>"
  exit 1
fi

echo "Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "✓ Notarization complete"
