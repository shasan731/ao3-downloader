# Security policy

## Supported versions

Security fixes target the latest release and current `main` branch.

## Reporting a vulnerability

Please use GitHub’s **Security → Report a vulnerability** private reporting flow for this repository. Do not open a public issue for a vulnerability involving path traversal, unsafe redirects, credential exposure, sandbox escape, malicious EPUB/PDF handling, or destructive file behavior.

Include a minimal reproduction using synthetic data, affected version, expected impact, and suggested mitigation if available. Do not send story contents, AO3 cookies, credentials, access tokens, or sensitive URLs. Maintainers will acknowledge a valid report when available and coordinate disclosure after a fix.

## Scope

ArchiveBind accepts only exact AO3 HTTPS hosts, treats remote files as untrusted, and does not support account login or browser-cookie import. Current public artifacts are ad-hoc signed and are not notarized; checksum verification and that limitation are documented for every release.
