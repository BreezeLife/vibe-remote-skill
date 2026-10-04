#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Vibe Remote requires macOS 13+ and Xcode Command Line Tools." >&2
    exit 1
fi

VIBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIBE_PACKAGE="$VIBE_ROOT/apps/macos"
VIBE_APP="$VIBE_ROOT/build/Vibe Remote.app"

swift build --package-path "$VIBE_PACKAGE" --configuration release --disable-sandbox
VIBE_BIN="$(swift build --package-path "$VIBE_PACKAGE" --configuration release --show-bin-path --disable-sandbox)"
mkdir -p "$VIBE_APP/Contents/MacOS" "$VIBE_APP/Contents/Resources"
install -m 755 "$VIBE_BIN/VibeRemote" "$VIBE_APP/Contents/MacOS/VibeRemote"
cp "$VIBE_PACKAGE/Packaging/Info.plist" "$VIBE_APP/Contents/Info.plist"
cp "$VIBE_ROOT/LICENSE" "$VIBE_APP/Contents/Resources/LICENSE.txt"
cp "$VIBE_PACKAGE/THIRD_PARTY_NOTICES.md" "$VIBE_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
plutil -lint "$VIBE_APP/Contents/Info.plist"
# Cloud-synced build directories may attach Finder metadata to the generated
# bundle. Remove only the two metadata classes codesign forbids; do not clear
# quarantine, provenance or other attributes, and never touch the source tree.
xattr -dr com.apple.FinderInfo "$VIBE_APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$VIBE_APP" 2>/dev/null || true
codesign --force --sign - --identifier io.github.BreezeLife.VibeRemote "$VIBE_APP"
codesign --verify --strict --verbose=2 "$VIBE_APP"
printf 'Built: %s\n' "$VIBE_APP"
printf 'Open: open "%s"\n' "$VIBE_APP"
