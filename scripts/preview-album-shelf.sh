#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
preview_root="$PWD"
preview_app="$PWD/.tools/Still Shelf Preview.app"
mkdir -p "$preview_app/Contents/MacOS"
cat > "$preview_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.still.shelf-preview</string>
<key>CFBundleExecutable</key><string>ShelfPreview</string>
<key>CFBundleName</key><string>Still Shelf Preview</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/ContactSheet/App.swift').read_text()
Path('.tools/ShelfPreviewSupport.swift').write_text('import SwiftUI\nimport AppKit\n' + source[source.index('final class AppDelegate'):])
PY
preview_sources=()
for source in Sources/ContactSheet/*.swift; do
  if [[ "$source" != "Sources/ContactSheet/App.swift" ]]; then preview_sources+=("$source"); fi
done
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "${preview_sources[@]}" .tools/ShelfPreviewSupport.swift scripts/preview-album-shelf.swift \
  -o "$preview_app/Contents/MacOS/ShelfPreview"
codesign --force --sign - "$preview_app"
STILL_PREVIEW_ROOT="$preview_root" "$preview_app/Contents/MacOS/ShelfPreview"
