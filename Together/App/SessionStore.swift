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
        case .pair:
            if hasActivePairSpace, let sharedSpace = pairSpaceSummary?.sharedSpace {
                return sharedSpace
            }
            return singleSpace
        case .single:
            return singleSpace
        }
    }

    var availableSpaces: [Space] {
        [singleSpace, pairSpaceSummary?.sharedSpace].compactMap { $0 }
    }

    var bindingState: BindingState {
        if hasActivePairSpace {
            return .paired
        }
        return pairingContext.state
    }

    var currentPairSpace: PairSpace? {
        pairSpaceSummary?.pairSpace
    }

    var hasActivePairSpace: Bool {
        currentPairSpace?.status == .active
    }

    var isViewingPairSpace: Bool {
        activeMode == .pair && hasActivePairSpace
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
        let spaceContext = await spaceService.currentSpaceContext(for: session.user?.id)
        let pairingContext = await pairingService.currentPairingContext(for: session.user?.id)
        applyBootstrap(session: session, spaceContext: spaceContext, pairingContext: pairingContext)
    }

    func handleSignIn(session: AuthSession) {
        authState = session.state
        currentUser = session.user
    }

    func switchMode(to mode: AppMode) {
        guard availableModeStates.contains(mode) else { return }
        guard mode == .single || hasActivePairSpace else { return }
        activeMode = mode
    }

    func refresh(spaceContext: SpaceContext, pairingContext: PairingContext) {
        applySpaceAndPairing(spaceContext: spaceContext, pairingContext: pairingContext)
    }

    func applyBootstrap(
        session: AuthSession,
        spaceContext: SpaceContext,
        pairingContext: PairingContext
    ) {
        authState = session.state
        currentUser = session.user
        singleSpace = spaceContext.singleSpace
        applySpaceAndPairing(spaceContext: spaceContext, pairingContext: pairingContext)
        activeMode = .single
    }

    func applySpaceAndPairing(
        spaceContext: SpaceContext,
        pairingContext: PairingContext
    ) {
        singleSpace = spaceContext.singleSpace
        let resolvedPairSummary = spaceContext.pairSpaceSummary ?? pairingContext.pairSpaceSummary
        pairSpaceSummary = resolvedPairSummary
        availableModeStates = resolvedPairSummary?.pairSpace.status == .active ? [.single, .pair] : [.single]
        self.pairingContext = PairingContext(
            state: pairingContext.state,
            pairSpaceSummary: resolvedPairSummary,
            activeInvite: pairingContext.activeInvite
        )
        if availableModeStates.contains(activeMode) == false {
            activeMode = .single
        }
    }

    func applyPairingContext(_ pairingContext: PairingContext, autoSwitchToPairWhenBound: Bool = false) {
        let resolvedPairSummary = pairingContext.pairSpaceSummary
        pairSpaceSummary = resolvedPairSummary
        availableModeStates = resolvedPairSummary?.pairSpace.status == .active ? [.single, .pair] : [.single]
        self.pairingContext = PairingContext(
            state: pairingContext.state,
            pairSpaceSummary: resolvedPairSummary,
            activeInvite: pairingContext.activeInvite
        )
        if resolvedPairSummary == nil, activeMode == .pair {
            activeMode = .single
        } else if autoSwitchToPairWhenBound, pairingContext.state == .paired, resolvedPairSummary != nil {
            activeMode = .pair
        } else if availableModeStates.contains(activeMode) == false {
            activeMode = .single
        }
    }

    func updateActiveInvite(_ invite: Invite?, state: BindingState) {
        pairingContext = PairingContext(
            state: state,
            pairSpaceSummary: pairSpaceSummary,
            activeInvite: invite
        )
    }

    func updatePairSpaceDisplayName(_ displayName: String?) {
        guard var summary = pairSpaceSummary else { return }
        let resolvedSharedName = displayName ?? PairSpace.defaultSharedSpaceDisplayName
        summary.sharedSpace.displayName = resolvedSharedName
        pairSpaceSummary = summary
        pairingContext = PairingContext(
            state: pairingContext.state,
            pairSpaceSummary: summary,
            activeInvite: pairingContext.activeInvite
        )
        userProfileRevision = UUID()
    }

    func clearForSignOut() {
        authState = .signedOut
        currentUser = nil
        singleSpace = nil
        pairSpaceSummary = nil
        availableModeStates = [.single]
        pairingContext = PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
        activeMode = .single
    }

    func seedMock(
        currentUser: User,
        singleSpace: Space,
        pairSummary: PairSpaceSummary?
    ) {
        authState = .signedIn
        self.currentUser = currentUser
        self.singleSpace = singleSpace
        pairSpaceSummary = pairSummary
        availableModeStates = pairSummary?.pairSpace.status == .active ? [.single, .pair] : [.single]
        pairingContext = PairingContext(
            state: pairSummary == nil ? .singleTrial : .paired,
            pairSpaceSummary: pairSummary,
            activeInvite: nil
        )
        activeMode = .single
    }
}
