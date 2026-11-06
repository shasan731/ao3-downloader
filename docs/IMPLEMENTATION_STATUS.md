# Implementation status

## Implemented and CI-verified

- Native macOS 14 SwiftUI navigation shell with ArchiveBind branding and original icon, responsive work input/preview, folder chooser, format picker, open/reveal actions, narrow-window Settings, and About.
- Exact HTTPS host/path validation for AO3 and `www.fanfiction.net`, with AO3 chapter-to-work and FanFiction.net chapter-to-story normalization.
- Explicit public Mature/Explicit consent handling with adult-warning detection and strict same-work canonical/first-chapter redirect validation; multi-chapter parts still use AO3's complete-work downloads.
- Public work metadata parsing with SwiftSoup and discovered official EPUB/PDF/HTML links.
- One in-flight request lifecycle globally across both sites, 15-second default spacing, cancellation-aware waiting, numeric/HTTP-date `Retry-After` parsing, and relaunch-safe cooldown persistence.
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
- Size-stable large-series preview with a bounded lazy scroller, title/part search, progress-state filters, live counters, collapsible descriptions, and automatic active-part tracking.
- Quality-of-life URL trimming/clearing, Return-to-analyze, Escape-to-cancel, and a stable minimum window size.
- FanFiction.net single- and multi-chapter story analysis with source-aware metadata, chapter-level download progress, bounded page reads, exact same-story redirect checks, and sanitized local EPUB 3/PDF/HTML generation with linked Contents/bookmarks and editable metadata.
- Durable Activity history for single stories and series with atomic per-chapter/per-part checkpoints, distinct fetching/building/verifying phases, persistent failure details, completed-output reopening, interrupted-operation recovery after relaunch, and one-click safe retry without repopulating New Download.
- App-wide compact live-progress controls, Activity attention badges, and narrow-window-safe Activity/Library layouts so sidebar navigation remains usable throughout long downloads.
- FanFiction.net challenge/unavailable-page recognition with no browser-cookie import, security-feature bypass, or fallback scraping; offline fixtures cover URL safety, metadata, sanitization, challenge classification, and all three book formats.
- arm64 GitHub Actions test/build/ArchiveBind ZIP/DMG/checksum pipeline and stable tag-release workflow.

## Not yet supported

- Pause/resume controls (explicit cancellation and later Library recovery are supported).
- Automatic offline monitoring, resume-on-reconnect, and notifications.
- Automatic bounded retry attempts for transient server failures (manual individual/bulk retry is supported).
- Developer ID signing and notarization. CI artifacts use an ad-hoc integrity signature only.
- FanFiction.net communities/favorites lists as series. FanFiction.net has no native ordered-series object comparable to AO3 series.
- FanFiction.net pages while its browser-verification challenge blocks ordinary HTTPS clients. ArchiveBind deliberately does not circumvent that control.

## Verification state

GitHub Actions run [#31](https://github.com/shasan731/ao3-downloader/actions/runs/42084643038) passed on November 6, 2026 for commit `82f8acc`. The complete offline suite—including the new strict FanFiction.net URL cases, metadata/chapter parser, unsafe-markup removal, challenge recognition, and generated EPUB/PDF/HTML verification—passed alongside every existing AO3 series, Library, merger, scheduler, and workspace test. Debug and Release compilation, ArchiveBind icon compilation, ad-hoc signature verification, arm64 validation, ZIP/DMG packaging, checksums, and artifact upload also succeeded. Tag workflow [Release #4](https://github.com/shasan731/ao3-downloader/actions/runs/42086118720) independently passed its test/build/verify/package gates and published stable [ArchiveBind v0.2.0](https://github.com/shasan731/ao3-downloader/releases/tag/v0.2.0). Both public DMG/ZIP SHA-256 checks passed, and the ZIP contains the signed app executable and code-signature resources; the temporary verification downloads were removed. No local Xcode build or test was run, per repository constraints. A supervised live compatibility probe from the development network received FanFiction.net's Cloudflare browser-verification response; ArchiveBind correctly treats that class of response as a non-bypassable challenge. Live story compatibility remains dependent on FanFiction.net allowing ordinary HTTPS access from the user's network.

GitHub Actions run [#29](https://github.com/shasan731/ao3-downloader/actions/runs/41326183867) passed on November 1, 2026 for commit `1c5b51f`: the complete synthetic suite—including busy-safe New Download workspace isolation, numeric `Retry-After`, persisted courtesy/server cooldown, offline classification, damaged-primary Library recovery, hierarchical book navigation, adult-warning, complete multi-chapter work, selectable-series, Library, progress, and cancellation coverage—passed, and the size-stable large-series SwiftUI changes compiled in both Debug and Release. The arm64 Release build, ArchiveBind icon compilation, ad-hoc signature verification, ZIP/DMG packaging, checksums, and `ArchiveBind-1c5b51fa957d62137698e0c1f3c51242644707c9` artifact upload also completed successfully. Tag workflow [Release #3](https://github.com/shasan731/ao3-downloader/actions/runs/41326568498) then passed the same test/build/verify/package gates and published stable [ArchiveBind v0.1.3](https://github.com/shasan731/ao3-downloader/releases/tag/v0.1.3) with DMG, ZIP, and checksum assets. The public assets were downloaded and both SHA-256 checks passed; the ZIP contains the expected signed `ArchiveBind.app`. No local compiler or test suite was run, per project constraints. AO3 selectors and the warning/redirect behavior are checked against synthetic fixtures derived from the official open-source AO3 application behavior and still require one supervised, low-volume real-site smoke test. No claim of production AO3 compatibility is made until then.

