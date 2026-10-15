#!/bin/bash
set -euo pipefail
oneway_root="$(cd "$(dirname "$0")" && pwd)"
oneway_fixture="$oneway_root/.build/OneWayTestFixture.app"
mkdir -p "$oneway_fixture/Contents/MacOS"
cat > "$oneway_fixture/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.OneWayTestFixture</string>
<key>CFBundleName</key><string>OneWay Test Fixture</string>
<key>CFBundleExecutable</key><string>fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun swiftc "$oneway_root/Tests/Fixture.swift" -o "$oneway_fixture/Contents/MacOS/fixture"
xcrun swiftc -swift-version 5 -parse-as-library \
    "$oneway_root/../Shared/DailyAllowance.swift" "$oneway_root/../Shared/AccessSession.swift" \
    "$oneway_root/../OneWay/OneWay/BlockList.swift" "$oneway_root/Sources/Core.swift" \
    "$oneway_root/Sources/Enforcement.swift" "$oneway_root/Tests/CoreTests.swift" \
    -o "$oneway_root/.build/core-tests"
"$oneway_root/.build/core-tests" "$oneway_fixture"
