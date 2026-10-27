# Implementation status

## Implemented and CI-verified

- Native macOS 14 SwiftUI navigation shell, work input/preview, folder chooser, format picker, open/reveal actions, Settings and About.
- Exact HTTPS host/path validation and chapter-to-work normalization.
- Explicit public Mature/Explicit consent handling with adult-warning detection and strict same-work canonical/first-chapter redirect validation; multi-chapter parts still use AO3's complete-work downloads.
- Public work metadata parsing with SwiftSoup and discovered official EPUB/PDF/HTML links.
- One in-flight AO3 request lifecycle globally, 15-second default spacing, cancellation-aware waiting, numeric/HTTP-date `Retry-After` parsing, and relaunch-safe cooldown persistence.
- Actionable offline/timeout/status classification, challenge/restricted detection, bounded HTML reads, and host-safe downloads.
- PDF/EPUB/HTML signatures and basic EPUB structure validation before safe, auto-renamed output.
- Bounded series pagination with cycle/host/path protection, author-order selection, sequential separate-file downloads, inaccessible-work visibility, and partial `download-report.json` output.
- Book-quality combined EPUB 3 output with per-work resource namespaces, designed title/Contents/part-divider pages, and clickable Series → Book/Story → Chapter navigation in-book and in reader sidebars.
- Single and combined PDF polishing with non-rasterized source pages, designed title and paginated Contents pages, clickable internal links, imported hierarchical chapter bookmarks, and duplicate-safe managed front matter.
- Window-owned operations continue across sidebar navigation, with analysis-page progress, per-work processed counts/status icons, combined-book assembly/verification phases, elapsed time, and explicit cancellation that retains verified output.
- Versioned atomic JSON persistence service and deterministic URL/parser/file/persistence tests.
- Recoverable durable Library projects with immediate visible per-part/failure checkpoints, schema validation, a last-known-good database copy, security-scoped destination bookmarks, retained hidden sources for combined-only jobs, missing-local-file detection, and safe record-only removal.
- Individual and ordered bulk retry from New Download, Queue, and Library with visible failure reasons, dynamic deselection during an active download, manual verified-subset recombination after failures, and reanalysis that preserves known selections/downloads while identifying new work IDs.
- Editable title, authors, language, and managed JPEG/PNG cover metadata for single works, retained parts, new combined books, and existing combined EPUB/PDF files.
- Synthetic tests for Library round trips, live deselection, retained-source reuse, EPUB package metadata/cover/front-matter navigation, and PDF metadata/cover/clickable Contents/outline regeneration.
- arm64 GitHub Actions test/build/ZIP/DMG/checksum pipeline and tag prerelease workflow.

## Not yet supported

- Pause/resume controls (explicit cancellation and later Library recovery are supported).
- Automatic offline monitoring, resume-on-reconnect, and notifications.
- Automatic bounded retry attempts for transient server failures (manual individual/bulk retry is supported).
- Developer ID signing and notarization. CI artifacts use an ad-hoc integrity signature only.

## Verification state

GitHub Actions run [#24](https://github.com/shasan731/ao3-downloader/actions/runs/40537995089) passed on October 27, 2026 for commit `055ab1c`: the synthetic numeric `Retry-After`, persisted courtesy/server cooldown, offline classification, damaged-primary Library recovery, hierarchical book navigation, adult-warning, complete multi-chapter work, selectable-series, Library, progress, and cancellation coverage passed; the arm64 Release build, ad-hoc signature verification, ZIP/DMG packaging, checksums, and `AO3Downloader-055ab1ca66948566e9453f4cc964cc9d24e47956` artifact upload also completed successfully. No local compiler or test suite was run, per project constraints. AO3 selectors and the warning/redirect behavior are checked against synthetic fixtures derived from the official open-source AO3 application behavior and still require one supervised, low-volume real-site smoke test. No claim of production AO3 compatibility is made until then.

