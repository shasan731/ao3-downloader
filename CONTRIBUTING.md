# Contributing to ArchiveBind

Thank you for helping improve ArchiveBind. Keep changes focused, explain user-visible behavior, and preserve existing downloads and Library data.

## Development rules

- GitHub Actions is the authoritative Xcode build and test environment.
- Never add live AO3 requests to automated tests. Use bounded synthetic HTML fixtures.
- Preserve exact-host validation and global request serialization.
- Never log story contents, cookies, credentials, or sensitive URL queries.
- Treat downloaded HTML, EPUBs, and PDFs as untrusted input.
- Update `docs/IMPLEMENTATION_STATUS.md` whenever capabilities change.

## Pull requests

1. Open an issue for significant behavior changes.
2. Add or update deterministic tests for parsing, persistence, file validation, or assembly behavior.
3. Update user and maintainer documentation where relevant.
4. Describe compatibility and migration considerations in the pull request.
5. Wait for the full Actions workflow and address every failing check.

Do not include copyrighted downloaded works, real session data, or credentials in issues, fixtures, commits, or diagnostics.
