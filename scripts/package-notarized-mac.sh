#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo 'Usage: ./scripts/package-notarized-mac.sh /absolute/path/to/JustThirty.app' >&2
  exit 2
fi
release_root="$(cd "$(dirname "$0")/.." && pwd)"
release_app="$1"
[[ -d "$release_app/Contents" ]] || { echo 'A complete exported app bundle is required.' >&2; exit 2; }
# This route packages Xcode's notarized export without rebuilding or re-signing
# it, which would invalidate the accepted code identity and staple.
codesign --verify --deep --strict "$release_app"
xcrun stapler validate "$release_app"
spctl --assess --type execute --verbose=2 "$release_app"
release_archs="$(lipo -archs "$release_app/Contents/MacOS/OneWayMac")"
[[ "$release_archs" == *arm64* && "$release_archs" == *x86_64* ]] || { echo 'Both Mac architectures are required.' >&2; exit 1; }
release_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$release_app/Contents/Info.plist")"
release_dir="$release_root/.build/release/mac"
mkdir -p "$release_dir"
release_zip="$release_dir/JustThirty-$release_version.zip"
ditto -c -k --keepParent "$release_app" "$release_zip"
(cd "$release_dir" && shasum -a 256 "$(basename "$release_zip")") > "$release_zip.sha256"
echo "Verified notarized Mac package: $release_zip"
