# Test plan

Automated tests use synthetic fixtures only and cover accepted/rejected URL shapes, normalization, core work metadata/download-menu extraction, explicit adult-warning detection, consent query construction, safe same-work first-chapter redirects, rejection of cross-work redirects, complete multi-chapter metadata, layout failure, ordered multi-page series parsing, inaccessible series entries, ordered per-work progress updates, live deselection, verified-part reuse without another provider analysis, cancellation while waiting for the global request lease, merged EPUB 3 structure/navigation/resource namespacing, in-place EPUB metadata/cover editing, merged PDF page order and metadata/cover output, Unicode/path sanitization, request serialization, and atomic Library persistence round trips. CI compiles, runs the suite, validates bundle identity, ad-hoc signature, and arm64 architecture, then packages ZIP/DMG checksums.

Gaps to add with later phases: full fake-clock cooldown tests, transport response matrix, forced-process-termination recovery, broader malformed EPUB variations, PDF outline/bookmark tests, and view-model state tests.

Manual checks: launch unsigned app safely, keyboard/VoiceOver navigation, light/dark appearance, one supervised public AO3 work analysis and download per format, one warned multi-chapter series part with consent disabled then enabled, deselection during a longer series run, retry/recombine/reanalysis flows, repeated metadata edits in Apple Books/Preview, removable/moved destination behavior, and Gatekeeper messaging.

