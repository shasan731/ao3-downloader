# CI/CD

The fixed `macos-15` runner prints environment versions, installs checksum-pinned XcodeGen 2.42.0, generates the project, resolves exact Swift package versions, tests, builds unsigned arm64 Release output, verifies its bundle and packages ZIP/DMG artifacts for 14 days. Same-branch runs cancel older runs to reduce macOS minutes.

Tags matching `v*` repeat test/build in one runner and create an explicitly unsigned prerelease. GitHub Actions usage depends on repository visibility and account plan; inspect repository Billing settings before frequent runs.

