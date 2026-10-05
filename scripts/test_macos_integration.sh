#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Controls integration checks require macOS." >&2
    exit 2
fi

integration_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
integration_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-integration-checks.XXXXXX")"
trap 'rm -rf "$integration_check_dir"' EXIT
integration_core="$integration_project_root/apps/macos/Sources/VibeRemoteCore"
integration_app="$integration_project_root/apps/macos/Sources/VibeRemote"
integration_module_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-speech-module-cache}"
integration_target="$(uname -m)-apple-macosx13.0"

swiftc -swift-version 5 -target "$integration_target" \
    -emit-library -emit-module -module-name VibeRemoteCore \
    -module-cache-path "$integration_module_cache" "$integration_core"/*.swift \
    -emit-module-path "$integration_check_dir/VibeRemoteCore.swiftmodule" \
    -o "$integration_check_dir/libVibeRemoteCore.dylib"

# Compile the actual coordinator, store, HID, tool and voice services; instantiate
# only injected fake services. SwiftUI's application entry point is excluded.
swiftc -swift-version 5 -target "$integration_target" \
    -module-cache-path "$integration_module_cache" \
    -framework AppKit -framework Combine -framework CoreBluetooth -framework IOKit \
    -framework AVFoundation -framework Speech -framework ApplicationServices -framework CoreAudio \
    -I "$integration_check_dir" -L "$integration_check_dir" -lVibeRemoteCore \
    -Xlinker -rpath -Xlinker "$integration_check_dir" \
    "$integration_app/RemoteServices.swift" "$integration_app/RemoteModel.swift" \
    "$integration_app/SpeechService.swift" "$integration_app/BluetoothService.swift" \
    "$integration_app/NativeSettingsStore.swift" "$integration_app/HIDRemoteInputService.swift" \
    "$integration_app/ToolAdapter.swift" "$integration_app/SystemVolume.swift" \
    "$integration_app/ControlsModel.swift" \
    "$integration_project_root/apps/macos/Tests/ControlsIntegrationChecks.swift" \
    -o "$integration_check_dir/ControlsIntegrationChecks"
"$integration_check_dir/ControlsIntegrationChecks"
