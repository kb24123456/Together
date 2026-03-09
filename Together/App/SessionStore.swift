import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    var authState: AuthState = .signedOut
    var bindingState: BindingState = .singleTrial
    var currentUser: User?
    var currentPairSpace: PairSpace?
    var activeInvite: Invite?

    func bootstrap(
        authService: AuthServiceProtocol,
        relationshipService: RelationshipServiceProtocol
    ) async {
        let session = await authService.currentSession()
        authState = session.state
        currentUser = session.user

        let bindingContext = await relationshipService.currentBindingContext(for: session.user?.id)
        bindingState = bindingContext.state
        currentPairSpace = bindingContext.pairSpace
        activeInvite = bindingContext.activeInvite
    }
}
