import Foundation
import OSLog

@MainActor
final class AnniversaryWidgetSnapshotWriter {
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "AnniversaryWidgetSnapshot")
    private let repository: ImportantDateRepositoryProtocol
    private let snapshotStore: AnniversaryWidgetSnapshotStore
    private let builder: AnniversaryWidgetSnapshotBuilder

    init(
        repository: ImportantDateRepositoryProtocol,
        snapshotStore: AnniversaryWidgetSnapshotStore? = nil,
        builder: AnniversaryWidgetSnapshotBuilder? = nil
    ) {
        self.repository = repository
        self.snapshotStore = snapshotStore ?? AnniversaryWidgetSnapshotStore()
        self.builder = builder ?? AnniversaryWidgetSnapshotBuilder()
    }

    func refreshAnniversaryWidgetSnapshot(
        currentUser: User?,
        pairSummary: PairSpaceSummary?
    ) async throws {
        guard
            let currentUser,
            let pairSummary,
            pairSummary.pairSpace.status == .active
        else {
            let snapshot = AnniversaryWidgetSnapshot.empty
            try snapshotStore.write(snapshot)
            logSnapshotWrite(snapshot)
            return
        }

        let records = try await repository.fetchAllStoredRecords(spaceID: pairSummary.sharedSpace.id)
        let snapshot = builder.build(
            currentUser: currentUser,
            partner: pairSummary.partner,
            records: records,
            referenceDate: .now
        )
        try snapshotStore.write(snapshot)
        logSnapshotWrite(snapshot)
    }

    private func logSnapshotWrite(_ snapshot: AnniversaryWidgetSnapshot) {
        let avatarBytes = snapshot.avatars.reduce(0) { partial, avatar in
            partial + (avatar.imageData?.count ?? 0)
        }
        logger.info(
            "[AnniversaryWidgetSnapshot] wrote path=\(self.snapshotStore.diagnosticFilePath, privacy: .public) exists=\(self.snapshotStore.fileExistsForDiagnostics) paired=\(snapshot.isPaired) hasStartDate=\(snapshot.startDate != nil) avatars=\(snapshot.avatars.count) avatarBytes=\(avatarBytes)"
        )
    }
}
