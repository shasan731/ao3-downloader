# CI/CD

The fixed `macos-15` runner prints environment versions, installs checksum-pinned XcodeGen 2.42.0, generates the project, resolves exact Swift package versions, tests, builds unsigned arm64 Release output, verifies its bundle and packages ZIP/DMG artifacts for 14 days. Same-branch runs cancel older runs to reduce macOS minutes.

Tags matching `v*` repeat test/build in one runner and publish a stable GitHub release with generated notes, an `ArchiveBind-macOS-arm64` ZIP and DMG, and `SHA256SUMS.txt`. The app inside the packages is renamed for display while its internal executable and bundle identifier remain stable for compatibility. Public artifacts are ad-hoc signed rather than Developer ID signed or notarized, and the release clearly states that limitation.

GitHub Actions usage depends on repository visibility and account plan; inspect repository Billing settings before frequent runs. The workflow is authoritative—local Xcode builds are intentionally not part of the project process.

