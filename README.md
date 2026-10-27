<p align="center">
  <img src="docs/assets/archivebind-icon.png" width="128" alt="ArchiveBind app icon">
</p>

<h1 align="center">ArchiveBind</h1>

<p align="center"><strong>Your stories, beautifully bound.</strong></p>

<p align="center">
  A private, local-first macOS app for saving public Archive of Our Own works and turning a series into a polished EPUB or PDF anthology.
</p>

<p align="center">
  <a href="https://github.com/shasan731/ao3-downloader/actions/workflows/ci.yml"><img alt="Build status" src="https://github.com/shasan731/ao3-downloader/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/shasan731/ao3-downloader/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/shasan731/ao3-downloader"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111">
</p>

> ArchiveBind is unofficial and is not affiliated with Archive of Our Own or the Organization for Transformative Works.

## Why ArchiveBind?

- Download a public work as AO3’s complete EPUB, PDF, or HTML file.
- Analyze ordered series, choose exactly which parts to keep, and change that selection during a download.
- Build book-quality combined EPUB/PDF editions with linked contents, story and chapter navigation, title pages, and PDF bookmarks.
- Retry individual failures without losing successful parts, then combine when the chosen set is complete.
- Keep a durable local Library for metadata editing, custom covers, recombination, and discovering newly added series parts.
- Follow a courteous globally serialized request queue with persistent server-directed cooldowns.
- Stay private: no telemetry, cloud account, password collection, cookie import, or story-content logging.

## Install

1. Open the [latest release](https://github.com/shasan731/ao3-downloader/releases/latest).
2. Download `ArchiveBind-macOS-arm64.dmg` and `SHA256SUMS.txt`.
3. Verify the checksum with `shasum -a 256 -c SHA256SUMS.txt`, open the DMG, and drag ArchiveBind to Applications.
4. The community build is ad-hoc signed but not Apple-notarized. If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after confirming the checksum. Never disable Gatekeeper globally.

ArchiveBind currently targets Apple silicon and macOS 14 or later. The Actions page also provides short-lived artifacts for every successful `main` build.

## Quick start

Paste a public AO3 work, chapter, or series URL into **New Download**, select **Analyze**, review the results, choose a destination and output format, then download. Activity continues if you open another section. For a saved series, use **Library** to retry failures, adjust its selected parts, edit metadata, reanalyze for additions, or make another combined edition.

Public Mature/Explicit warning pages require the explicit consent toggle. Login-only works, browser-session reuse, CAPTCHA bypass, and mirror fallback are intentionally unsupported.

## Documentation

| Guide | Purpose |
| --- | --- |
| [User guide](docs/USER_GUIDE.md) | Complete download, Library, retry, and recombination workflow |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | macOS launch, damaged-app, network, and output help |
| [Privacy](docs/PRIVACY.md) | Data storage and network behavior |
| [Architecture](ARCHITECTURE.md) | Design, safety boundaries, and book assembly |
| [Implementation status](docs/IMPLEMENTATION_STATUS.md) | Verified capabilities and known gaps |
| [CI/CD](docs/CI_CD.md) | Builds, artifacts, release automation, and checksums |
| [Release signing](docs/RELEASE_SIGNING.md) | Developer ID and notarization path |

The [documentation index](docs/README.md) links the remaining policy and test references.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Automated tests use only synthetic fixtures—never live AO3 traffic. Security concerns should follow [SECURITY.md](SECURITY.md).

ArchiveBind is available under the [MIT License](LICENSE). It uses pinned versions of SwiftSoup and ZIPFoundation, both MIT licensed.
