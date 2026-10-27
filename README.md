# AO3 Downloader for macOS

A private, local-first SwiftUI app for downloading public Archive of Our Own works in AO3's own EPUB, PDF, or HTML formats. It is unofficial and is not affiliated with AO3 or the Organization for Transformative Works.

## Current build

The current implementation supports strict work/chapter/series URL normalization, work and ordered selectable series previews, persistent cross-navigation analysis/download tasks with live progress, discovery of links from each work's Download menu, globally serialized/courteous requests, server-directed and relaunch-safe cooldowns, validated complete-work downloads, separate or combined EPUB/PDF series output, safe filenames, partial/cancellation reports, and auto-renaming. Combined books include designed title/contents pages and hierarchical Series → Book/Story → Chapter navigation with internal links; PDFs also include page numbers and reader bookmarks. Multi-chapter series parts are downloaded as AO3's complete-work files. An explicit preference supports AO3's public Mature/Explicit warning flow and validates AO3's same-work redirect to the first chapter. Its recoverable durable Library keeps verified series parts for individual or bulk retry, live reselection, custom-metadata recombination, and later reanalysis to discover/download only new or missing parts. See [implementation status](docs/IMPLEMENTATION_STATUS.md) for important gaps.

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

