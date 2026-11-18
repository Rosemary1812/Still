#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${IOS_SIMULATOR_ID:?Set IOS_SIMULATOR_ID to an available iPhone simulator UUID (xcrun simctl list devices available)}"
python3 scripts/generate_ios_project.py
xcrun simctl bootstatus "$IOS_SIMULATOR_ID" -b
xcrun simctl addmedia "$IOS_SIMULATOR_ID" previews/photo-albums/assets/photo-0.jpg
xcodebuild -project Still-iOS.xcodeproj -scheme StillIOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS_SIMULATOR_ID" -derivedDataPath build/ios \
  CODE_SIGNING_ALLOWED=NO test
