#!/bin/bash
set -euo pipefail
app="${1:?app path required}"
output="${2:?output directory required}"
mkdir -p "$output"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$app" "$stage/ArchiveBind.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$stage/ArchiveBind.app" "$output/ArchiveBind-macOS-arm64.zip"
ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create -volname "ArchiveBind" -srcfolder "$stage" -ov -format UDZO "$output/ArchiveBind-macOS-arm64.dmg"
(cd "$output" && /usr/bin/shasum -a 256 ArchiveBind-macOS-arm64.zip ArchiveBind-macOS-arm64.dmg > SHA256SUMS.txt)

