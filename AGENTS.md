# Repository guidance

- Do not run local Xcode builds or tests; GitHub Actions is authoritative.
- Never add live AO3 network calls to automated tests.
- Preserve strict exact-host validation and global request serialization.
- Never log story contents, cookies, credentials, or sensitive URL queries.
- Update `docs/IMPLEMENTATION_STATUS.md` when capabilities change.

