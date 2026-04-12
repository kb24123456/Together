import CloudKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "SyncEngineCoordinator")

/// Central coordinator for all CKSyncEngine instances.
///
/// Manages one engine for the `solo` zone (single-mode data) and one engine
/// per active pair space via `PairSyncBridge`.
///
/// ## Architecture
/// ```
/// SyncEngineCoordinator
/// ├── soloEngine        (CKSyncEngine, private zone "solo")
/// └── pairBridges       (PairSyncBridge per active pair space)
///     └── engine         (CKSyncEngine over private/shared CloudKit DB)
/// ```
actor SyncEngineCoordinator {

    // MARK: - Dependencies

    private let ckContainer: CKContainer
    private let modelContainer: ModelContainer
    private let codecRegistry: RecordCodecRegistry
    nonisolated let healthMonitor: SyncHealthMonitor

    // MARK: - Engines

    private var soloEngine: CKSyncEngine?
    private var soloDelegate: SyncEngineDelegate?

    /// Active pair space bridges, keyed by pairSpaceID.
    private var pairBridges: [UUID: PairSyncBridge] = [:]

    /// Reverse mapping: sharedSpaceID → pairSpaceID.
    /// Tasks are created with sharedSpaceID but bridges are keyed by pairSpaceID.
    private var sharedToPairSpaceID: [UUID: UUID] = [:]

    /// Known solo space ID (set externally so we can route changes correctly).
    private var soloSpaceID: UUID?

    // MARK: - Zone IDs

    static let soloZoneID = CKRecordZone.ID(zoneName: "solo")

    static func pairZoneID(for pairSpaceID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "pair-\(pairSpaceID.uuidString)")
    }

    // MARK: - Init

    init(
        ckContainer: CKContainer,
        modelContainer: ModelContainer,
        healthMonitor: SyncHealthMonitor
    ) {
        self.ckContainer = ckContainer
        self.modelContainer = modelContainer
        self.codecRegistry = RecordCodecRegistry()
        self.healthMonitor = healthMonitor
    }

    // MARK: - Configuration

    /// Sets the solo space ID so the coordinator can route changes correctly.
    func configureSoloSpaceID(_ id: UUID) {
        self.soloSpaceID = id
    }

    // MARK: - Solo Zone

    /// Starts CKSyncEngine for the solo zone (single-mode data, multi-device sync).
    /// Called once at app launch after authentication.
    func startSoloSync() {
        guard soloEngine == nil else {
            logger.info("[Coordinator] Solo engine already running")
            return
        }

        let zoneID = Self.soloZoneID
        let delegate = SyncEngineDelegate(
            zoneID: zoneID,
            modelContainer: modelContainer,
            codecRegistry: codecRegistry,
            healthMonitor: healthMonitor
        )

        delegate.onRemoteChangesApplied = { count in
            logger.info("[Coordinator] Solo: \(count) remote changes applied")
        }

        let stateSerialization = loadStateSerialization(for: zoneID)

        let configuration = CKSyncEngine.Configuration(
            database: ckContainer.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: delegate
        )

        let engine = CKSyncEngine(configuration)

        // Ensure the solo zone exists
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID))
        ])

        self.soloEngine = engine
        self.soloDelegate = delegate

        logger.info("[Coordinator] ✅ Solo CKSyncEngine started")
    }

    /// Sets the callback invoked when remote changes are applied to the solo zone.
    func setSoloRemoteChangesCallback(_ callback: @escaping @Sendable (_ count: Int) -> Void) {
        soloDelegate?.onRemoteChangesApplied = callback
    }

    /// Stops the solo zone CKSyncEngine (e.g., on sign-out or account change).
    func stopSoloSync() {
        soloEngine = nil
        soloDelegate = nil
        logger.info("[Coordinator] Solo CKSyncEngine stopped")
    }

    // MARK: - Pair Zone

    /// Starts sync for a pair space using a single shared CloudKit authority zone.
    ///
    /// - Parameters:
    ///   - pairSpaceID: The pair space identifier.
    ///   - sharedSpaceID: The shared space identifier (used in task spaceID fields).
    ///   - myUserID: The current user's UUID.
    ///   - inviterID: The inviter (memberA) user ID — used for key derivation.
    ///   - responderID: The responder (memberB) user ID — used for key derivation.
    func startPairSync(
        pairSpaceID: UUID,
        sharedSpaceID: UUID,
        myUserID _: UUID,
        inviterID _: UUID,
        responderID _: UUID,
        isZoneOwner: Bool
    ) {
        guard pairBridges[pairSpaceID] == nil else {
            logger.info("[Coordinator] Pair engine already running for \(pairSpaceID.uuidString.prefix(8))")
            return
        }

        // Register reverse mapping so task changes (which carry sharedSpaceID) route correctly
        sharedToPairSpaceID[sharedSpaceID] = pairSpaceID

        let zoneID = Self.pairZoneID(for: pairSpaceID)
        let database = isZoneOwner ? ckContainer.privateCloudDatabase : ckContainer.sharedCloudDatabase

        // 1. Create SyncEngineDelegate for this pair zone
        let delegate = SyncEngineDelegate(
            zoneID: zoneID,
            modelContainer: modelContainer,
            codecRegistry: codecRegistry,
            healthMonitor: healthMonitor
        )

        delegate.onRemoteChangesApplied = { count in
            logger.info("[Coordinator] Pair \(pairSpaceID.uuidString.prefix(8)): \(count) remote changes applied")
        }

        // 2. Restore or create CKSyncEngine state
        let stateSerialization = loadStateSerialization(for: zoneID)
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: delegate
        )
        let engine = CKSyncEngine(configuration)

        if isZoneOwner {
            engine.state.add(pendingDatabaseChanges: [
                .saveZone(CKRecordZone(zoneID: zoneID))
            ])
        }

        // Pair data now lives in one shared authority zone; relay is disabled for pair sync.
        let bridge = PairSyncBridge(
            pairSpaceID: pairSpaceID,
            engine: engine,
            delegate: delegate,
            zoneID: zoneID,
            modelContainer: modelContainer,
            codecRegistry: codecRegistry
        )

        pairBridges[pairSpaceID] = bridge

        logger.info("[Coordinator] ✅ Pair CKSyncEngine started for \(pairSpaceID.uuidString.prefix(8)), owner=\(isZoneOwner)")
    }

    /// Sets the callback invoked when remote changes are applied to a pair zone.
    func setPairRemoteChangesCallback(
        pairSpaceID: UUID,
        callback: @escaping @Sendable (_ count: Int) -> Void
    ) {
        pairBridges[pairSpaceID]?.delegate.onRemoteChangesApplied = callback
    }

    /// Stops sync for a pair space and cleans up.
    func stopPairSync(pairSpaceID: UUID) {
        guard pairBridges.removeValue(forKey: pairSpaceID) != nil else { return }

        // Remove reverse mapping
        sharedToPairSpaceID = sharedToPairSpaceID.filter { $0.value != pairSpaceID }

        logger.info("[Coordinator] Pair CKSyncEngine stopped for \(pairSpaceID.uuidString.prefix(8))")
    }

    /// Stops pair sync for unbind / teardown.
    func teardownPairSync(pairSpaceID: UUID) {
        stopPairSync(pairSpaceID: pairSpaceID)
        logger.info("[Coordinator] Pair sync torn down for \(pairSpaceID.uuidString.prefix(8))")
    }

    // MARK: - Record Local Changes

    /// Records a local mutation that needs to be pushed to CloudKit.
    /// Routes to the correct zone based on spaceID.
    func recordChange(_ change: SyncChange) {
        let zoneID = zoneIDForChange(change)

        guard let engine = engineFor(zoneID) else {
            logger.warning("[Coordinator] No engine for zone \(zoneID.zoneName), change dropped")
            return
        }

        let recordID = CKRecord.ID(
            recordName: change.recordID.uuidString,
            zoneID: zoneID
        )

        switch change.operation {
        case .delete:
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        case .upsert, .complete, .archive:
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        }

        healthMonitor.updateZone(zoneID.zoneName) { $0.pendingChangeCount += 1 }

        logger.debug("[Coordinator] Queued \(change.operation.rawValue) for \(change.entityKind.rawValue)/\(change.recordID.uuidString.prefix(8)) in \(zoneID.zoneName)")
    }

    // MARK: - Account Change

    /// Handles iCloud account change by stopping all engines.
    func handleAccountChange() {
        stopSoloSync()
        let pairIDs = Array(pairBridges.keys)
        for id in pairIDs {
            stopPairSync(pairSpaceID: id)
        }
        sharedToPairSpaceID.removeAll()
        logger.info("[Coordinator] All engines stopped due to account change")
    }

    // MARK: - Active Pair Spaces

    /// Returns the IDs of all active pair spaces being synced.
    var activePairSpaceIDs: [UUID] {
        Array(pairBridges.keys)
    }

    /// Returns whether a pair space has an active sync bridge.
    func isPairSyncActive(for pairSpaceID: UUID) -> Bool {
        pairBridges[pairSpaceID] != nil
    }

    // MARK: - State Persistence

    /// Loads persisted CKSyncEngine state for resuming across app launches.
    private func loadStateSerialization(for zoneID: CKRecordZone.ID) -> CKSyncEngine.State.Serialization? {
        let context = ModelContext(modelContainer)
        let zoneName = zoneID.zoneName
        let descriptor = FetchDescriptor<PersistentSyncState>(
            predicate: #Predicate<PersistentSyncState> { $0.cursorToken == zoneName }
        )

        guard let state = try? context.fetch(descriptor).first,
              let data = state.serverChangeTokenData else {
            return nil
        }

        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
            return result as? CKSyncEngine.State.Serialization
        } catch {
            logger.error("[Coordinator] Failed to unarchive state for \(zoneName): \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private func delegateFor(_ zoneID: CKRecordZone.ID) -> SyncEngineDelegate? {
        if zoneID == Self.soloZoneID {
            return soloDelegate
        }
        for (_, bridge) in pairBridges where bridge.zoneID == zoneID {
            return bridge.delegate
        }
        return nil
    }

    private func engineFor(_ zoneID: CKRecordZone.ID) -> CKSyncEngine? {
        if zoneID == Self.soloZoneID {
            return soloEngine
        }
        // Look up pair bridge by matching zone name
        for (_, bridge) in pairBridges where bridge.zoneID == zoneID {
            return bridge.engine
        }
        return nil
    }

    /// Determines the zone ID for a given change based on its spaceID.
    private func zoneIDForChange(_ change: SyncChange) -> CKRecordZone.ID {
        // If the change's spaceID matches the solo space, route to solo zone
        if let soloID = soloSpaceID, change.spaceID == soloID {
            return Self.soloZoneID
        }

        // Direct match: spaceID is a pairSpaceID
        if pairBridges[change.spaceID] != nil {
            return Self.pairZoneID(for: change.spaceID)
        }

        // Reverse lookup: spaceID is a sharedSpaceID → resolve to pairSpaceID
        if let pairID = sharedToPairSpaceID[change.spaceID] {
            return Self.pairZoneID(for: pairID)
        }

        // Default: route to solo zone
        return Self.soloZoneID
    }
}
