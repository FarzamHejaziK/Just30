#!/bin/bash
set -euo pipefail
oneway_root="$(cd "$(dirname "$0")" && pwd)"
"$oneway_root/build.sh"
oneway_destination="/Applications/OneWay.app"
# In-place app updates do not touch the root-owned block list or network rules.
ditto "$oneway_root/.build/OneWay.app" "$oneway_destination"
codesign --verify --deep --strict "$oneway_destination"
open "$oneway_destination"
