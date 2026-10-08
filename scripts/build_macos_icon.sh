#!/bin/bash
set -euo pipefail

# Mechanical format conversion only; keep the generated artwork and its alpha.
icon_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
icon_source="$icon_root/apps/macos/Packaging/Artwork/AppIcon.png"
icon_output="$icon_root/apps/macos/Packaging/AppIcon.icns"
icon_stage="$(mktemp -d /private/tmp/vibe-remote-icon.XXXXXX)"
trap 'rm -rf "$icon_stage"' EXIT
mkdir "$icon_stage/AppIcon.iconset"
for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" "$icon_source" \
        --out "$icon_stage/AppIcon.iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
    icon_retina=$((icon_size * 2))
    sips -z "$icon_retina" "$icon_retina" "$icon_source" \
        --out "$icon_stage/AppIcon.iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_stage/AppIcon.iconset" -o "$icon_output"
printf 'Icon: %s\n' "$icon_output"
