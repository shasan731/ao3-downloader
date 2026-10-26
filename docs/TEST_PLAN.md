# Test plan

Automated tests use synthetic fixtures only and cover accepted/rejected URL shapes, normalization, core work metadata/download-menu extraction, layout failure, ordered multi-page series parsing, inaccessible series entries, Unicode/path sanitization, request serialization, and persistence round trips. CI compiles, runs the suite, validates bundle identity, ad-hoc signature, and arm64 architecture, then packages ZIP/DMG checksums.

Gaps to add with later phases: full fake-clock cooldown tests, transport response matrix, crash recovery, series download recovery, EPUB 2/3 merge fixtures, PDF page-order fixtures, and view-model state tests.

Manual checks: launch unsigned app safely, keyboard/VoiceOver navigation, light/dark appearance, one supervised public AO3 work analysis and download per format, Apple Books/Preview readability, removable destination behavior, and Gatekeeper messaging.

