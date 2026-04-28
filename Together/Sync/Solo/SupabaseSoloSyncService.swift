import Foundation
import SwiftData
import os

enum SoloSyncServiceError: Error, Equatable {
    case requiresPro
    case missingSingleSpace
    case missingLocalRow(entityKind: String, recordID: UUID)
}

actor SupabaseSoloSyncService {
    static let sendingRecoveryStaleInterval: TimeInterval = 5 * 60

    private let modelContainer: ModelContainer
    private let remote: SupabaseSoloRemoteGatewayProtocol
    private let metadata: SoloSyncMetadataStore
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "SupabaseSoloSync")
    private let installationIDProvider: @Sendable () -> UUID
    private let appVersionProvider: @Sendable () -> String?
    private let buildNumberProvider: @Sendable () -> String?

    init(
        modelContainer: ModelContainer,
        remote: SupabaseSoloRemoteGatewayProtocol = SupabaseSoloRemoteGateway(),
        metadata: SoloSyncMetadataStore = SoloSyncMetadataStore(),
        installationIDProvider: @escaping @Sendable () -> UUID = { InstallationIDStore.current },
        appVersionProvider: @escaping @Sendable () -> String? = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        },
        buildNumberProvider: @escaping @Sendable () -> String? = {
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        }
    ) {
        self.modelContainer = modelContainer
        self.remote = remote
        self.metadata = metadata
        self.installationIDProvider = installationIDProvider
        self.appVersionProvider = appVersionProvider
        self.buildNumberProvider = buildNumberProvider
    }

    func start(
        userID: UUID,
        localUserID: UUID,
        displayName: String,
        platform: SoloDevicePlatform,
        isPro: Bool
    ) async throws {
        guard SoloSyncGate.decision(platform: platform, isPro: isPro) == .allowed else {
            throw SoloSyncServiceError.requiresPro
        }

        let spaceID = try await remote.ensureSingleSpace(userID: userID, displayName: displayName)
        try reconcileLocalSingleSpace(remoteSpaceID: spaceID, userID: localUserID, displayName: displayName)
        try await remote.registerDevice(DeviceInstallationUpsertDTO(
            userID: userID,
            installationID: installationIDProvider(),
            platform: platform,
            deviceName: nil,
            appVersion: appVersionProvider(),
            buildNumber: buildNumberProvider()
        ))

        switch try classifyLocalState(spaceID: spaceID) {
        case .freshInstall:
            try await fullPull(spaceID: spaceID)
        case .needsBootstrap:
            try await bootstrapLocalData(spaceID: spaceID, userID: userID)
        case .hasBaseline:
            try await pushPending(spaceID: spaceID, userID: userID)
            try await pullDeltas(spaceID: spaceID)
        }
    }

    func pushPending(spaceID: UUID, userID: UUID) async throws {
        let context = ModelContext(modelContainer)
        try resurrectSendingChanges(spaceID: spaceID, context: context)

        let pendingRaw = SyncMutationLifecycleState.pending.rawValue
        let failedRaw = SyncMutationLifecycleState.failed.rawValue
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> {
                $0.spaceID == spaceID &&
                ($0.lifecycleStateRawValue == pendingRaw || $0.lifecycleStateRawValue == failedRaw)
            },
            sortBy: [SortDescriptor(\PersistentSyncChange.changedAt, order: .forward)]
        )

        let changes = try context.fetch(descriptor)
        guard changes.isEmpty == false else { return }

        var outboundChanges: [PersistentSyncChange] = []
        do {
            let buildResult = try makePendingSnapshot(from: changes, spaceID: spaceID, userID: userID, context: context)
            outboundChanges = buildResult.outboundChanges
            let failedAt = Date()
            for failedChange in buildResult.failedChanges {
                failedChange.change.lifecycleState = .failed
                failedChange.change.lastAttemptedAt = failedChange.change.lastAttemptedAt ?? failedAt
                failedChange.change.lastError = failedChange.message
            }
            if buildResult.failedChanges.isEmpty == false {
                try context.save()
            }

            let snapshot = buildResult.snapshot
            guard snapshot.hasRows else { return }

            let attemptedAt = Date()
            for change in outboundChanges {
                change.lifecycleState = .sending
                change.lastAttemptedAt = attemptedAt
                change.lastError = nil
            }
            try context.save()

            try await remote.upsert(snapshot: snapshot)

            for change in outboundChanges {
                context.delete(change)
            }
            try context.save()
            metadata.setLastPushedAt(Date(), spaceID: spaceID)
        } catch {
            try markFailed(outboundChanges.isEmpty ? changes : outboundChanges, error: error, context: context)
            throw error
        }
    }
}

