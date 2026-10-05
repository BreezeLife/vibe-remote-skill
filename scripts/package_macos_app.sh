#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "Vibe Remote packaging requires macOS and Xcode Command Line Tools." >&2
    exit 1
fi

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_resources="$package_root/apps/macos/Packaging"
package_output="${VIBE_PACKAGE_OUTPUT_DIR:-$package_root/build/packages}"
package_version="$(plutil -extract CFBundleShortVersionString raw "$package_resources/Info.plist")"
package_min_os="$(plutil -extract LSMinimumSystemVersion raw "$package_resources/Info.plist")"
package_arch="$(uname -m)"
if [[ ! "$package_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
   [[ ! "$package_min_os" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
   [[ "$package_arch" != arm64 && "$package_arch" != x86_64 ]]; then
    echo "Unsupported version, minimum macOS version or build architecture." >&2
    exit 1
fi
package_name="VibeRemote-$package_version-$package_arch.pkg"
mkdir -p "$package_output"
package_output="$(cd "$package_output" && pwd)"
if [[ -e "$package_output/$package_name" || -L "$package_output/$package_name" ||
      -e "$package_output/$package_name.sha256" || -L "$package_output/$package_name.sha256" ]]; then
    echo "Package already exists; choose a different VIBE_PACKAGE_OUTPUT_DIR: $package_output" >&2
    exit 1
fi

# Never stage signed bundles inside an iCloud/File Provider checkout.
package_stage="$(mktemp -d /private/tmp/vibe-remote-package.XXXXXX)"
trap 'rm -rf "$package_stage"' EXIT
VIBE_OUTPUT_DIR="$package_stage/payload" bash "$package_root/scripts/build_macos_app.sh"
package_app="$package_stage/payload/Vibe Remote.app"
if [[ "$(lipo -archs "$package_app/Contents/MacOS/VibeRemote")" != "$package_arch" ]]; then
    echo "The built binary does not match the installer architecture." >&2
    exit 1
fi

# In a current-user domain /Applications resolves under that user's home.
# Disable relocation so LaunchServices cannot choose an old cloud-workspace copy.
pkgbuild --root "$package_stage/payload" \
    --component-plist "$package_resources/InstallerComponents.plist" \
    --identifier io.github.BreezeLife.VibeRemote.installer \
    --version "$package_version" --install-location /Applications \
    "$package_stage/VibeRemote-component.pkg"
sed -e "s/@VERSION@/$package_version/g" \
    -e "s/@ARCH@/$package_arch/g" \
    -e "s/@MIN_OS@/$package_min_os/g" \
    "$package_resources/Distribution.xml.in" > "$package_stage/Distribution.xml"
productbuild --distribution "$package_stage/Distribution.xml" \
    --resources "$package_resources/InstallerResources" \
    --package-path "$package_stage" "$package_stage/$package_name"

# Install only via the product archive, whose domains exclude system-wide paths.
package_domains="$(installer -dominfo -pkg "$package_stage/$package_name")"
if [[ "$package_domains" != CurrentUserHomeDirectory ]]; then
    printf 'Unexpected installation domains: %s\n' "$package_domains" >&2
    exit 1
fi
pkgutil --expand-full "$package_stage/$package_name" "$package_stage/verify"
codesign --verify --strict --verbose=2 \
    "$package_stage/verify/VibeRemote-component.pkg/Payload/Vibe Remote.app"
cp "$package_stage/$package_name" "$package_output/$package_name"
(cd "$package_output" && shasum -a 256 "$package_name" > "$package_name.sha256")
printf 'Package: %s\n' "$package_output/$package_name"
printf 'Checksum: %s\n' "$package_output/$package_name.sha256"
printf 'Install: installer -pkg "%s" -target CurrentUserHomeDirectory\n' "$package_output/$package_name"
printf 'Development package: app is ad-hoc signed; installer is unsigned and not notarized.\n'
