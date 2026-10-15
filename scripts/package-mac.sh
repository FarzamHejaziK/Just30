#!/bin/bash
set -euo pipefail
release_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="$release_root/.build/release/mac"
release_app="$release_root/OneWayMac/.build/JustThirty.app"
release_profile="${1:-}"
mkdir -p "$release_dir"
"$release_root/OneWayMac/build.sh"
codesign --verify --deep --strict "$release_app"
release_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$release_app/Contents/Info.plist")"
release_stage="$(mktemp -d "$release_dir/staging.XXXXXX")"
trap 'rm -rf "$release_stage"' EXIT
if [[ -n "$release_profile" ]]; then
  ditto -c -k --keepParent "$release_app" "$release_dir/JustThirty-upload.zip"
  xcrun notarytool submit "$release_dir/JustThirty-upload.zip" --keychain-profile "$release_profile" --wait --output-format json > "$release_dir/notarization.json"
  python3 - "$release_dir/notarization.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('status')!='Accepted': raise SystemExit('Notarization was not accepted. Do not distribute this build.')
PY
  xcrun stapler staple "$release_app"
  xcrun stapler validate "$release_app"
  spctl --assess --type execute --verbose=2 "$release_app"
  release_dmg="$release_dir/JustThirty-$release_version.dmg"
else
  release_dmg="$release_dir/JustThirty-$release_version-unnotarized.dmg"
fi
ditto "$release_app" "$release_stage/JustThirty.app"
ln -s /Applications "$release_stage/Applications"
cp "$release_root/release/mac/READ-ME-FIRST.txt" "$release_stage/Read me first.txt"
hdiutil create -volname JustThirty -srcfolder "$release_stage" -ov -format UDZO "$release_dmg"
if [[ -n "$release_profile" ]]; then
  # Notarize the disk image too, so its own Gatekeeper assessment is verified.
  xcrun notarytool submit "$release_dmg" --keychain-profile "$release_profile" --wait --output-format json > "$release_dir/dmg-notarization.json"
  python3 - "$release_dir/dmg-notarization.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status')!='Accepted': raise SystemExit('Disk image notarization was not accepted.')
PY
  xcrun stapler staple "$release_dmg"
  xcrun stapler validate "$release_dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$release_dmg"
  shasum -a 256 "$release_dmg" > "$release_dmg.sha256"
  echo "Verified distribution package: $release_dmg"
else
  echo "Package prepared: $release_dmg"
  echo 'NOT READY FOR PUBLIC DOWNLOAD: configure a notarytool Keychain profile, then run this script with that profile name.'
fi