private enum SoloLocalState {
    case freshInstall
    case needsBootstrap
    case hasBaseline
}

private enum InstallationIDStore {
    private static let key = "together.installationID"

    static var current: UUID {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}

private extension SoloRemoteSnapshot {
    var hasRows: Bool {
        tasks.isEmpty == false ||
        taskLists.isEmpty == false ||
        projects.isEmpty == false ||
        projectSubtasks.isEmpty == false ||
        periodicTasks.isEmpty == false ||
        importantDates.isEmpty == false
    }
}

private extension SupabaseSoloSyncService {
    struct PendingSnapshotBuildResult {
        struct FailedChange {
            let change: PersistentSyncChange
            let message: String
        }

        var snapshot = SoloRemoteSnapshot()
        var outboundChanges: [PersistentSyncChange] = []
        var failedChanges: [FailedChange] = []

        mutating func markMissing(_ change: PersistentSyncChange) {
            failedChanges.append(.init(
                change: change,
                message: String(describing: SoloSyncServiceError.missingLocalRow(
                    entityKind: change.entityKindRawValue,
                    recordID: change.recordID
                ))
            ))
        }
    }

    static func supportsSoloPush(entityKindRawValue: String) -> Bool {
        switch SyncEntityKind(rawValue: entityKindRawValue) {
        case .task, .taskList, .project, .projectSubtask, .periodicTask, .importantDate:
            return true
        case .space, .memberProfile, .avatarAsset, .taskMessage, nil:
            return false
        }
    }

    func makePendingSnapshot(
        from changes: [PersistentSyncChange],
        spaceID: UUID,
        userID: UUID,
        context: ModelContext
    ) throws -> PendingSnapshotBuildResult {
        var result = PendingSnapshotBuildResult()

        for change in changes {
            guard let entityKind = SyncEntityKind(rawValue: change.entityKindRawValue) else {
                result.failedChanges.append(.init(
                    change: change,
                    message: "unsupported solo sync entity kind: \(change.entityKindRawValue)"
                ))
                continue
            }

            switch entityKind {
            case .task:
                guard let task = try fetchTask(id: change.recordID, context: context),
                      task.spaceID == spaceID else {
                    result.markMissing(change)
                    continue
                }
                result.snapshot.tasks.append(TaskDTO(from: task, spaceID: spaceID, supabaseUserID: userID))
                result.outboundChanges.append(change)

            case .taskList:
                guard let taskList = try fetchTaskList(id: change.recordID, context: context),
                      taskList.spaceID == spaceID else {
                    result.markMissing(change)
                    continue
                }
                result.snapshot.taskLists.append(TaskListDTO(from: taskList, spaceID: spaceID))
                result.outboundChanges.append(change)

            case .project:
                guard let project = try fetchProject(id: change.recordID, context: context),
                      project.spaceID == spaceID else {
                    result.markMissing(change)
                    continue
                }
                result.snapshot.projects.append(ProjectDTO(from: project, spaceID: spaceID))
                result.outboundChanges.append(change)

            case .projectSubtask:
                guard let subtask = try fetchProjectSubtask(id: change.recordID, context: context),
                      let project = try fetchProject(id: subtask.projectID, context: context),
                      project.spaceID == spaceID else {
                    result.markMissing(change)
                    continue
                }
                result.snapshot.projectSubtasks.append(ProjectSubtaskDTO(from: subtask, spaceID: spaceID))
                result.outboundChanges.append(change)

            case .periodicTask:
                guard let periodicTask = try fetchPeriodicTask(id: change.recordID, context: context),
                      periodicTask.spaceID == spaceID else {
                    result.markMissing(change)
                    continue
                }
                result.snapshot.periodicTasks.append(PeriodicTaskDTO(from: periodicTask, spaceID: spaceID))
                result.outboundChanges.append(change)

            case .importantDate:
                guard let importantDate = try fetchImportantDate(id: change.recordID, context: context),
                      importantDate.spaceID == spaceID else {
                    result.markMissing(change)
                    continue
                }
                result.snapshot.importantDates.append(ImportantDateDTO(from: importantDate))
                result.outboundChanges.append(change)

            case .space, .memberProfile, .avatarAsset, .taskMessage:
                result.failedChanges.append(.init(
                    change: change,
                    message: "unsupported solo sync entity kind: \(change.entityKindRawValue)"
                ))
            }
        }

        return result
    }

