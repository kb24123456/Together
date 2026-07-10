import Foundation
import Observation

@MainActor
@Observable
final class AppBootstrapper {
    enum Phase: Equatable {
        case idle
        case bootstrapping
        case needsAuth
        case ready
        case persistenceFailed(PersistenceStartupFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var appContext: AppContext?

    var isReady: Bool {
        phase == .ready && appContext != nil
    }

    func bootstrapIfNeeded() async {
        guard phase == .idle else { return }

        let startedAt = ContinuousClock.now
        phase = .bootstrapping
        StartupTrace.mark("AppBootstrapper.bootstrap.begin")

        // Allow the launch surface to render before building the full app graph.
        await Task.yield()
        StartupTrace.mark("AppBootstrapper.bootstrap.afterYield")

        let appContext: AppContext
        do {
            appContext = try AppContext.makeContext()
            self.appContext = appContext
        } catch let failure as PersistenceStartupFailure {
            self.appContext = nil
            phase = .persistenceFailed(failure)
            StartupTrace.mark("AppBootstrapper.bootstrap.persistenceFailed=\(failure.summary)")
            return
        } catch {
            let failure = PersistenceStartupFailure(summary: error.localizedDescription)
            self.appContext = nil
            phase = .persistenceFailed(failure)
            StartupTrace.mark("AppBootstrapper.bootstrap.persistenceFailed=\(failure.summary)")
            return
        }

        await appContext.bootstrapIfNeeded()

        // Ensure the launch animation has time to play out.
        let minLaunchDuration: Duration = .milliseconds(1200)
        let elapsed = ContinuousClock.now - startedAt
        if elapsed < minLaunchDuration {
            try? await Task.sleep(for: minLaunchDuration - elapsed)
        }

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
        await appContext.migrateLegacyProjectsIfNeeded()
        await appContext.restorePersistedUserProfileIfNeeded()
        phase = .ready
        StartupTrace.mark("AppBootstrapper.handleSignIn.ready")
    }

    func handleSignOut() {
        phase = .needsAuth
    }

    func retryPersistenceBootstrap() async {
        guard case .persistenceFailed = phase else { return }
        appContext = nil
        phase = .idle
        await bootstrapIfNeeded()
    }
}
