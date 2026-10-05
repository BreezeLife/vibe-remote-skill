#!/usr/bin/env bash
set -euo pipefail
controls_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
controls_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibe-controls-tests.XXXXXX")"
trap 'rm -rf "$controls_dir"' EXIT
controls_cache="${TMPDIR:-/tmp}/vibe-controls-module-cache"
swiftc -swift-version 5 -emit-library -emit-module -module-name VibeRemoteCore \
  -module-cache-path "$controls_cache" "$controls_root/apps/macos/Sources/VibeRemoteCore/"*.swift \
  -emit-module-path "$controls_dir/VibeRemoteCore.swiftmodule" -o "$controls_dir/libVibeRemoteCore.dylib"
cp "$controls_root/apps/macos/Tests/ControlsChecks.swift" "$controls_dir/main.swift"
swiftc -swift-version 5 -module-cache-path "$controls_cache" \
  -I "$controls_dir" -L "$controls_dir" -lVibeRemoteCore -Xlinker -rpath -Xlinker "$controls_dir" \
  "$controls_root/apps/macos/Sources/VibeRemote/NativeSettingsStore.swift" \
  "$controls_dir/main.swift" -o "$controls_dir/checks"
"$controls_dir/checks"
