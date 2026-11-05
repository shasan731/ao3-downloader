# Security policy

## Supported versions

Security fixes target the latest release and current `main` branch.

| Version | Supported |
| --- | --- |
| 0.2.x | Yes |
| 0.1.x and earlier | No—upgrade to the latest release |
| `main` | Development fixes; not a stable support channel |

## Reporting a vulnerability

Please use GitHub’s **Security → Report a vulnerability** private reporting flow for this repository. Do not open a public issue for a vulnerability involving path traversal, unsafe redirects, credential exposure, sandbox escape, malicious HTML/EPUB/PDF handling, persistence corruption, or destructive file behavior.

Include:

- The affected ArchiveBind version and macOS version.
- A concise impact assessment and reproducible steps using synthetic data.
- The smallest safe fixture or proof of concept needed to demonstrate the issue.
- Any known preconditions, mitigations, or suggested fix.

Do not send story contents, site cookies, credentials, access tokens, personal Library databases, or sensitive URL query strings. Maintainers will review reports on a best-effort basis, keep reporters informed when practical, and coordinate public disclosure after an appropriate fix is available.

## Security boundaries

- Network access is restricted to exact approved HTTPS hosts: `archiveofourown.org`, `download.archiveofourown.org`, and `www.fanfiction.net`.
- Redirects must retain the expected provider, story/work identity, and approved path shape.
- All provider requests share one serialized, cooldown-aware scheduler.
- Browser sessions, cookies, credentials, account login, verification bypasses, and mirror fallbacks are outside the design.
- Remote HTML and downloaded/generated books are treated as untrusted and bounded before parsing, extraction, merging, or editing.
- User-selected files are staged and verified before replacement; Library storage uses atomic writes and a validated recovery copy.
- Story contents and sensitive request data must never be logged.

Reports that demonstrate a bypass or failure of these boundaries are in scope.

## Usually not security vulnerabilities

- A supported site changing its layout, becoming unavailable, throttling requests, or showing browser verification.
- Gatekeeper warning about the documented lack of Apple notarization.
- A story’s content, metadata, copyright status, or removal by its creator.
- A problem requiring the user to intentionally disable macOS protections or replace the application bundle.

These may still be valid functional or policy issues; use the normal issue tracker with synthetic, non-sensitive details.

## Release integrity

Current public artifacts are ad-hoc signed, checksum-published, and not Developer ID signed or Apple-notarized. Download only from the repository’s [official Releases page](https://github.com/shasan731/ao3-downloader/releases), verify the matching `SHA256SUMS.txt`, and never disable Gatekeeper globally. Signing and notarization limitations are documented in every release.
