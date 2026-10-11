#!/usr/bin/env bash
set -euo pipefail
external_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
external_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibe-external-checks.XXXXXX")"
trap 'rm -rf "$external_dir"' EXIT
external_app="$external_root/apps/macos/Sources/VibeRemote"
external_cache="${TMPDIR:-/tmp}/viberemote-speech-module-cache"
swiftc -swift-version 5 -emit-library -emit-module -module-name VibeRemoteCore \
  -module-cache-path "$external_cache" "$external_root/apps/macos/Sources/VibeRemoteCore/"*.swift \
  -emit-module-path "$external_dir/VibeRemoteCore.swiftmodule" -o "$external_dir/libVibeRemoteCore.dylib"
cp "$external_root/apps/macos/Tests/ExternalDictationChecks.swift" "$external_dir/main.swift"
swiftc -swift-version 5 -module-cache-path "$external_cache" \
  -I "$external_dir" -L "$external_dir" -lVibeRemoteCore -Xlinker -rpath -Xlinker "$external_dir" \
  "$external_app/RemoteServices.swift" "$external_app/BluetoothService.swift" \
  "$external_app/SpeechService.swift" "$external_app/RemoteAudioOutput.swift" \
  "$external_app/FocusedInputService.swift" \
  "$external_app/ExternalDictationController.swift" \
  "$external_dir/main.swift" -o "$external_dir/checks"
"$external_dir/checks"
