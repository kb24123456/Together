import Observation

@MainActor
@Observable
final class AppBootstrapper {
    enum Phase: Equatable {
        case idle
        case bootstrapping
        case ready
    }

    private(set) var phase: Phase = .idle
    private(set) var appContext: AppContext?

    var isReady: Bool {
        phase == .ready && appContext != nil
    }

    func bootstrapIfNeeded() async {
        guard phase == .idle else { return }

        phase = .bootstrapping
        StartupTrace.mark("AppBootstrapper.bootstrap.begin")

        // Allow the launch surface to render before building the full app graph.
        await Task.yield()
        StartupTrace.mark("AppBootstrapper.bootstrap.afterYield")

        let appContext = AppContext.makeBootstrappedContext()
        await appContext.restorePersistedUserProfileIfNeeded()
        self.appContext = appContext
        phase = .ready
        StartupTrace.mark("AppBootstrapper.bootstrap.ready")
    }
}
