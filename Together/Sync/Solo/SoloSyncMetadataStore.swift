import Foundation

final class SoloSyncMetadataStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func migrationCompletedAt(spaceID: UUID) -> Date? {
        defaults.object(forKey: key("migrationCompletedAt", spaceID)) as? Date
    }

    func migrationBuild(spaceID: UUID) -> String? {
        defaults.string(forKey: key("migrationBuild", spaceID))
    }

    func markMigrationCompleted(spaceID: UUID, at date: Date, build: String?) {
        defaults.set(date, forKey: key("migrationCompletedAt", spaceID))
        if let build {
            defaults.set(build, forKey: key("migrationBuild", spaceID))
        } else {
            defaults.removeObject(forKey: key("migrationBuild", spaceID))
        }
    }

    func lastPulledAt(spaceID: UUID) -> Date? {
        defaults.object(forKey: key("lastPulledAt", spaceID)) as? Date
    }

    func setLastPulledAt(_ date: Date, spaceID: UUID) {
        defaults.set(date, forKey: key("lastPulledAt", spaceID))
    }

    func lastPushedAt(spaceID: UUID) -> Date? {
        defaults.object(forKey: key("lastPushedAt", spaceID)) as? Date
    }

    func setLastPushedAt(_ date: Date, spaceID: UUID) {
        defaults.set(date, forKey: key("lastPushedAt", spaceID))
    }

    func baselineRefreshVersion(spaceID: UUID) -> String? {
        defaults.string(forKey: key("baselineRefreshVersion", spaceID))
    }

    func markBaselineRefreshCompleted(spaceID: UUID, version: String, at date: Date) {
        defaults.set(version, forKey: key("baselineRefreshVersion", spaceID))
        defaults.set(date, forKey: key("baselineRefreshCompletedAt", spaceID))
    }

    private func key(_ name: String, _ spaceID: UUID) -> String {
        "together.soloSupabase.\(spaceID.uuidString).\(name)"
    }
}
