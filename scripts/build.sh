#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 scripts/generate_project.py
xcodebuild -project ContactSheet.xcodeproj -target ContactSheet -configuration Debug SYMROOT="$PWD/build" build
printf '\nApp: %s/build/Debug/Still.app\n' "$PWD"
