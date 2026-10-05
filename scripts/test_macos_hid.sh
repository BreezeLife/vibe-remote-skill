#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "HID input checks require macOS." >&2
    exit 2
fi

hid_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
hid_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-hid-checks.XXXXXX")"
trap 'rm -rf "$hid_check_dir"' EXIT
hid_core="$hid_project_root/apps/macos/Sources/VibeRemoteCore"
hid_module_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-hid-module-cache}"
hid_target="$(uname -m)-apple-macosx13.0"

# Compile the real IOKit adapter; run only the injected fake driver. No permission
# request, HID enumeration/open, keyboard capture, device seizure or GUI is used.
swiftc -swift-version 5 -target "$hid_target" \
    -emit-library -emit-module -module-name VibeRemoteCore \
    -module-cache-path "$hid_module_cache" \
    "$hid_core"/*.swift \
    -emit-module-path "$hid_check_dir/VibeRemoteCore.swiftmodule" \
    -o "$hid_check_dir/libVibeRemoteCore.dylib"

cp "$hid_project_root/apps/macos/Tests/HIDInputChecks.swift" "$hid_check_dir/main.swift"
swiftc -swift-version 5 -target "$hid_target" \
    -module-cache-path "$hid_module_cache" \
    -framework AppKit -framework Combine -framework IOKit \
    -I "$hid_check_dir" -L "$hid_check_dir" -lVibeRemoteCore \
    -Xlinker -rpath -Xlinker "$hid_check_dir" \
    "$hid_project_root/apps/macos/Sources/VibeRemote/HIDRemoteInputService.swift" \
    "$hid_check_dir/main.swift" -o "$hid_check_dir/HIDInputChecks"
"$hid_check_dir/HIDInputChecks"
