#!/bin/bash
set -euo pipefail
app="${1:?usage: verify-build.sh path/to/AO3Downloader.app}"
test -d "$app"
binary="$app/Contents/MacOS/AO3Downloader"
test -x "$binary"
/usr/bin/file "$binary" | /usr/bin/grep -q arm64
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
test "$bundle_id" = "com.shasan731.AO3Downloader"
/usr/bin/plutil -lint "$app/Contents/Info.plist"

