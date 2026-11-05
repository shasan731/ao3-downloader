# Contributing to ArchiveBind

Thank you for helping improve ArchiveBind. Keep changes focused, explain user-visible behavior, and preserve existing downloads and Library data.

## Before starting

- Search existing issues and the [implementation status](docs/IMPLEMENTATION_STATUS.md) before duplicating work.
- Open an issue before a large feature, storage migration, provider addition, or major UI redesign.
- Keep pull requests narrow enough to review and verify safely.

Small documentation corrections, deterministic tests, and clearly scoped bug fixes can go directly to a pull request.

## Safety invariants

- GitHub Actions is the authoritative Xcode build and test environment.
- Never add live AO3 or FanFiction.net requests to automated tests. Use small, bounded synthetic HTML fixtures.
- Preserve strict exact-host/path validation, same-work/story redirect checks, and global request serialization across providers.
- Do not add browser-cookie import, account login, challenge/CAPTCHA bypass, mirror fallback, or concurrent story-site requests.
- Never log story contents, cookies, credentials, or sensitive URL queries.
- Treat downloaded HTML, EPUBs, and PDFs as untrusted input.
- Preserve output staging, validation, collision-safe filenames, and cancellation-safe verified files.
- Keep persisted Library schema changes backward compatible or provide an explicit migration and recovery test.
- Update `docs/IMPLEMENTATION_STATUS.md` whenever capabilities change.

Changes that weaken these boundaries will not be accepted merely for speed or compatibility.

## Development environment

- macOS 14 or later on Apple silicon.
- Xcode 16.2 or a compatible newer Xcode with Swift 5.10 support.
- [XcodeGen 2.42.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.42.0).

Generate the project with `xcodegen generate --spec project.yml`. The generated `.xcodeproj`, build output, downloaded books, credentials, and local Library data must not be committed. Local checks are useful for contributors, but the GitHub Actions result remains authoritative.

## Repository map

- `AO3Downloader/Services` — networking, parsing, validation, persistence, and book generation.
- `AO3Downloader/ViewModels` and `AO3Downloader/Views` — durable operation state and SwiftUI presentation.
- `AO3DownloaderTests` — deterministic offline tests and synthetic fixtures.
- `docs` — user, privacy, policy, release, and implementation documentation.
- `Scripts` and `.github/workflows` — reproducible packaging and release automation.

## Testing requirements

- Add accepted and rejected URL cases for parser or redirect changes.
- Cover malformed, oversized, escaping, or active-content input when changing file/HTML handling.
- Test cancellation, partial success, and persistence recovery when changing long-running workflows.
- Validate generated EPUB/PDF/HTML structure when changing book output.
- Keep fixtures fictional, minimal, and free of copied story text or real session data.

Do not make a test depend on network availability, a live site layout, request timing, a personal folder, or an account.

## Pull requests

1. Explain the problem and the user-visible result.
2. Add or update deterministic tests for affected behavior.
3. Update the changelog and relevant user/maintainer documentation.
4. Describe security, privacy, compatibility, and migration considerations.
5. Include screenshots for meaningful UI changes, using only synthetic data.
6. Wait for the full Actions workflow and address every failing check.

By contributing, you agree that your contribution is licensed under this repository’s [MIT License](LICENSE). Do not include copyrighted downloaded works, site assets, real session data, private account information, or credentials in issues, fixtures, commits, screenshots, or diagnostics.
