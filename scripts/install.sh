#!/bin/bash
# Build Voice Dictation and install it as a signed .app in /Applications, with
# the Python transcription sidecar embedded in Resources. Signed with the stable
# "Voice Dictation Dev" identity so macOS permission grants (Microphone,
# Accessibility) persist across rebuilds. Grant permissions ONCE; then iterate
# with just `./scripts/install.sh`.
#
# One-time prerequisite: ./scripts/create-signing-identity.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Voice Dictation Dev"
DEST="/Applications/$APP_NAME.app"
EXECUTABLE="VoiceDictation"

echo "Building release…"
swift build -c release --product "$EXECUTABLE"

BIN=".build/release/$EXECUTABLE"

# Quit any running copy so we can replace the bundle.
pkill -f "$DEST/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/$EXECUTABLE"
cp Info.plist "$DEST/Contents/Info.plist"
# Embed the transcription sidecar so a shipped build is self-contained.
cp -R sidecar "$DEST/Contents/Resources/sidecar"

# Ad-hoc sign by default: no keychain, no prompt, instant. The only cost is
# re-granting Microphone/Accessibility after a rebuild — a fair trade for zero
# friction. Set VOICE_DICTATION_SIGN_IDENTITY to a keychain identity if you'd
# rather keep grants across rebuilds (needs that identity authorized for
# codesign, e.g. via `security set-key-partition-list`).
IDENTITY="${VOICE_DICTATION_SIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ] && security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$DEST"
    echo "Signed with identity '$IDENTITY' — grants persist across rebuilds."
else
    codesign --force --sign - "$DEST"
    echo "Ad-hoc signed (no keychain prompt)."
fi

echo "Installed → $DEST"
