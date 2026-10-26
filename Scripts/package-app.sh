#!/bin/bash
set -euo pipefail
app="${1:?app path required}"
output="${2:?output directory required}"
mkdir -p "$output"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$output/AO3Downloader-macOS-arm64.zip"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$app" "$stage/AO3Downloader.app"
ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create -volname "AO3 Downloader" -srcfolder "$stage" -ov -format UDZO "$output/AO3Downloader-macOS-arm64.dmg"
(cd "$output" && /usr/bin/shasum -a 256 AO3Downloader-macOS-arm64.zip AO3Downloader-macOS-arm64.dmg > SHA256SUMS.txt)

