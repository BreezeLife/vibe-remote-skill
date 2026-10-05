#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Tool adapter checks require macOS." >&2
    exit 2
fi
tool_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tool_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-tool-checks.XXXXXX")"
trap 'rm -rf "$tool_check_dir"' EXIT
tool_module_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-speech-module-cache}"
tool_target="$(uname -m)-apple-macosx13.0"
swiftc -swift-version 5 -target "$tool_target" -emit-library -emit-module -module-name VibeRemoteCore \
    -module-cache-path "$tool_module_cache" "$tool_project_root/apps/macos/Sources/VibeRemoteCore"/*.swift \
    -emit-module-path "$tool_check_dir/VibeRemoteCore.swiftmodule" -o "$tool_check_dir/libVibeRemoteCore.dylib"
cp "$tool_project_root/apps/macos/Tests/ToolAdapterChecks.swift" "$tool_check_dir/main.swift"
swiftc -swift-version 5 -target "$tool_target" -module-cache-path "$tool_module_cache" \
    -framework AppKit -framework ApplicationServices \
    -I "$tool_check_dir" -L "$tool_check_dir" -lVibeRemoteCore -Xlinker -rpath -Xlinker "$tool_check_dir" \
    "$tool_project_root/apps/macos/Sources/VibeRemote/ToolAdapter.swift" "$tool_check_dir/main.swift" \
    -o "$tool_check_dir/ToolAdapterChecks"
# This executable injects FakeToolAXDriver only; no app activation, AX/TCC or real UI reads.
"$tool_check_dir/ToolAdapterChecks"
