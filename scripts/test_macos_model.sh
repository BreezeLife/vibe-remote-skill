#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Remote model checks require macOS." >&2
    exit 2
fi

model_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
model_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-model-checks.XXXXXX")"
trap 'rm -rf "$model_check_dir"' EXIT
model_core="$model_project_root/apps/macos/Sources/VibeRemoteCore"
model_app="$model_project_root/apps/macos/Sources/VibeRemote"
model_module_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-speech-module-cache}"
model_target="$(uname -m)-apple-macosx13.0"

# Compile actual model/services, but inject only fakes in the test executable.
# No real Bluetooth central, speech recognizer, permission dialog or GUI is used.
swiftc -swift-version 5 -target "$model_target" \
    -emit-library -emit-module -module-name VibeRemoteCore \
    -module-cache-path "$model_module_cache" \
    "$model_core"/*.swift \
    -emit-module-path "$model_check_dir/VibeRemoteCore.swiftmodule" \
    -o "$model_check_dir/libVibeRemoteCore.dylib"

cp "$model_project_root/apps/macos/Tests/RemoteModelChecks.swift" "$model_check_dir/main.swift"
swiftc -swift-version 5 -target "$model_target" \
    -module-cache-path "$model_module_cache" \
    -framework AppKit -framework Combine -framework CoreBluetooth \
    -framework AVFoundation -framework Speech \
    -I "$model_check_dir" -L "$model_check_dir" -lVibeRemoteCore \
    -Xlinker -rpath -Xlinker "$model_check_dir" \
    "$model_app/RemoteServices.swift" "$model_app/RemoteModel.swift" \
    "$model_app/SpeechService.swift" "$model_app/BluetoothService.swift" \
    "$model_check_dir/main.swift" -o "$model_check_dir/RemoteModelChecks"
"$model_check_dir/RemoteModelChecks"
