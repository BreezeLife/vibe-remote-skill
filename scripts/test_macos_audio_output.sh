#!/usr/bin/env bash
set -euo pipefail
audio_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
audio_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-output-checks.XXXXXX")"
trap 'rm -rf "$audio_check_dir"' EXIT
# Pure PCM/ring/resolver fixtures and an injected empty inventory. Never starts real audio.
cp "$audio_root/apps/macos/Tests/RemoteAudioOutputChecks.swift" "$audio_check_dir/main.swift"
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-output-module-cache}" \
    -framework AVFoundation -framework Speech -framework CoreAudio -framework AudioToolbox \
    "$audio_root/apps/macos/Sources/VibeRemote/SpeechService.swift" \
    "$audio_root/apps/macos/Sources/VibeRemote/RemoteAudioOutput.swift" \
    "$audio_check_dir/main.swift" -o "$audio_check_dir/AudioOutputChecks"
"$audio_check_dir/AudioOutputChecks"
