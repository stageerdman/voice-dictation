#!/bin/bash
# Build "Voice Dictator" and install it as an ad-hoc-signed .app in /Applications,
# with the app icon and the Python transcription sidecar embedded in Resources.
# Ad-hoc signing means no keychain/certificate setup; the only cost is re-granting
# Microphone/Accessibility after a rebuild (the signature changes each build, so
# macOS resets the grants). Iterate with just `./scripts/install.sh`.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Voice Dictator"
DEST="/Applications/$APP_NAME.app"
EXECUTABLE="VoiceDictation"

echo "Building release…"
swift build -c release --product "$EXECUTABLE"

BIN=".build/release/$EXECUTABLE"

# Quit any running copy so we can replace the bundle.
pkill -f "$DEST/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
# Clean up the earlier dev-named bundle so there aren't two copies in /Applications.
pkill -f "/Applications/Voice Dictation Dev.app/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
rm -rf "/Applications/Voice Dictation Dev.app"

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/$EXECUTABLE"
cp Info.plist "$DEST/Contents/Info.plist"
# App icon (shown in Finder / Applications). Built by scripts/make-icon.sh.
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$DEST/Contents/Resources/AppIcon.icns"
else
    echo "⚠️  Resources/AppIcon.icns missing — run scripts/make-icon.sh first."
fi
# Embed the transcription sidecar so a shipped build is self-contained.
cp -R sidecar "$DEST/Contents/Resources/sidecar"

# Ad-hoc sign: no keychain, no prompt, instant. TCC attaches permissions to the
# signature, which changes each build — so grant Microphone/Accessibility once
# per rebuild (the Log view + launch self-check show when a grant is missing).
codesign --force --sign - "$DEST"

echo "Installed → $DEST"
echo "Note: after a rebuild, re-grant Accessibility & Microphone to \"$APP_NAME\" once."
