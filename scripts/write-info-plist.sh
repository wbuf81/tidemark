#!/bin/bash
# Usage: write-info-plist.sh <out-path> <version>
# Writes Tidemark's Info.plist with both version keys stamped from <version>.
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <out-path> <version>" >&2; exit 2; }
out="$1"; version="$2"
case "$version" in ''|*[!0-9A-Za-z.-]*) echo "bad version: $version" >&2; exit 2;; esac
cat > "$out" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Tidemark</string>
  <key>CFBundleDisplayName</key><string>Tidemark</string>
  <key>CFBundleIdentifier</key><string>io.github.wbuf81.tidemark</string>
  <key>CFBundleExecutable</key><string>Tidemark</string>
  <key>CFBundleIconFile</key><string>Tidemark</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>NSHumanReadableCopyright</key><string>Public domain (the Unlicense). No rights reserved.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
