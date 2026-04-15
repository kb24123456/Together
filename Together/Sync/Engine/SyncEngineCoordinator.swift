import CloudKit
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.pigdog.Together", category: "SyncEngineCoordinator")

/// Central coordinator for the solo CKSyncEngine instance.
///
/// Manages one engine for the `solo` zone (single-mode data, multi-device sync).
/// Pair sync is handled separately by `PairSyncService` using CloudKit Public DB.
actor SyncEngineCoordinator {

    // MARK: - Dependencies

    private let ckContainer: CKContainer
    private let modelContainer: ModelContainer
    private let codecRegistry: RecordCodecRegistry
    nonisolated let healthMonitor: SyncHealthMonitor

    // MARK: - Engines

    private var soloEngine: CKSyncEngine?
    private var soloDelegate: SyncEngineDelegate?

    /// Per-zone debounced immediate send tasks.
    private var immediateSendTasks: [String: Task<Void, Never>] = [:]

    /// Known solo space ID (set externally so we can route changes correctly).
    private var soloSpaceID: UUID?

    // MARK: - Zone IDs

    static let soloZoneID = CKRecordZone.ID(zoneName: "solo")

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
        immediateSendTasks.removeValue(forKey: Self.soloZoneID.zoneName)?.cancel()
        soloEngine = nil
        soloDelegate = nil
        logger.info("[Coordinator] Solo CKSyncEngine stopped")
    }

    // MARK: - Record Local Changes

    /// Records a local mutation that needs to be pushed to CloudKit.
    func recordChange(_ change: SyncChange) async {
        let zoneID = Self.soloZoneID

        guard let engine = soloEngine else {
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
        scheduleImmediateSend(for: zoneID, engine: engine)
    }

    // MARK: - Account Change

    /// Handles iCloud account change by stopping the solo engine.
    func handleAccountChange() {
        stopSoloSync()
        for task in immediateSendTasks.values {
            task.cancel()
        }
        immediateSendTasks.removeAll()
        logger.info("[Coordinator] All engines stopped due to account change")
    }

    /// Sends pending local changes for the solo space immediately.
    func sendChanges(for spaceID: UUID) async {
        await sendChanges(for: Self.soloZoneID)
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
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            do {
                let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
                unarchiver.requiresSecureCoding = true
                let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
                unarchiver.finishDecoding()
                return result as? CKSyncEngine.State.Serialization
            } catch {
                logger.error("[Coordinator] Failed to decode state for \(zoneName): \(error)")
                return nil
            }
        }
    }

    // MARK: - Helpers

    private func scheduleImmediateSend(for zoneID: CKRecordZone.ID, engine: CKSyncEngine) {
        let key = zoneID.zoneName
        immediateSendTasks[key]?.cancel()
        immediateSendTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.sendChanges(for: zoneID, engine: engine)
        }
    }

    private func sendChanges(for zoneID: CKRecordZone.ID) async {
        guard let engine = soloEngine else { return }
        await sendChanges(for: zoneID, engine: engine)
    }

    private func sendChanges(for zoneID: CKRecordZone.ID, engine: CKSyncEngine) async {
        defer { immediateSendTasks.removeValue(forKey: zoneID.zoneName) }
        do {
            try await engine.sendChanges()
        } catch {
            healthMonitor.updateZone(zoneID.zoneName) {
                $0.consecutiveFailures += 1
                $0.lastSendError = error.localizedDescription
                $0.lastError = error.localizedDescription
            }
            logger.error("[Coordinator] Immediate send failed for \(zoneID.zoneName): \(error.localizedDescription)")
        }
    }
}
