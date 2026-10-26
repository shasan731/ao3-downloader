# Release signing

Current artifacts are ad-hoc signed for bundle-integrity verification but are not Developer ID signed or notarized. Ad-hoc signing does not identify the developer or satisfy Gatekeeper distribution trust. Users may use System Settings → Privacy & Security → Open Anyway for a checksum-verified build they trust. Do not disable Gatekeeper globally. A future protected-tag workflow can use encrypted Developer ID and App Store Connect credentials with a temporary keychain, `notarytool`, stapling, and verification; no credentials belong in this repository.

