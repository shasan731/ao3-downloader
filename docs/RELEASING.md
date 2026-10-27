# Releasing

1. Update `CHANGELOG.md`, version values in `project.yml`, and `docs/IMPLEMENTATION_STATUS.md`.
2. Push `main` and wait for **Build, Test and Package** to pass. Do not substitute a local Xcode result.
3. Confirm the uploaded ZIP, DMG, and `SHA256SUMS.txt` are present and the app bundle passes the workflow’s verification step.
4. Create and push an annotated `vMAJOR.MINOR.PATCH` tag on the verified commit.
5. Wait for the **Release** workflow. It reruns tests and publishes a stable GitHub release with generated notes.
6. Download the public assets, verify checksums, and perform one supervised low-volume smoke test without adding live AO3 traffic to automated tests.

Until Developer ID signing and notarization are configured, keep the release warning about Gatekeeper and never advise users to disable system security globally. See [Release signing](RELEASE_SIGNING.md).
