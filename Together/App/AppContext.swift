import Foundation
import Observation

@MainActor
@Observable
final class AppContext {
    let container: AppContainer
    let sessionStore: SessionStore
    let router: AppRouter
    let homeViewModel: HomeViewModel
    let decisionsViewModel: DecisionsViewModel
    let anniversariesViewModel: AnniversariesViewModel
    let profileViewModel: ProfileViewModel

    private(set) var hasBootstrapped = false

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
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
        let context = AppContext(container: container, sessionStore: sessionStore, router: router)
        context.seedMockSession()
        context.hasBootstrapped = true
        return context
    }

    func bootstrapIfNeeded() async {
        guard hasBootstrapped == false else { return }

        await sessionStore.bootstrap(
            authService: container.authService,
            relationshipService: container.relationshipService
        )
        hasBootstrapped = true
    }

    private func seedMockSession() {
        sessionStore.authState = .signedIn
        sessionStore.bindingState = .paired
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.currentPairSpace = MockDataFactory.makePairSpace()
        sessionStore.activeInvite = nil
    }
}
