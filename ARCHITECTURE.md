# Architecture

SwiftUI views bind to `@MainActor` view models. View models validate intent and call injected provider/services; they do not parse HTML or own networking. `AO3Client` obtains a full lifecycle lease from the `AO3RequestScheduler` actor so metadata and file requests cannot overlap. `HTTPTransport` is replaceable in tests. `AO3HTMLParser` semantically parses bounded HTML. Downloads are staged by URLSession, verified, then moved to a collision-safe destination. Codable persistence uses atomic replacement.

The app is sandboxed for outbound networking and user-selected folder access. Future series jobs will own durable staging folders and checkpoints. All downloaded markup and ebooks are untrusted data.

