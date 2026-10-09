#!/usr/bin/env bash
set -euo pipefail
catalog_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
catalog_dir="$(mktemp -d "${TMPDIR:-/tmp}/viberemote-catalog-checks.XXXXXX")"
trap 'rm -rf "$catalog_dir"' EXIT
catalog_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/viberemote-catalog-module-cache}"
catalog_target="$(uname -m)-apple-macosx13.0"
swiftc -swift-version 5 -target "$catalog_target" -emit-library -emit-module -module-name VibeRemoteCore \
  -module-cache-path "$catalog_cache" "$catalog_root/apps/macos/Sources/VibeRemoteCore"/*.swift \
  -emit-module-path "$catalog_dir/VibeRemoteCore.swiftmodule" -o "$catalog_dir/libVibeRemoteCore.dylib"
swiftc -swift-version 5 -target "$catalog_target" -parse-as-library -module-cache-path "$catalog_cache" \
  -I "$catalog_dir" -L "$catalog_dir" -lVibeRemoteCore -Xlinker -rpath -Xlinker "$catalog_dir" \
  "$catalog_root/apps/macos/Sources/VibeRemote/CodexConversationCatalogService.swift" \
  "$catalog_root/apps/macos/Tests/CodexCatalogChecks.swift" -o "$catalog_dir/CodexCatalogChecks"
# Creates a temporary fake .app and speaks JSONL to its test executable only.
"$catalog_dir/CodexCatalogChecks"
