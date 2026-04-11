import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    var authState: AuthState = .signedOut
    var isAppLocked: Bool = false
    var currentUser: User? {
        didSet {
            userProfileRevision = UUID()
        }
    }
    var userProfileRevision = UUID()
    var activeMode: AppMode = .single
    var singleSpace: Space?
    var pairSpaceSummary: PairSpaceSummary?
    var availableModeStates: [AppMode] = [.single]
    var pairingContext = PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)

    var currentSpace: Space? {
        switch activeMode {
        case .single:
            return singleSpace
        case .pair:
            return pairSpaceSummary?.sharedSpace
        }
    }

    var availableSpaces: [Space] {
        [singleSpace, pairSpaceSummary?.sharedSpace].compactMap { $0 }
    }

    var bindingState: BindingState {
        pairingContext.state
    }

    var currentPairSpace: PairSpace? {
        pairSpaceSummary?.pairSpace
    }

    var activeInvite: Invite? {
        pairingContext.activeInvite
    }

    func bootstrap(
        authService: AuthServiceProtocol,
        spaceService: SpaceServiceProtocol,
        pairingService: PairingServiceProtocol
    ) async {
        let session = await authService.currentSession()
        authState = session.state
        currentUser = session.user

        let spaceContext = await spaceService.currentSpaceContext(for: session.user?.id)
        let pairingContext = await pairingService.currentPairingContext(for: session.user?.id)

        singleSpace = spaceContext.singleSpace
        pairSpaceSummary = spaceContext.pairSpaceSummary ?? pairingContext.pairSpaceSummary
        availableModeStates = spaceContext.availableModes
        self.pairingContext = pairingContext
        activeMode = .single
    }

    func handleSignIn(session: AuthSession) {
        authState = session.state
        currentUser = session.user
    }

    func switchMode(to mode: AppMode) {
        guard availableModeStates.contains(mode) else { return }
        guard mode == .single || pairSpaceSummary != nil else { return }
        activeMode = mode
    }

    func refresh(spaceContext: SpaceContext, pairingContext: PairingContext) {
        singleSpace = spaceContext.singleSpace
        pairSpaceSummary = spaceContext.pairSpaceSummary ?? pairingContext.pairSpaceSummary
        availableModeStates = spaceContext.availableModes
        self.pairingContext = pairingContext
        if availableModeStates.contains(activeMode) == false {
            activeMode = .single
        }
    }
}
