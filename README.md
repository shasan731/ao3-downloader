# AO3 Downloader for macOS

A private, local-first SwiftUI app for downloading public Archive of Our Own works in AO3's own EPUB, PDF, or HTML formats. It is unofficial and is not affiliated with AO3 or the Organization for Transformative Works.

## Current build

The first implementation supports strict work/chapter URL normalization, work previews, discovery of links from the page's Download menu, globally serialized/courteous requests, validated complete-work downloads, safe filenames, and auto-renaming. See [implementation status](docs/IMPLEMENTATION_STATUS.md) for important gaps.

No Xcode or compiler is required locally. GitHub Actions is the build and test authority:

1. Commit and push this repository to `main`.
2. Open GitHub → Actions → **Build, Test and Package** and select the pushed run.
3. Wait for the green build. Under **Artifacts**, download `AO3Downloader-<commit>`.
4. Verify `SHA256SUMS.txt`, then open the ZIP or DMG and move the app to Applications.
5. This build has an ad-hoc integrity signature but is not Developer ID signed or notarized. After the first blocked launch, open **System Settings → Privacy & Security**, scroll to Security, and use **Open Anyway** only if you trust this repository and verified the checksum. Do not disable Gatekeeper globally.

If CI fails, download `test-diagnostics-<commit>` and inspect the failing step and `.xcresult`. The project intentionally prohibits live AO3 requests in automated tests.

## Privacy and responsible use

The app has no telemetry, account system, cloud backend, password collection, CAPTCHA bypass, mirror fallback, or site-wide crawler. Only URLs supplied by the user are requested. The default request interval is 15 seconds and requests are serialized for their entire lifecycle; this is a conservative application default, not an AO3-published safe quota.

MIT licensed. SwiftSoup (MIT) and ZIPFoundation (MIT) versions are pinned in `project.yml`.

