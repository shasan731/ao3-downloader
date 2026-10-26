import Foundation

struct AppDependencies {
    let provider: AO3Providing
    let manager: DownloadManager
    let persistence: DownloadPersistence

    static let live: AppDependencies = {
        let defaults = UserDefaults.standard
        let cooldown = defaults.object(forKey: "AO3NextAllowedAt") as? Date ?? .distantPast
        let scheduler = AO3RequestScheduler(persistedCooldown: cooldown)
        let provider = AO3Client(scheduler: scheduler)
        return AppDependencies(provider: provider, manager: DownloadManager(provider: provider), persistence: DownloadPersistence())
    }()
}

