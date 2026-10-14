#!/bin/bash
set -euo pipefail
oneway_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$oneway_root/OneWay/.build"
xcrun swiftc "$oneway_root/OneWay/OneWay/BlockList.swift" "$oneway_root/OneWay/Tests/BlockListTests.swift" \
    -o "$oneway_root/OneWay/.build/block-list-tests"
"$oneway_root/OneWay/.build/block-list-tests"
"$oneway_root/OneWayMac/test.sh"
