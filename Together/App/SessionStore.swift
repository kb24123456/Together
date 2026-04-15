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
    var selectedWorkspace: WorkspaceSelection = .single
    var singleSpace: Space?
    var pairSpaceSummary: PairSpaceSummary?
    var availableModeStates: [AppMode] = [.single]
    var pairingContext = PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
    var sharedSyncStatus: SharedSyncStatus = .idle
    private(set) var sharedMutationSnapshots: [SharedMutationRecordKey: SyncMutationSnapshot] = [:]

    var activeMode: AppMode {
        get { selectedWorkspace.appMode }
        set { switchWorkspace(to: newValue == .pair ? .pair : .single) }
    }

    var currentSpace: Space? {
        switch selectedWorkspace {
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

    var pairBindingState: PairBindingState {
        if let pairSpace = currentPairSpace, pairSpace.status == .active {
            let hasCloudMetadata = pairSpace.cloudKitZoneName?.isEmpty == false
                && pairSpace.ownerRecordID?.isEmpty == false
            return hasCloudMetadata ? .pairedReady : .pairMetadataPending
        }
        switch pairingContext.state {
        case .singleTrial:
            return .unpaired
        case .invitePending:
            return .invitePending
        case .inviteReceived:
            return .inviteReceived
        case .paired:
            return .pairMetadataPending
        case .unbound:
            return .unbound
        }
    }

    var currentPairSpace: PairSpace? {
        pairSpaceSummary?.pairSpace
    }

    var hasActivePairSpace: Bool {
        currentPairSpace?.status == .active
    }

    var isViewingPairSpace: Bool {
        selectedWorkspace == .pair && hasActivePairSpace
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

    func switchWorkspace(to selection: WorkspaceSelection) {
        guard availableModeStates.contains(selection.appMode) else { return }
        guard selection == .single || hasActivePairSpace else { return }
        selectedWorkspace = selection
    }

    func switchMode(to mode: AppMode) {
        guard availableModeStates.contains(mode) else { return }
        guard mode == .single || hasActivePairSpace else { return }
        selectedWorkspace = mode == .pair ? .pair : .single
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
        selectedWorkspace = .single
    }

    func applySpaceAndPairing(
        spaceContext: SpaceContext,
        pairingContext: PairingContext
    ) {
        let previousSharedSpaceID = pairSpaceSummary?.sharedSpace.id
        singleSpace = spaceContext.singleSpace
        let resolvedPairSummary = spaceContext.pairSpaceSummary ?? pairingContext.pairSpaceSummary
        pairSpaceSummary = resolvedPairSummary
        availableModeStates = resolvedPairSummary?.pairSpace.status == .active ? [.single, .pair] : [.single]
        self.pairingContext = PairingContext(
            state: pairingContext.state,
            pairSpaceSummary: resolvedPairSummary,
            activeInvite: pairingContext.activeInvite
        )
        if availableModeStates.contains(selectedWorkspace.appMode) == false {
            selectedWorkspace = .single
        }
        if resolvedPairSummary?.sharedSpace.id != previousSharedSpaceID {
            sharedMutationSnapshots = [:]
        }
    }

    func applyPairingContext(_ pairingContext: PairingContext, autoSwitchToPairWhenBound: Bool = false) {
        let previousSharedSpaceID = pairSpaceSummary?.sharedSpace.id
        let resolvedPairSummary = pairingContext.pairSpaceSummary
        pairSpaceSummary = resolvedPairSummary
        availableModeStates = resolvedPairSummary?.pairSpace.status == .active ? [.single, .pair] : [.single]
        self.pairingContext = PairingContext(
            state: pairingContext.state,
            pairSpaceSummary: resolvedPairSummary,
            activeInvite: pairingContext.activeInvite
        )
        if resolvedPairSummary == nil, selectedWorkspace == .pair {
            selectedWorkspace = .single
        } else if autoSwitchToPairWhenBound, pairingContext.state == .paired, resolvedPairSummary != nil {
            selectedWorkspace = .pair
        } else if availableModeStates.contains(selectedWorkspace.appMode) == false {
            selectedWorkspace = .single
        }
        if resolvedPairSummary?.sharedSpace.id != previousSharedSpaceID {
            sharedMutationSnapshots = [:]
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

    func updateSharedSyncStatus(_ status: SharedSyncStatus) {
        sharedSyncStatus = status
    }

    func updateSharedMutationSnapshots(_ snapshots: [SharedMutationRecordKey: SyncMutationSnapshot]) {
        sharedMutationSnapshots = snapshots
    }

    func sharedMutationSnapshot(
        entityKind: SyncEntityKind,
        recordID: UUID
    ) -> SyncMutationSnapshot? {
        sharedMutationSnapshots[
            SharedMutationRecordKey(entityKind: entityKind, recordID: recordID)
        ]
    }

    func sharedMutationDisplayState(
        entityKind: SyncEntityKind,
        recordID: UUID,
        now: Date = .now
    ) -> SharedMutationDisplayState? {
        guard let snapshot = sharedMutationSnapshot(entityKind: entityKind, recordID: recordID) else {
            return nil
        }
        return SharedMutationDisplayState.resolve(from: snapshot, now: now)
    }

    func clearForSignOut() {
        authState = .signedOut
        currentUser = nil
        singleSpace = nil
        pairSpaceSummary = nil
        availableModeStates = [.single]
        pairingContext = PairingContext(state: .singleTrial, pairSpaceSummary: nil, activeInvite: nil)
        selectedWorkspace = .single
        sharedSyncStatus = .idle
        sharedMutationSnapshots = [:]
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
        selectedWorkspace = .single
        sharedSyncStatus = .idle
        sharedMutationSnapshots = [:]
    }
}
