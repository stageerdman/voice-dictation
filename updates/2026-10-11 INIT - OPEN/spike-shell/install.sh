#!/bin/bash
# Build and install the dev app into /Applications, signed with the stable
# self-signed identity so macOS permission grants (Accessibility / Input
# Monitoring / Microphone) persist across rebuilds. Grant permissions ONCE to
# "Voice Dictation Dev.app"; rebuild freely after that.
#
# One-time prerequisite: ./create-signing-identity.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Voice Dictation Dev"
DEST="/Applications/$APP_NAME.app"
IDENTITY="Voice Dictation Dev"

swift build -c release

# Quit any running copy so we can replace the bundle.
pkill -f "$DEST/Contents/MacOS/ShellSpike" 2>/dev/null || true

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
cp .build/release/ShellSpike "$DEST/Contents/MacOS/ShellSpike"
cp Info.plist "$DEST/Contents/Info.plist"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$DEST"
    echo "Signed with stable identity '$IDENTITY' — grants persist across rebuilds."
else
    codesign --force --sign - "$DEST"
    echo "WARNING: identity '$IDENTITY' not found; signed ad-hoc (grants reset on"
    echo "         each rebuild). Run ./create-signing-identity.sh first."
fi

echo "Installed → $DEST"
