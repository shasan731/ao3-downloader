#!/bin/bash
set -euo pipefail
epub="${1:?EPUB path required}"
/usr/bin/unzip -t "$epub"
test "$(/usr/bin/unzip -p "$epub" mimetype)" = "application/epub+zip"
/usr/bin/unzip -l "$epub" | /usr/bin/grep -q 'META-INF/container.xml'

