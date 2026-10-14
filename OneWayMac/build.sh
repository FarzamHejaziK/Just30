#!/bin/bash
set -euo pipefail
oneway_root="$(cd "$(dirname "$0")" && pwd)"
oneway_build="$oneway_root/.build"
oneway_unsigned=false
if [[ "${1:-}" == "--unsigned" && $# -eq 1 ]]; then
    oneway_unsigned=true
    oneway_build="$oneway_build/unsigned"
elif [[ $# -ne 0 ]]; then
    echo 'Usage: ./build.sh [--unsigned]' >&2
    exit 2
fi
oneway_app="$oneway_build/OneWay.app"
# Recreate only generated output so old identities/plists cannot leak into a build.
rm -rf "$oneway_app"
mkdir -p "$oneway_app/Contents/MacOS" "$oneway_app/Contents/Resources" \
    "$oneway_app/Contents/Library/HelperTools" "$oneway_app/Contents/Library/LaunchDaemons"
if $oneway_unsigned; then
    python3 "$oneway_root/prepare-build.py" --build "$oneway_build" --unsigned
else
    python3 "$oneway_root/prepare-build.py" --build "$oneway_build"
fi
oneway_identity="$(cat "$oneway_build/generated/signing-identity")"
oneway_helper_id="$(cat "$oneway_build/generated/helper-identifier")"
oneway_shared="$oneway_root/../OneWay/OneWay/BlockList.swift"
oneway_sources="$oneway_root/Sources"
oneway_sdk="$(xcrun --sdk macosx --show-sdk-path)"

xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -sdk "$oneway_sdk" -D ONEWAY_CONFIGURED_BUILD \
    "$oneway_build/generated/BuildIdentity.swift" \
    "$oneway_shared" "$oneway_sources/Core.swift" "$oneway_sources/Protocol.swift" \
    "$oneway_sources/Enforcement.swift" "$oneway_sources/Helper.swift" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$oneway_build/generated/HelperInfo.plist" \
    -o "$oneway_app/Contents/Library/HelperTools/OneWayHelper"
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -sdk "$oneway_sdk" -D ONEWAY_CONFIGURED_BUILD \
    "$oneway_build/generated/BuildIdentity.swift" \
    "$oneway_shared" "$oneway_sources/Core.swift" "$oneway_sources/Protocol.swift" \
    "$oneway_sources/AppModel.swift" "$oneway_sources/App.swift" \
    -o "$oneway_app/Contents/MacOS/OneWayMac"

oneway_icon="$oneway_build/AppIcon.iconset"
mkdir -p "$oneway_icon"
for oneway_size in 16 32 128 256 512; do
    sips -z "$oneway_size" "$oneway_size" "$oneway_root/../OneWay/OneWay/Assets.xcassets/AppIcon.appiconset/AppIcon.png" \
        --out "$oneway_icon/icon_${oneway_size}x${oneway_size}.png" >/dev/null
    oneway_double=$((oneway_size * 2))
    sips -z "$oneway_double" "$oneway_double" "$oneway_root/../OneWay/OneWay/Assets.xcassets/AppIcon.appiconset/AppIcon.png" \
        --out "$oneway_icon/icon_${oneway_size}x${oneway_size}@2x.png" >/dev/null
done
iconutil -c icns "$oneway_icon" -o "$oneway_app/Contents/Resources/AppIcon.icns"
oneway_sign_flags=(--force --options runtime --sign "$oneway_identity")
if $oneway_unsigned; then oneway_sign_flags+=(--timestamp=none); else oneway_sign_flags+=(--timestamp); fi
codesign "${oneway_sign_flags[@]}" --identifier "$oneway_helper_id" "$oneway_app/Contents/Library/HelperTools/OneWayHelper"
codesign "${oneway_sign_flags[@]}" "$oneway_app"
codesign --verify --deep --strict --verbose=2 "$oneway_app"
echo "Built and signed: $oneway_app"
if $oneway_unsigned; then echo 'Ad-hoc preview only: background-service authentication requires a Developer ID build.'; fi
