import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
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

    func switchWorkspace(to selection: WorkspaceSelection) {
        selectedWorkspace = .single
    }

    func switchMode(to mode: AppMode) {
        selectedWorkspace = .single
    }

    func refresh(spaceContext: SpaceContext) {
        applySpace(spaceContext)
    }

    func applyPersonalIdentity(user: User, space: Space) {
        currentUser = user
        applySpace(SpaceContext(singleSpace: space, activeMode: .single, availableModes: [.single]))
        selectedWorkspace = .single
    }

    func applySpaceContext(_ spaceContext: SpaceContext) {
        applySpace(spaceContext)
    }

    func seedMock(currentUser: User, singleSpace: Space) {
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
