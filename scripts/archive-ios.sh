#!/bin/bash
set -euo pipefail
release_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="$release_root/.build/release"
mkdir -p "$release_dir"
xcodebuild -project "$release_root/OneWay/OneWay.xcodeproj" -scheme OneWay \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$release_dir/JustThirty.xcarchive" -derivedDataPath "$release_root/OneWay/.build/Archive" \
  -allowProvisioningUpdates archive
cat > "$release_dir/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>method</key><string>app-store-connect</string><key>signingStyle</key><string>automatic</string><key>destination</key><string>export</string><key>manageAppVersionAndBuildNumber</key><false/></dict></plist>
PLIST
# Export cannot succeed until Apple assigns Family Controls for distribution to
# both the app and monitor. This command does not upload or submit the app.
xcodebuild -exportArchive -archivePath "$release_dir/JustThirty.xcarchive" \
  -exportOptionsPlist "$release_dir/ExportOptions.plist" -exportPath "$release_dir/AppStore" -allowProvisioningUpdates
