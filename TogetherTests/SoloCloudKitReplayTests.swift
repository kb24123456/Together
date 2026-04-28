import CloudKit
import Foundation
import Testing
@testable import Together

struct SoloCloudKitReplayTests {
    @Test("solo startup sync sends pending changes before fetching remote changes")
    func soloStartupSyncSendsThenFetches() {
        #expect(SyncEngineCoordinator.startupSyncActionsForTesting == [.sendChanges, .fetchChanges])
    }

    @Test("solo replay only enqueues CloudKit-supported pending changes for the solo space")
    func soloReplayFiltersPendingChangesToSoloCloudKitEntities() {
        let soloSpaceID = UUID()
        let pairSpaceID = UUID()
        let taskID = UUID()
        let deletedProjectID = UUID()
        let pairTaskID = UUID()
        let importantDateID = UUID()
        let zoneID = CKRecordZone.ID(zoneName: "solo")

        let changes = [
            SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: soloSpaceID),
            SyncChange(entityKind: .project, operation: .delete, recordID: deletedProjectID, spaceID: soloSpaceID),
            SyncChange(entityKind: .task, operation: .upsert, recordID: pairTaskID, spaceID: pairSpaceID),
            SyncChange(entityKind: .importantDate, operation: .upsert, recordID: importantDateID, spaceID: soloSpaceID)
        ]

        let pendingChanges = SyncEngineCoordinator.makePendingRecordZoneChangesForTesting(
            from: changes,
            soloSpaceID: soloSpaceID,
            zoneID: zoneID
        )

        #expect(pendingChanges.count == 2)
        #expect(pendingChanges.containsSave(recordID: taskID, zoneID: zoneID))
        #expect(pendingChanges.containsDelete(recordID: deletedProjectID, zoneID: zoneID))
        #expect(!pendingChanges.containsSave(recordID: pairTaskID, zoneID: zoneID))
        #expect(!pendingChanges.containsSave(recordID: importantDateID, zoneID: zoneID))
    }
}

private extension [CKSyncEngine.PendingRecordZoneChange] {
    func containsSave(recordID: UUID, zoneID: CKRecordZone.ID) -> Bool {
        contains { change in
            guard case .saveRecord(let ckRecordID) = change else { return false }
            return ckRecordID.recordName == recordID.uuidString && ckRecordID.zoneID == zoneID
        }
    }

    func containsDelete(recordID: UUID, zoneID: CKRecordZone.ID) -> Bool {
        contains { change in
            guard case .deleteRecord(let ckRecordID) = change else { return false }
            return ckRecordID.recordName == recordID.uuidString && ckRecordID.zoneID == zoneID
        }
    }
}
