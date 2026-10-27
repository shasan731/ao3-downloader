# Implementation status

## Implemented and CI-verified

- Native macOS 14 SwiftUI navigation shell with ArchiveBind branding and original icon, responsive work input/preview, folder chooser, format picker, open/reveal actions, narrow-window Settings, and About.
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
- Searchable, streamlined durable Library projects with summary cards, immediate visible per-part/failure checkpoints, schema validation, a last-known-good database copy, security-scoped destination bookmarks, retained hidden sources for combined-only jobs, missing-local-file detection, and safe record-only removal.
- Individual and ordered bulk retry from New Download, Queue, and Library with visible failure reasons, dynamic deselection during an active download, manual verified-subset recombination after failures, and reanalysis that preserves known selections/downloads while identifying new work IDs.
- Editable title, authors, language, and managed JPEG/PNG cover metadata for single works, retained parts, new combined books, and existing combined EPUB/PDF files.
- Synthetic tests for Library round trips, live deselection, retained-source reuse, EPUB package metadata/cover/front-matter navigation, and PDF metadata/cover/clickable Contents/outline regeneration.
- Busy-safe New Download workspace reset after browsing Library, without interrupting active operations or deleting history.
- arm64 GitHub Actions test/build/ArchiveBind ZIP/DMG/checksum pipeline and stable tag-release workflow.

## Not yet supported

- Pause/resume controls (explicit cancellation and later Library recovery are supported).
- Automatic offline monitoring, resume-on-reconnect, and notifications.
- Automatic bounded retry attempts for transient server failures (manual individual/bulk retry is supported).
- Developer ID signing and notarization. CI artifacts use an ad-hoc integrity signature only.

## Verification state

GitHub Actions run [#28](https://github.com/shasan731/ao3-downloader/actions/runs/40547549801) passed on October 27, 2026 for commit `36a8b19`: the complete synthetic suite—including busy-safe New Download workspace isolation, numeric `Retry-After`, persisted courtesy/server cooldown, offline classification, damaged-primary Library recovery, hierarchical book navigation, adult-warning, complete multi-chapter work, selectable-series, Library, progress, and cancellation coverage—passed. The arm64 Release build, ArchiveBind icon compilation, ad-hoc signature verification, ZIP/DMG packaging, checksums, and `ArchiveBind-36a8b194b4365466c028995c6f4a16ac7c33893a` artifact upload also completed successfully. Tag workflow [Release #2](https://github.com/shasan731/ao3-downloader/actions/runs/40548287916) then passed the same test/build/verify/package gates and published stable [ArchiveBind v0.1.2](https://github.com/shasan731/ao3-downloader/releases/tag/v0.1.2) with DMG, ZIP, and checksum assets. The public assets were downloaded and both SHA-256 checks passed; the ZIP contains the expected signed `ArchiveBind.app`. No local compiler or test suite was run, per project constraints. AO3 selectors and the warning/redirect behavior are checked against synthetic fixtures derived from the official open-source AO3 application behavior and still require one supervised, low-volume real-site smoke test. No claim of production AO3 compatibility is made until then.

