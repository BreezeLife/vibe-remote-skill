#!/usr/bin/env bash
set -euo pipefail
provider_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
provider_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibe-provider-app-tests.XXXXXX")"
trap 'rm -rf "$provider_dir"' EXIT
provider_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/vibe-provider-app-module-cache}"
provider_target="$(uname -m)-apple-macosx13.0"
swiftc -swift-version 5 -target "$provider_target" -emit-library -emit-module -module-name VibeRemoteCore \
  -module-cache-path "$provider_cache" "$provider_root/apps/macos/Sources/VibeRemoteCore/"*.swift \
  -emit-module-path "$provider_dir/VibeRemoteCore.swiftmodule" -o "$provider_dir/libVibeRemoteCore.dylib"
cp "$provider_root/apps/macos/Tests/VoiceProviderAppsChecks.swift" "$provider_dir/main.swift"
swiftc -swift-version 5 -target "$provider_target" -module-cache-path "$provider_cache" \
  -I "$provider_dir" -L "$provider_dir" -lVibeRemoteCore -Xlinker -rpath -Xlinker "$provider_dir" \
  "$provider_root/apps/macos/Sources/VibeRemote/VoiceProviderApps.swift" \
  "$provider_dir/main.swift" -o "$provider_dir/checks"
# Only temporary fixture bundles are read. No app, shortcut or microphone is opened.
"$provider_dir/checks"
