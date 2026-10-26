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
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
signature=$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)
printf '%s\n' "$signature" | /usr/bin/grep -q 'Signature=adhoc'

