import Foundation

struct AppDependencies {
    let provider: AO3Providing
    let manager: DownloadManager
    let persistence: DownloadPersistence
    let libraryStore: LibraryStore

    static let live: AppDependencies = {
        let defaults = UserDefaults.standard
        let cooldown = defaults.object(forKey: "AO3NextAllowedAt") as? Date ?? .distantPast
        let configuredInterval = defaults.object(forKey: "minimumRequestInterval") as? Double ?? 15
        let scheduler = AO3RequestScheduler(minimumInterval: max(10, configuredInterval), persistedCooldown: cooldown,
                                            cooldownChanged: { UserDefaults.standard.set($0, forKey: "AO3NextAllowedAt") })
        let provider = AO3Client(scheduler: scheduler)
        return AppDependencies(provider: provider, manager: DownloadManager(provider: provider),
                               persistence: DownloadPersistence(), libraryStore: LibraryStore())
    }()
}

