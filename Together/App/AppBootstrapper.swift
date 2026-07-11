import CoreData
import Foundation
import Observation

@MainActor
@Observable
final class AppBootstrapper {
    enum Phase: Equatable {
        case idle
        case bootstrapping
        case restoringIdentity(isSlow: Bool)
        case requiresLocalStart
        case identityFailed(String)
        case ready
        case persistenceFailed(PersistenceStartupFailure)
    }

    private(set) var phase: Phase = .idle
    private(set) var appContext: AppContext?
    private var identityRestoreSlowTask: Task<Void, Never>?
    private var cloudImportObservationTask: Task<Void, Never>?
    private var didObserveSuccessfulInitialImport = false

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
            startObservingCloudImports()
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

        let identityResolution = await appContext.bootstrapIfNeeded(
            afterInitialCloudImport: didObserveSuccessfulInitialImport
        )

        // Ensure the launch animation has time to play out.
        let minLaunchDuration: Duration = .milliseconds(1200)
        let elapsed = ContinuousClock.now - startedAt
        if elapsed < minLaunchDuration {
            try? await Task.sleep(for: minLaunchDuration - elapsed)
        }

        apply(identityResolution)
        StartupTrace.mark("AppBootstrapper.bootstrap.phaseResolved=\(phase)")
    }

    func startLocally() async {
        guard let appContext else { return }
        do {
            apply(try await appContext.startLocally())
        } catch {
            phase = .identityFailed("无法创建本机空间，请重试。")
        }
    }

    func retryPersistenceBootstrap() async {
        guard case .persistenceFailed = phase else { return }
        appContext = nil
        phase = .idle
        await bootstrapIfNeeded()
    }

    func retryIdentityResolution() async {
        guard let appContext else { return }
        phase = .bootstrapping
        apply(await appContext.bootstrapIfNeeded(afterInitialCloudImport: didObserveSuccessfulInitialImport))
    }

    private func apply(_ resolution: PersonalIdentityResolution) {
        identityRestoreSlowTask?.cancel()
        switch resolution {
        case .ready:
            phase = .ready
        case .waitingForCloudRestore:
            phase = .restoringIdentity(isSlow: false)
            identityRestoreSlowTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard Task.isCancelled == false,
                      let self,
                      case .restoringIdentity = phase else { return }
                phase = .restoringIdentity(isSlow: true)
            }
        case .requiresLocalStart:
            phase = .requiresLocalStart
        }
    }

    private func startObservingCloudImports() {
        guard cloudImportObservationTask == nil else { return }
        cloudImportObservationTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                      event.type == .import,
                      event.endDate != nil,
                      event.succeeded
                else { continue }

                guard let self else { return }
                didObserveSuccessfulInitialImport = true
                guard let appContext else { continue }
                apply(await appContext.bootstrapIfNeeded(afterInitialCloudImport: true))
            }
        }
    }
}