    func resurrectSendingChanges(spaceID: UUID, context: ModelContext) throws {
        let sendingRaw = SyncMutationLifecycleState.sending.rawValue
        let staleCutoff = Date().addingTimeInterval(-Self.sendingRecoveryStaleInterval)
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate<PersistentSyncChange> {
                $0.spaceID == spaceID && $0.lifecycleStateRawValue == sendingRaw
            }
        )
        let stuck = try context.fetch(descriptor).filter { change in
            guard let lastAttemptedAt = change.lastAttemptedAt else { return true }
            return lastAttemptedAt < staleCutoff
        }
        guard stuck.isEmpty == false else { return }
        for change in stuck {
            change.lifecycleState = .pending
        }
        try context.save()
        logger.info("[Recovery] Revived \(stuck.count) stuck solo sending changes")
    }

    func fetchTask(id: UUID, context: ModelContext) throws -> PersistentItem? {
        let recordID = id
        let descriptor = FetchDescriptor<PersistentItem>(predicate: #Predicate { $0.id == recordID })
        return try context.fetch(descriptor).first
    }

    func fetchTaskList(id: UUID, context: ModelContext) throws -> PersistentTaskList? {
        let recordID = id
        let descriptor = FetchDescriptor<PersistentTaskList>(predicate: #Predicate { $0.id == recordID })
        return try context.fetch(descriptor).first
    }

    func fetchProject(id: UUID, context: ModelContext) throws -> PersistentProject? {
        let recordID = id
        let descriptor = FetchDescriptor<PersistentProject>(predicate: #Predicate { $0.id == recordID })
        return try context.fetch(descriptor).first
    }

    func fetchProjectSubtask(id: UUID, context: ModelContext) throws -> PersistentProjectSubtask? {
        let recordID = id
        let descriptor = FetchDescriptor<PersistentProjectSubtask>(predicate: #Predicate { $0.id == recordID })
        return try context.fetch(descriptor).first
    }

    func fetchPeriodicTask(id: UUID, context: ModelContext) throws -> PersistentPeriodicTask? {
        let recordID = id
        let descriptor = FetchDescriptor<PersistentPeriodicTask>(predicate: #Predicate { $0.id == recordID })
        return try context.fetch(descriptor).first
    }

    func fetchImportantDate(id: UUID, context: ModelContext) throws -> PersistentImportantDate? {
        let recordID = id
        let descriptor = FetchDescriptor<PersistentImportantDate>(predicate: #Predicate { $0.id == recordID })
        return try context.fetch(descriptor).first
    }

    func markFailed(
        _ changes: [PersistentSyncChange],
        error: Error,
        context: ModelContext
    ) throws {
        let message = String(describing: error)
        let attemptedAt = Date()
        for change in changes {
            change.lifecycleState = .failed
            change.lastAttemptedAt = change.lastAttemptedAt ?? attemptedAt
            change.lastError = message
        }
        try context.save()
    }

    func reconcileLocalSingleSpace(remoteSpaceID: UUID, userID: UUID, displayName: String) throws {
        let context = ModelContext(modelContainer)
        let activeSingles = try context.fetch(FetchDescriptor<PersistentSpace>()).filter {
            $0.typeRawValue == SpaceType.single.rawValue &&
            $0.statusRawValue == SpaceStatus.active.rawValue
        }
        let activeSingleIDs = Set(activeSingles.map(\.id))
        let dataBearingSpaceID = try dataBearingSingleSpaceID(context: context, activeSingleIDs: activeSingleIDs)

        if let oldID = dataBearingSpaceID, oldID != remoteSpaceID {
            if let exact = activeSingles.first(where: { $0.id == remoteSpaceID }) {
                updateSingleSpace(exact, userID: userID, displayName: displayName)
                if let old = activeSingles.first(where: { $0.id == oldID }) {
                    context.delete(old)
                }
            } else if let old = activeSingles.first(where: { $0.id == oldID }) {
                old.id = remoteSpaceID
                updateSingleSpace(old, userID: userID, displayName: displayName)
            } else {
                insertSingleSpace(remoteSpaceID: remoteSpaceID, userID: userID, displayName: displayName, context: context)
            }
            try reassignSoloData(from: oldID, to: remoteSpaceID, context: context)
            try context.save()
            return
        }

        if let exact = activeSingles.first(where: { $0.id == remoteSpaceID }) {
            updateSingleSpace(exact, userID: userID, displayName: displayName)
            try context.save()
            return
        }

        insertSingleSpace(remoteSpaceID: remoteSpaceID, userID: userID, displayName: displayName, context: context)
        try context.save()
    }

    func updateSingleSpace(_ space: PersistentSpace, userID: UUID, displayName: String) {
        space.ownerUserID = userID
        if displayName.isEmpty == false {
            space.displayName = displayName
        } else if space.displayName.isEmpty {
            space.displayName = "我的空间"
        }
        space.typeRawValue = SpaceType.single.rawValue
        space.statusRawValue = SpaceStatus.active.rawValue
        space.updatedAt = .now
    }

    func insertSingleSpace(
        remoteSpaceID: UUID,
        userID: UUID,
        displayName: String,
        context: ModelContext
    ) {
        let now = Date()
        context.insert(PersistentSpace(
            space: Space(
                id: remoteSpaceID,
                type: .single,
                displayName: displayName.isEmpty ? "我的空间" : displayName,
                ownerUserID: userID,
                status: .active,
                createdAt: now,
                updatedAt: now
            )
        ))
    }

    func dataBearingSingleSpaceID(context: ModelContext, activeSingleIDs: Set<UUID>) throws -> UUID? {
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        if let spaceID = items.first(where: { item in
            guard let spaceID = item.spaceID else { return false }
            return activeSingleIDs.contains(spaceID) && !item.isLocallyDeleted
        })?.spaceID {
            return spaceID
        }

        let taskLists = try context.fetch(FetchDescriptor<PersistentTaskList>())
        if let spaceID = taskLists.first(where: {
            activeSingleIDs.contains($0.spaceID) && !$0.isLocallyDeleted
        })?.spaceID {
            return spaceID
        }

        let projects = try context.fetch(FetchDescriptor<PersistentProject>())
        if let spaceID = projects.first(where: {
            activeSingleIDs.contains($0.spaceID) && !$0.isLocallyDeleted
        })?.spaceID {
            return spaceID
        }

        let periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        if let spaceID = periodicTasks.first(where: { periodicTask in
            guard let spaceID = periodicTask.spaceID else { return false }
            return activeSingleIDs.contains(spaceID) && !periodicTask.isLocallyDeleted
        })?.spaceID {
            return spaceID
        }

        let importantDates = try context.fetch(FetchDescriptor<PersistentImportantDate>())
        return importantDates.first(where: {
            activeSingleIDs.contains($0.spaceID) && !$0.isLocallyDeleted
        })?.spaceID
    }

    func reassignSoloData(from oldSpaceID: UUID, to newSpaceID: UUID, context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<PersistentItem>()) where item.spaceID == oldSpaceID {
            item.spaceID = newSpaceID
        }
        for list in try context.fetch(FetchDescriptor<PersistentTaskList>()) where list.spaceID == oldSpaceID {
            list.spaceID = newSpaceID
        }
        for project in try context.fetch(FetchDescriptor<PersistentProject>()) where project.spaceID == oldSpaceID {
            project.spaceID = newSpaceID
        }
        for periodic in try context.fetch(FetchDescriptor<PersistentPeriodicTask>()) where periodic.spaceID == oldSpaceID {
            periodic.spaceID = newSpaceID
        }
        for date in try context.fetch(FetchDescriptor<PersistentImportantDate>()) where date.spaceID == oldSpaceID {
            date.spaceID = newSpaceID
        }
        for change in try context.fetch(FetchDescriptor<PersistentSyncChange>()) where change.spaceID == oldSpaceID {
            change.spaceID = newSpaceID
        }
    }

    func classifyLocalState(spaceID: UUID) throws -> SoloLocalState {
        if metadata.migrationCompletedAt(spaceID: spaceID) != nil {
            return .hasBaseline
        }

        let context = ModelContext(modelContainer)
        return try hasLocalData(spaceID: spaceID, context: context) ? .needsBootstrap : .freshInstall
    }

    func hasLocalData(spaceID: UUID, context: ModelContext) throws -> Bool {
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        if items.contains(where: { $0.spaceID == spaceID && !$0.isLocallyDeleted }) {
            return true
        }

        let taskLists = try context.fetch(FetchDescriptor<PersistentTaskList>())
        if taskLists.contains(where: { $0.spaceID == spaceID && !$0.isLocallyDeleted }) {
            return true
        }

        let projects = try context.fetch(FetchDescriptor<PersistentProject>())
        if projects.contains(where: { $0.spaceID == spaceID && !$0.isLocallyDeleted }) {
            return true
        }

        let periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        if periodicTasks.contains(where: { $0.spaceID == spaceID && !$0.isLocallyDeleted }) {
            return true
        }

        let importantDates = try context.fetch(FetchDescriptor<PersistentImportantDate>())
        return importantDates.contains(where: { $0.spaceID == spaceID && !$0.isLocallyDeleted })
    }

    func fullPull(spaceID: UUID) async throws {
        let snapshot = try await remote.fetchSnapshot(spaceID: spaceID, since: nil)
        try apply(snapshot: snapshot)
        let now = Date()
        metadata.setLastPulledAt(now, spaceID: spaceID)
        metadata.markMigrationCompleted(spaceID: spaceID, at: now, build: buildNumberProvider())
    }

    func bootstrapLocalData(spaceID: UUID, userID: UUID) async throws {
        let remoteSnapshot = try await remote.fetchSnapshot(spaceID: spaceID, since: nil)
        try apply(snapshot: remoteSnapshot)

        let localSnapshot = try makeLocalSnapshot(spaceID: spaceID, supabaseUserID: userID)
        try await remote.upsert(snapshot: localSnapshot)

        let now = Date()
        metadata.setLastPushedAt(now, spaceID: spaceID)
        metadata.setLastPulledAt(now, spaceID: spaceID)
        metadata.markMigrationCompleted(spaceID: spaceID, at: now, build: buildNumberProvider())
    }

    func makeLocalSnapshot(spaceID: UUID, supabaseUserID: UUID) throws -> SoloRemoteSnapshot {
        let context = ModelContext(modelContainer)
        var snapshot = SoloRemoteSnapshot()

        let taskLists = try context.fetch(FetchDescriptor<PersistentTaskList>())
        snapshot.taskLists = taskLists
            .filter { $0.spaceID == spaceID }
            .map { TaskListDTO(from: $0, spaceID: spaceID) }

        let projects = try context.fetch(FetchDescriptor<PersistentProject>())
        snapshot.projects = projects
            .filter { $0.spaceID == spaceID }
            .map { ProjectDTO(from: $0, spaceID: spaceID) }

        let projectIDs = Set(snapshot.projects.map(\.id))
        let projectSubtasks = try context.fetch(FetchDescriptor<PersistentProjectSubtask>())
        snapshot.projectSubtasks = projectSubtasks.compactMap { subtask in
            projectIDs.contains(subtask.projectID) ? ProjectSubtaskDTO(from: subtask, spaceID: spaceID) : nil
        }

        let periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>())
        snapshot.periodicTasks = periodicTasks
            .filter { $0.spaceID == spaceID }
            .map { PeriodicTaskDTO(from: $0, spaceID: spaceID) }

        let importantDates = try context.fetch(FetchDescriptor<PersistentImportantDate>())
        snapshot.importantDates = importantDates
            .filter { $0.spaceID == spaceID }
            .map(ImportantDateDTO.init(from:))

        let tasks = try context.fetch(FetchDescriptor<PersistentItem>())
        snapshot.tasks = tasks
            .filter { $0.spaceID == spaceID }
            .map { TaskDTO(from: $0, spaceID: spaceID, supabaseUserID: supabaseUserID) }

        return snapshot
    }

    func apply(snapshot: SoloRemoteSnapshot) throws {
        let context = ModelContext(modelContainer)
        for row in snapshot.taskLists {
            row.applyToLocal(context: context)
        }
        for row in snapshot.projects {
            row.applyToLocal(context: context)
        }
        for row in snapshot.projectSubtasks {
            row.applyToLocal(context: context)
        }
        for row in snapshot.periodicTasks {
            row.applyToLocal(context: context)
        }
        for row in snapshot.importantDates {
            row.applyToLocal(context: context)
        }
        for row in snapshot.tasks {
            row.applyToLocal(context: context)
        }
        try context.save()
    }

    func pullDeltas(spaceID: UUID) async throws {
        let snapshot = try await remote.fetchSnapshot(
            spaceID: spaceID,
            since: metadata.lastPulledAt(spaceID: spaceID)
        )
        try apply(snapshot: snapshot)
        metadata.setLastPulledAt(Date(), spaceID: spaceID)
    }
}
