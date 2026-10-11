#!/usr/bin/env bash
set -euo pipefail
focused_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
focused_dir="$(mktemp -d "${TMPDIR:-/tmp}/vibe-focused-input-tests.XXXXXX")"
trap 'rm -rf "$focused_dir"' EXIT
focused_cache="${VIBE_REMOTE_SWIFT_MODULE_CACHE:-${TMPDIR:-/tmp}/vibe-focused-input-module-cache}"
focused_target="$(uname -m)-apple-macosx13.0"
cp "$focused_root/apps/macos/Tests/FocusedInputChecks.swift" "$focused_dir/main.swift"
swiftc -swift-version 5 -target "$focused_target" -module-cache-path "$focused_cache" \
  "$focused_root/apps/macos/Sources/VibeRemote/FocusedInputService.swift" \
  "$focused_dir/main.swift" -o "$focused_dir/checks"
# Fake observations and writes only. Never inspect or mutate another application's real UI.
"$focused_dir/checks"
