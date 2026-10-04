#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Speech PCM checks require macOS." >&2
    exit 2
fi

speech_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
speech_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-speech-checks.XXXXXX")"
trap 'rm -rf "$speech_check_dir"' EXIT

# No recognizer is created and no permission request is made by these checks.
# Build as a standalone executable so Command Line Tools can run them without XCTest.
cp "$speech_project_root/apps/macos/Tests/SpeechChecks.swift" "$speech_check_dir/main.swift"
swiftc -swift-version 5 \
    -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-speech-module-cache}" \
    -framework AVFoundation -framework Speech \
    "$speech_project_root/apps/macos/Sources/VibeRemote/SpeechService.swift" \
    "$speech_check_dir/main.swift" \
    -o "$speech_check_dir/SpeechChecks"
"$speech_check_dir/SpeechChecks"
