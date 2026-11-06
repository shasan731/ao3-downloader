<p align="center">
  <img src="docs/assets/archivebind-icon.png" width="128" alt="ArchiveBind app icon">
</p>

<h1 align="center">ArchiveBind</h1>

<p align="center"><strong>Your stories, beautifully bound.</strong></p>

<p align="center">
  A private, local-first macOS app for binding public AO3 and FanFiction.net stories into polished EPUB, PDF, and HTML books.
</p>

<p align="center">
  <a href="https://github.com/shasan731/ao3-downloader/actions/workflows/ci.yml"><img alt="Build status" src="https://github.com/shasan731/ao3-downloader/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/shasan731/ao3-downloader/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/shasan731/ao3-downloader"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111">
</p>

> ArchiveBind is unofficial and is not affiliated with Archive of Our Own, the Organization for Transformative Works, or FanFiction.net.

## Why ArchiveBind?

- Download a public work as AO3’s complete EPUB, PDF, or HTML file.
- Turn a public single- or multi-chapter FanFiction.net story into a locally generated EPUB, PDF, or HTML book with linked chapter navigation.
- Analyze AO3 series, choose exactly which parts to keep, and change that selection during a download.
- Build book-quality combined EPUB/PDF editions with linked contents, story and chapter navigation, title pages, and PDF bookmarks.
- Retry individual failures without losing successful parts, then combine when the chosen set is complete.
- Keep a durable local Library for metadata editing, custom covers, recombination, and discovering newly added series parts.
- Follow chapter/part progress from any section; Activity preserves the last checkpoint and offers a safe retry if the app or download is interrupted.
- Follow a courteous globally serialized request queue with persistent server-directed cooldowns.
- Stay private: no telemetry, cloud account, password collection, cookie import, or story-content logging.

## Support at a glance

| Capability | AO3 | FanFiction.net |
| --- | --- | --- |
| Single story/work | EPUB, PDF, HTML supplied by AO3 | EPUB, PDF, HTML assembled locally |
| Multi-chapter story/work | Complete AO3-provided file | Sequential chapter fetch with live progress |
| Ordered series | Selectable parts; separate, combined, or both | Not available—the site has no equivalent ordered-series object |
| Mature-content flow | Explicit public-warning consent | Site-provided public access only |
| Login/browser session | Not imported or supported | Not imported or supported |
| Verification challenge | Detected; never bypassed | Detected; never bypassed |

See [Implementation status](docs/IMPLEMENTATION_STATUS.md) for verified behavior and current limitations.

## Install

1. Open the [latest release](https://github.com/shasan731/ao3-downloader/releases/latest).
2. Download `ArchiveBind-macOS-arm64.dmg` and `SHA256SUMS.txt`.
3. In Terminal, run `grep 'ArchiveBind-macOS-arm64.dmg$' SHA256SUMS.txt | shasum -a 256 -c -` from the download folder.
4. After it reports `OK`, open the DMG and drag ArchiveBind to Applications.
5. The community build is ad-hoc signed but not Apple-notarized. If macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway** after confirming the checksum. Never disable Gatekeeper globally.

ArchiveBind currently targets Apple silicon and macOS 14 or later. The Actions page also provides short-lived artifacts for every successful `main` build.

## Quick start

Paste a public AO3 work/chapter/series URL or a `www.fanfiction.net/s/…` story URL into **New Download**, select **Analyze**, review the results, choose a destination and output format, then download. Activity continues if you open another section, and a compact progress bar remains visible throughout the app. FanFiction.net chapters are fetched one at a time through the same courteous global queue and assembled locally. If ArchiveBind closes before finishing, **Activity** shows the last saved chapter/part count and a Retry action after relaunch. For a saved AO3 series, use **Library** to retry failures, adjust its selected parts, edit metadata, reanalyze for additions, or make another combined edition.

Public AO3 Mature/Explicit warning pages require the explicit consent toggle. Login-only works, browser-session reuse, verification/CAPTCHA bypass, and mirror fallback are intentionally unsupported. FanFiction.net may present Cloudflare browser verification; ArchiveBind reports that condition and does not bypass it.

## Reliability and safety boundaries

- Every remote request uses an exact approved HTTPS host and the global serialized request queue.
- Downloads are staged, format-checked, and moved into the selected folder only after verification.
- FanFiction.net markup is sanitized before local book generation; automated tests never contact either story site.
- Cancelling retains already verified files, while Library checkpoints preserve retry and recombination state.
- ArchiveBind is intended for authorized personal use. Users remain responsible for source-site terms, applicable law, and creators’ choices.

## Documentation

| Guide | Purpose |
| --- | --- |
| [User guide](docs/USER_GUIDE.md) | Complete download, Library, retry, and recombination workflow |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | macOS launch, damaged-app, network, and output help |
| [Privacy](docs/PRIVACY.md) | Data storage and network behavior |
| [FanFiction.net policy notes](docs/FANFICTION_NET_POLICY_NOTES.md) | Request pacing, terms boundary, and challenge behavior |
| [Architecture](ARCHITECTURE.md) | Design, safety boundaries, and book assembly |
| [Implementation status](docs/IMPLEMENTATION_STATUS.md) | Verified capabilities and known gaps |
| [CI/CD](docs/CI_CD.md) | Builds, artifacts, release automation, and checksums |
| [Release signing](docs/RELEASE_SIGNING.md) | Developer ID and notarization path |

The [documentation index](docs/README.md) links the remaining policy and test references.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Automated tests use only synthetic fixtures—never live AO3 or FanFiction.net traffic. Security concerns should follow [SECURITY.md](SECURITY.md).

The ArchiveBind source code is available under the [MIT License](LICENSE). That license covers this software, not stories, metadata, site trademarks, or other third-party material processed by a user. ArchiveBind uses pinned versions of SwiftSoup and ZIPFoundation, both MIT licensed.
