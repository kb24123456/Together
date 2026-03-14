import Foundation
import Observation

@MainActor
@Observable
final class AppContext {
    let container: AppContainer
    let sessionStore: SessionStore
    let router: AppRouter
    let homeViewModel: HomeViewModel
    let listsViewModel: ListsViewModel
    let projectsViewModel: ProjectsViewModel
    let calendarViewModel: CalendarViewModel
    let profileViewModel: ProfileViewModel

    private(set) var hasBootstrapped = false

    init(container: AppContainer, sessionStore: SessionStore, router: AppRouter) {
        self.container = container
        self.sessionStore = sessionStore
        self.router = router
        self.homeViewModel = HomeViewModel(
            sessionStore: sessionStore,
            taskApplicationService: container.taskApplicationService
        )
        self.listsViewModel = ListsViewModel(
            sessionStore: sessionStore,
            taskListRepository: container.taskListRepository
        )
        self.projectsViewModel = ProjectsViewModel(
            sessionStore: sessionStore,
            projectRepository: container.projectRepository
        )
        self.calendarViewModel = CalendarViewModel(
            sessionStore: sessionStore,
            itemRepository: container.itemRepository
        )
        self.profileViewModel = ProfileViewModel(
            sessionStore: sessionStore,
            authService: container.authService,
            relationshipService: container.relationshipService,
            notificationService: container.notificationService
        )
    }

    static func bootstrap() -> AppContext {
        let container = LocalServiceFactory.makeContainer()
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
            spaceService: container.spaceService
        )
        hasBootstrapped = true
    }

    private func seedMockSession() {
        sessionStore.authState = .signedIn
        sessionStore.bindingState = .singleTrial
        sessionStore.currentUser = MockDataFactory.makeCurrentUser()
        sessionStore.currentSpace = MockDataFactory.makeSingleSpace()
        sessionStore.availableSpaces = [MockDataFactory.makeSingleSpace()]
        sessionStore.currentPairSpace = nil
        sessionStore.activeInvite = nil
    }
}
