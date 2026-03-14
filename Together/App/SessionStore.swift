import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    var authState: AuthState = .signedOut
    var bindingState: BindingState = .singleTrial
    var currentUser: User?
    var currentSpace: Space?
    var availableSpaces: [Space] = []
    var currentPairSpace: PairSpace?
    var activeInvite: Invite?

    func bootstrap(
        authService: AuthServiceProtocol,
        spaceService: SpaceServiceProtocol
    ) async {
        let session = await authService.currentSession()
        authState = session.state
        currentUser = session.user

        let spaceContext = await spaceService.currentSpaceContext(for: session.user?.id)
        currentSpace = spaceContext.currentSpace
        availableSpaces = spaceContext.availableSpaces
        bindingState = .singleTrial
        currentPairSpace = nil
        activeInvite = nil
    }
}
