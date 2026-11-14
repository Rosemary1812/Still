#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 scripts/generate_project.py
album_info="$(mktemp /tmp/contact-sheet-albums.XXXXXX.plist)"
trap 'rm -f "$album_info"' EXIT
python3 - "$album_info" <<'PY'
import plistlib,sys
from pathlib import Path
info=plistlib.loads(Path('Info.plist').read_bytes())
info.update(CFBundleIdentifier='local.contact-sheet.albums-development',CFBundleName='Contact Sheet 相册开发版',CFBundleDisplayName='Contact Sheet 相册开发版',CFBundleShortVersionString='0.3.0',CFBundleVersion='3')
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
PY
xcodebuild -project ContactSheet.xcodeproj -target ContactSheet -configuration Debug \
  SYMROOT="$PWD/build-albums" \
  INFOPLIST_FILE="$album_info" \
  PRODUCT_BUNDLE_IDENTIFIER=local.contact-sheet.albums-development build
printf '\nApp: %s/build-albums/Debug/Contact Sheet.app\n' "$PWD"
