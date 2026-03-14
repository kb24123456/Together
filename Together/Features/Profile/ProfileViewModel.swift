import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let authService: AuthServiceProtocol
    private let relationshipService: RelationshipServiceProtocol
    private let notificationService: NotificationServiceProtocol

    var loadState: LoadableState = .idle
    var notificationAuthorization: NotificationAuthorizationStatus = .notDetermined

    init(
        sessionStore: SessionStore,
        authService: AuthServiceProtocol,
        relationshipService: RelationshipServiceProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.sessionStore = sessionStore
        self.authService = authService
        self.relationshipService = relationshipService
        self.notificationService = notificationService
    }

    var currentUser: User? { sessionStore.currentUser }
    var currentSpace: Space? { sessionStore.currentSpace }
    var bindingState: BindingState { sessionStore.bindingState }
    var pairSpace: PairSpace? { sessionStore.currentPairSpace }
    var activeInvite: Invite? { sessionStore.activeInvite }

    var notificationSummary: String {
        switch notificationAuthorization {
        case .authorized:
            return "提醒已开启"
        case .denied:
            return "提醒未开启"
        case .notDetermined:
            return "尚未请求提醒权限"
        }
    }

    func load() async {
        loadState = .loading
        notificationAuthorization = await notificationService.authorizationStatus()
        loadState = .loaded
    }

    func requestNotifications() async {
        notificationAuthorization = (try? await notificationService.requestAuthorization()) ?? .denied
    }

    func createInvite() async {
        guard let inviterID = currentUser?.id else { return }
        _ = try? await relationshipService.createInvite(from: inviterID)
    }

    func signOut() async {
        await authService.signOut()
        sessionStore.authState = .signedOut
        sessionStore.bindingState = .singleTrial
        sessionStore.currentUser = nil
        sessionStore.currentSpace = nil
        sessionStore.availableSpaces = []
        sessionStore.currentPairSpace = nil
    }
}
