import Foundation

struct TodayWidgetSharedContext: Codable, Equatable, Sendable {
    var spaceID: UUID
    var actorID: UUID
}

struct TodayWidgetSharedContextStore: Sendable {
    private static let key = "today-widget-context"
    private nonisolated(unsafe) let defaults: UserDefaults?

    nonisolated init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
    }

    nonisolated func read() -> TodayWidgetSharedContext? {
        guard let data = defaults?.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(TodayWidgetSharedContext.self, from: data)
    }

    nonisolated func write(_ context: TodayWidgetSharedContext) {
        guard let data = try? JSONEncoder().encode(context) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    nonisolated func clear() {
        defaults?.removeObject(forKey: Self.key)
    }
}
