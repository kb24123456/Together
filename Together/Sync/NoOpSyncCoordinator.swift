import Foundation

actor NoOpSyncCoordinator: SyncCoordinatorProtocol {
    func recordLocalChange(_ change: SyncChange) async {}
}
