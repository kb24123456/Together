import Foundation
import Observation

@MainActor
@Observable
final class AppContext {
    let container: AppContainer
    let sessionStore: SessionStore
    let router: AppRouter
    let keyboardMetrics: KeyboardMetricsStore
    let homeViewModel: HomeViewModel
    let decisionsViewModel: DecisionsViewModel
    let anniversariesViewModel: AnniversariesViewModel
    let profileViewModel: ProfileViewModel

    private(set) var hasBootstrapped = false

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.keyboardMetrics = KeyboardMetricsStore()
        self.homeViewModel = HomeViewModel(
            sessionStore: sessionStore,
            itemRepository: container.itemRepository,
            anniversaryRepository: container.anniversaryRepository
        )
        self.decisionsViewModel = DecisionsViewModel(
            sessionStore: sessionStore,
            decisionRepository: container.decisionRepository,
            itemRepository: container.itemRepository
        )
        self.anniversariesViewModel = AnniversariesViewModel(
            sessionStore: sessionStore,
            anniversaryRepository: container.anniversaryRepository
        )
        self.profileViewModel = ProfileViewModel(
            sessionStore: sessionStore,
            authService: container.authService,
            relationshipService: container.relationshipService,
            notificationService: container.notificationService
        )
    }

    static func bootstrap() -> AppContext {
        let container = MockServiceFactory.makeContainer()
        let sessionStore = SessionStore()
        let router = AppRouter()
        return AppContext(container: container, sessionStore: sessionStore, router: router)
    }

    func bootstrapIfNeeded() async {
        guard hasBootstrapped == false else { return }

        await sessionStore.bootstrap(
            authService: container.authService,
            relationshipService: container.relationshipService
        )
        await homeViewModel.load()
        await decisionsViewModel.load()
        await anniversariesViewModel.load()
        await profileViewModel.load()
        hasBootstrapped = true
    }
}
