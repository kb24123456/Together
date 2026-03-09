import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private let sessionStore: SessionStore
    private let authService: AuthServiceProtocol
    private let relationshipService: RelationshipServiceProtocol
    private let notificationService: NotificationServiceProtocol

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
    var bindingState: BindingState { sessionStore.bindingState }
    var pairSpace: PairSpace? { sessionStore.currentPairSpace }
    var activeInvite: Invite? { sessionStore.activeInvite }

    func load() async {
        notificationAuthorization = await notificationService.authorizationStatus()
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
        sessionStore.currentPairSpace = nil
    }
}
