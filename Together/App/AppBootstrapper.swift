import Observation

@MainActor
@Observable
final class AppBootstrapper {
    enum Phase: Equatable {
        case idle
        case bootstrapping
        case needsAuth
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

        let appContext = AppContext.makeContext()
        self.appContext = appContext

        await appContext.bootstrapIfNeeded()

        if appContext.sessionStore.authState == .signedIn {
            phase = .ready
        } else {
            phase = .needsAuth
        }
        StartupTrace.mark("AppBootstrapper.bootstrap.phaseResolved=\(phase)")
    }

    func handleSignIn(session: AuthSession) async {
        guard let appContext else { return }
        appContext.sessionStore.handleSignIn(session: session)

        // Set up spaces for a newly signed-in user
        await appContext.setupSpacesForCurrentUserIfNeeded()
        await appContext.restorePersistedUserProfileIfNeeded()
        phase = .ready
        StartupTrace.mark("AppBootstrapper.handleSignIn.ready")
    }

    func handleSignOut() {
        phase = .needsAuth
    }
}
