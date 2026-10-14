#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo 'Usage: ./install.sh <iPhone UDID>' >&2
    echo 'Find the paired phone with: xcrun devicectl list devices' >&2
    exit 2
fi

oneway_root="$(cd "$(dirname "$0")" && pwd)"
oneway_device="$1"
oneway_build="$oneway_root/.build/Xcode"

xcodebuild -project "$oneway_root/OneWay.xcodeproj" -scheme OneWay \
    -configuration Debug -destination "id=$oneway_device" \
    -derivedDataPath "$oneway_build" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# Updating in place preserves the existing add-only list. Never uninstall first.
xcrun devicectl device install app --device "$oneway_device" \
    "$oneway_build/Build/Products/Debug-iphoneos/OneWay.app"
oneway_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' \
    "$oneway_build/Build/Products/Debug-iphoneos/OneWay.app/Info.plist")"
xcrun devicectl device process launch --device "$oneway_device" "$oneway_bundle_id"
