# Implementation status

## Implemented and CI-verified

- Native macOS 14 SwiftUI navigation shell, work input/preview, folder chooser, format picker, open/reveal actions, Settings and About.
- Exact HTTPS host/path validation and chapter-to-work normalization.
- Public work metadata parsing with SwiftSoup and discovered official EPUB/PDF/HTML links.
- One in-flight AO3 request lifecycle globally, 15-second default spacing, cancellation-aware waiting.
- Status classification, challenge/restricted detection, bounded HTML reads, host-safe downloads.
- PDF/EPUB/HTML signatures and basic EPUB structure validation before safe, auto-renamed output.
- Bounded series pagination with cycle/host/path protection, author-order selection, sequential separate-file downloads, inaccessible-work visibility, and partial `download-report.json` output.
- Versioned atomic JSON persistence service and deterministic URL/parser/file/persistence tests.
- arm64 GitHub Actions test/build/ZIP/DMG/checksum pipeline and tag prerelease workflow.

## Not yet supported

- Durable per-work queue/recovery and pause/resume/cancel controls.
- Merged EPUB 3 and merged PDF output.
- Complete pause/resume/cancel/history UI and persisted security-scoped bookmarks.
- Full Retry-After parsing, escalation persistence, retries/offline monitoring, notifications.
- Developer ID signing and notarization. CI artifacts use an ad-hoc integrity signature only.

## Verification state

GitHub Actions run [#5](https://github.com/shasan731/ao3-downloader/actions/runs/40287116421) passed on October 26, 2026 for commit `d9669a2`: synthetic tests, arm64 Release build, ad-hoc signature verification, ZIP/DMG packaging, checksums, and artifact upload all completed successfully. No local compiler or test suite was run, per project constraints. AO3 selectors are based on synthetic fixtures and still require one supervised, low-volume real-site smoke test. No claim of production AO3 compatibility is made until then.

