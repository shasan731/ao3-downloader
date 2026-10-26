# Implementation status

## Implemented (source present; CI not yet run)

- Native macOS 14 SwiftUI navigation shell, work input/preview, folder chooser, format picker, open/reveal actions, Settings and About.
- Exact HTTPS host/path validation and chapter-to-work normalization.
- Public work metadata parsing with SwiftSoup and discovered official EPUB/PDF/HTML links.
- One in-flight AO3 request lifecycle globally, 15-second default spacing, cancellation-aware waiting.
- Status classification, challenge/restricted detection, bounded HTML reads, host-safe downloads.
- PDF/EPUB/HTML signatures and basic EPUB structure validation before safe, auto-renamed output.
- Versioned atomic JSON persistence service and deterministic URL/parser/file/persistence tests.
- arm64 GitHub Actions test/build/ZIP/DMG/checksum pipeline and tag prerelease workflow.

## Not yet supported

- Series UI, pagination orchestration, durable per-work queue/recovery, partial reports.
- Merged EPUB 3 and merged PDF output.
- Complete pause/resume/cancel/history UI and persisted security-scoped bookmarks.
- Full Retry-After parsing, escalation persistence, retries/offline monitoring, notifications.
- Signing/notarization. All artifacts are unsigned.

## Verification state

No local compiler or test suite was run, per project constraints. GitHub Actions has not yet been triggered or inspected. AO3 selectors are based on synthetic fixtures and require one supervised, low-volume real-site smoke test after CI succeeds. No claim of production compatibility is made until then.

