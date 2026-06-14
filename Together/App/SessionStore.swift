import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    var authState: AuthState = .signedOut
    var isAppLocked: Bool = false
    var currentUser: User? {
        didSet {
            guard oldValue != currentUser else { return }
            userProfileRevision = UUID()
        }
    }
    var userProfileRevision = UUID()
    var selectedWorkspace: WorkspaceSelection = .single
    var singleSpace: Space?
    var availableModeStates: [AppMode] = [.single]

    var activeMode: AppMode {
        get { .single }
        set { selectedWorkspace = .single }
    }

    var currentSpace: Space? {
        singleSpace
    }

    var availableSpaces: [Space] {
        [singleSpace].compactMap { $0 }
    }

    func bootstrap(
        authService: AuthServiceProtocol,
        spaceService: SpaceServiceProtocol
    ) async {
        let session = await authService.currentSession()
        let spaceContext = await spaceService.currentSpaceContext(for: session.user?.id)
        applyBootstrap(session: session, spaceContext: spaceContext)
    }

    func handleSignIn(session: AuthSession) {
        authState = session.state
        currentUser = session.user
    }

    func switchWorkspace(to selection: WorkspaceSelection) {
        selectedWorkspace = .single
    }

    func switchMode(to mode: AppMode) {
        selectedWorkspace = .single
    }

    func refresh(spaceContext: SpaceContext) {
        applySpace(spaceContext)
    }

    func applyBootstrap(session: AuthSession, spaceContext: SpaceContext) {
        authState = session.state
        currentUser = session.user
        applySpace(spaceContext)
        selectedWorkspace = .single
    }

    func applySpaceContext(_ spaceContext: SpaceContext) {
        applySpace(spaceContext)
    }

    func clearForSignOut() {
        authState = .signedOut
        currentUser = nil
        singleSpace = nil
        availableModeStates = [.single]
        selectedWorkspace = .single
    }

    func seedMock(currentUser: User, singleSpace: Space) {
        authState = .signedIn
        self.currentUser = currentUser
        self.singleSpace = singleSpace
        availableModeStates = [.single]
        selectedWorkspace = .single
    }

    private func applySpace(_ spaceContext: SpaceContext) {
        singleSpace = spaceContext.singleSpace
        availableModeStates = [.single]
        selectedWorkspace = .single
    }
}
