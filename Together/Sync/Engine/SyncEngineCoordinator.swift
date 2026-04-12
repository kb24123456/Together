import CloudKit
import CryptoKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "SyncEngineCoordinator")

/// Central coordinator for all CKSyncEngine instances.
///
/// Manages one engine for the `solo` zone (single-mode data) and one engine
/// per active pair space via `PairSyncBridge`. Each pair bridge couples a
/// private-zone CKSyncEngine with a `SyncRelayGateway` for cross-user sync.
///
/// ## Architecture
/// ```
/// SyncEngineCoordinator
/// ├── soloEngine        (CKSyncEngine, private zone "solo")
/// └── pairBridges       (PairSyncBridge per active pair space)
///     ├── engine         (CKSyncEngine, private zone "pair-<id>")
///     └── relayGateway   (SyncRelayGateway, public DB relay)
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

    /// Relay subscription manager for push notifications on new relay records.
    private var relaySubscriptionManager: SyncRelaySubscriptionManager?

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

    /// Starts sync for a pair space: creates CKSyncEngine + SyncRelayGateway bridge.
    ///
    /// - Parameters:
    ///   - pairSpaceID: The pair space identifier.
    ///   - myUserID: The current user's UUID.
    ///   - inviterID: The inviter (memberA) user ID — used for key derivation.
    ///   - responderID: The responder (memberB) user ID — used for key derivation.
    func startPairSync(
        pairSpaceID: UUID,
        myUserID: UUID,
        inviterID: UUID,
        responderID: UUID
    ) {
        guard pairBridges[pairSpaceID] == nil else {
            logger.info("[Coordinator] Pair engine already running for \(pairSpaceID.uuidString.prefix(8))")
            return
        }

        let zoneID = Self.pairZoneID(for: pairSpaceID)

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
            database: ckContainer.privateCloudDatabase,
            stateSerialization: stateSerialization,
            delegate: delegate
        )
        let engine = CKSyncEngine(configuration)

        // Ensure the pair zone exists
        engine.state.add(pendingDatabaseChanges: [
            .saveZone(CKRecordZone(zoneID: zoneID))
        ])

        // 3. Derive or load encryption key
        let encryptionKey = RelayKeyManager.loadOrDerive(
            pairSpaceID: pairSpaceID,
            inviterID: inviterID,
            responderID: responderID
        )

        // 4. Create SyncRelayGateway
        let lastSentSeq = loadLastSentSequence(for: pairSpaceID)
        let relayGateway = SyncRelayGateway(
            container: ckContainer,
            pairSpaceID: pairSpaceID,
            myUserID: myUserID,
            encryptionKey: encryptionKey,
            healthMonitor: healthMonitor,
            lastSequence: lastSentSeq
        )

        // 5. Create PairSyncBridge (wires relay posting automatically)
        let bridge = PairSyncBridge(
            pairSpaceID: pairSpaceID,
            engine: engine,
            delegate: delegate,
            relayGateway: relayGateway,
            zoneID: zoneID,
            modelContainer: modelContainer,
            codecRegistry: codecRegistry
        )

        pairBridges[pairSpaceID] = bridge

        // 6. Subscribe to relay push notifications
        Task {
            await ensureRelaySubscriptionManager(myUserID: myUserID)
            try? await relaySubscriptionManager?.subscribe(pairSpaceID: pairSpaceID)
        }

        // 7. Initial relay fetch (catch up on anything missed while offline)
        Task {
            await bridge.fetchAndApplyRelays()
            await bridge.retryFailedRelays()
        }

        logger.info("[Coordinator] ✅ Pair CKSyncEngine + Relay started for \(pairSpaceID.uuidString.prefix(8))")
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

        Task {
            try? await relaySubscriptionManager?.unsubscribe(pairSpaceID: pairSpaceID)
        }

        logger.info("[Coordinator] Pair CKSyncEngine stopped for \(pairSpaceID.uuidString.prefix(8))")
    }

    /// Stops pair sync and deletes the encryption key (for unbind).
    func teardownPairSync(pairSpaceID: UUID) {
        stopPairSync(pairSpaceID: pairSpaceID)
        RelayKeyManager.deleteKey(for: pairSpaceID)
        logger.info("[Coordinator] Pair sync torn down for \(pairSpaceID.uuidString.prefix(8))")
    }

    /// Fetches and applies new relay messages for a specific pair space.
    /// Called on relay push notification or periodic poll.
    @discardableResult
    func fetchRelays(for pairSpaceID: UUID) async -> Int {
        guard let bridge = pairBridges[pairSpaceID] else {
            logger.warning("[Coordinator] No bridge for space \(pairSpaceID.uuidString.prefix(8)) on relay fetch")
            return 0
        }
        return await bridge.fetchAndApplyRelays()
    }

    /// Retries any failed relay posts for a pair space.
    func retryRelays(for pairSpaceID: UUID) async {
        await pairBridges[pairSpaceID]?.retryFailedRelays()
    }

    /// Triggers relay cleanup (delete old records) for a pair space.
    func cleanupRelays(for pairSpaceID: UUID) async {
        guard let bridge = pairBridges[pairSpaceID] else { return }
        try? await bridge.relayGateway.cleanupOldRelays()
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
            // Register the record type so the delegate can relay the deletion
            if let delegate = delegateFor(zoneID) {
                delegate.registerPendingDeletion(
                    recordName: recordID.recordName,
                    recordType: change.entityKind.ckRecordType
                )
            }
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        case .upsert, .complete, .archive:
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        }

        healthMonitor.updateZone(zoneID.zoneName) { $0.pendingChangeCount += 1 }

        #if DEBUG
        logger.debug("[Coordinator] Queued \(change.operation.rawValue) for \(change.entityKind.rawValue)/\(change.recordID.uuidString.prefix(8)) in \(zoneID.zoneName)")
        #endif
    }

    // MARK: - Relay Push Notification Handling

    /// Handles a relay push notification by extracting the pairSpaceID and fetching new relays.
    /// Returns the number of changes applied, or 0 if the notification wasn't for a relay.
    @discardableResult
    func handleRelayNotification(subscriptionID: String) async -> Int {
        guard let manager = relaySubscriptionManager else { return 0 }
        guard let pairSpaceID = await manager.pairSpaceID(for: subscriptionID) else {
            return 0
        }
        return await fetchRelays(for: pairSpaceID)
    }

    /// Handles a relay push notification and returns whether it was processed.
    func isRelaySubscription(_ subscriptionID: String) async -> Bool {
        guard let manager = relaySubscriptionManager else { return false }
        return await manager.pairSpaceID(for: subscriptionID) != nil
    }

    // MARK: - Account Change

    /// Handles iCloud account change by stopping all engines.
    func handleAccountChange() {
        stopSoloSync()
        let pairIDs = Array(pairBridges.keys)
        for id in pairIDs {
            stopPairSync(pairSpaceID: id)
        }
        relaySubscriptionManager = nil
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

    private func loadLastSentSequence(for pairSpaceID: UUID) -> Int64 {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentRelaySequence>(
            predicate: #Predicate<PersistentRelaySequence> { $0.pairSpaceID == pairSpaceID }
        )
        return (try? context.fetch(descriptor).first?.lastSentSequence) ?? 0
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

        // Check if this spaceID matches any active pair bridge
        if pairBridges[change.spaceID] != nil {
            return Self.pairZoneID(for: change.spaceID)
        }

        // Default: route to solo zone
        return Self.soloZoneID
    }

    private func ensureRelaySubscriptionManager(myUserID: UUID) async {
        guard relaySubscriptionManager == nil else { return }
        relaySubscriptionManager = SyncRelaySubscriptionManager(
            container: ckContainer,
            myUserID: myUserID
        )
    }
}
