import Foundation
import SwiftData

struct PersistenceController {
    let container: ModelContainer
    private static let legacyPeriodicDataCleanupKey = "didCleanupLegacyPeriodicData.v1"

    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    init(inMemory: Bool = false) {
        StartupTrace.mark("PersistenceController.init.begin inMemory=\(inMemory)")

        var firstError = ""

        // First attempt: open the existing store normally.
        if let resolved = Self.attemptFullInit(inMemory: inMemory, errorOut: &firstError) {
            self.container = resolved
            StartupTrace.mark("PersistenceController.init.end")
            return
        }

        StartupTrace.mark("PersistenceController.firstAttemptFailed=\(firstError)")

        guard inMemory == false else {
            fatalError("[Persistence] In-memory store failed: \(firstError)")
        }

        if Self.shouldAttemptLegacyRelayMigration(afterFailure: firstError) {
            var migrationError = ""
            if let migrated = Self.migrateLegacyRelayStoreIfNeeded(errorOut: &migrationError) {
                self.container = migrated
                StartupTrace.mark("PersistenceController.init.end.afterLegacyRelayMigration")
                return
            }
            if migrationError.isEmpty == false {
                let storePath = Self.persistentStoreURL.path(percentEncoded: false)
                fatalError("[Persistence] Legacy relay schema migration failed.\npath: \(storePath)\n1st: \(firstError)\nmigration: \(migrationError)")
            }
        }

        // Store is broken or schema is incompatible — nuke it and try fresh.
        Self.deleteStoreFiles()
        StartupTrace.mark("PersistenceController.storeReset")

        var secondError = ""
        if let resolved = Self.attemptFullInit(inMemory: false, errorOut: &secondError) {
            self.container = resolved
            StartupTrace.mark("PersistenceController.init.end.afterReset")
            return
        }

        // Both attempts failed — fatal. Print both errors so we can diagnose.
        let storePath = Self.persistentStoreURL.path(percentEncoded: false)
        fatalError("[Persistence] Failed even after store reset.\npath: \(storePath)\n1st: \(firstError)\n2nd: \(secondError)")
    }

    /// Creates the container AND exercises it (seed + cleanup) so that any lazy-load
    /// error (migration, corruption) is caught here rather than surfacing later.
    private static func attemptFullInit(inMemory: Bool, errorOut: inout String) -> ModelContainer? {
        let container: ModelContainer
        do {
            container = try makeContainer(inMemory: inMemory)
        } catch {
            errorOut = "makeContainer: \(error)"
            return nil
        }

        do {
            let probeContext = ModelContext(container)
            _ = try probeContext.fetchCount(FetchDescriptor<PersistentSpace>())
        } catch {
            errorOut = "probeStore: \(error)"
            return nil
        }

        do {
            try cleanupLegacyPeriodicDataIfNeeded(container: container, inMemory: inMemory)
        } catch {
            errorOut = "cleanupLegacy: \(error)"
            return nil
        }

        do {
            try seedIfNeeded(container: container)
        } catch {
            errorOut = "seedIfNeeded: \(error)"
            return nil
        }

        do {
            try injectDebugPairReviewFixtureIfNeeded(container: container)
        } catch {
            errorOut = "injectFixture: \(error)"
            return nil
        }

        return container
    }

    /// Removes all SQLite artefacts for the persistent store.
    private static func deleteStoreFiles() {
        let storeURL = persistentStoreURL
        let base = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.deletingPathExtension().lastPathComponent)
        for suffix in ["store", "store-shm", "store-wal"] {
            let url = base.appendingPathExtension(suffix)
            try? FileManager.default.removeItem(at: url)
        }
        // External-storage support directory (used by @Attribute(.externalStorage))
        let supportURL = URL(fileURLWithPath: storeURL.path + "_SUPPORT")
        try? FileManager.default.removeItem(at: supportURL)
    }

    private static func cleanupLegacyPeriodicDataIfNeeded(
        container: ModelContainer,
        inMemory: Bool
    ) throws {
        guard inMemory == false else { return }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: legacyPeriodicDataCleanupKey) == false else { return }

        let context = ModelContext(container)
        let periodicItems = try context.fetch(
            FetchDescriptor<PersistentItem>(
                predicate: #Predicate<PersistentItem> { $0.repeatRuleData != nil }
            )
        )
        let periodicTemplates = try context.fetch(
            FetchDescriptor<PersistentTaskTemplate>(
                predicate: #Predicate<PersistentTaskTemplate> { $0.repeatRuleData != nil }
            )
        )

        for record in periodicItems {
            context.delete(record)
        }

        for record in periodicTemplates {
            context.delete(record)
        }

        if periodicItems.isEmpty == false || periodicTemplates.isEmpty == false {
            try context.save()
        }

        defaults.set(true, forKey: legacyPeriodicDataCleanupKey)
    }

    private static func makeContainer(
        inMemory: Bool,
        includeLegacyRelayModels: Bool = false
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "TogetherStore",
                url: persistentStoreURL,
                cloudKitDatabase: .none
            )
        }

        if includeLegacyRelayModels {
            return try ModelContainer(
                for: PersistentUserProfile.self,
                PersistentSpace.self,
                PersistentPairSpace.self,
                PersistentPairMembership.self,
                PersistentInvite.self,
                PersistentTaskList.self,
                PersistentProject.self,
                PersistentProjectSubtask.self,
                PersistentItem.self,
                PersistentItemOccurrenceCompletion.self,
                PersistentTaskTemplate.self,
                PersistentSyncChange.self,
                PersistentSyncState.self,
                PersistentPeriodicTask.self,
                PersistentPairingHistory.self,
                PersistentSyncRelayQueue.self,
                PersistentRelaySequence.self,
                configurations: configuration
            )
        }

        return try ModelContainer(
            for: PersistentUserProfile.self,
            PersistentSpace.self,
            PersistentPairSpace.self,
            PersistentPairMembership.self,
            PersistentInvite.self,
            PersistentTaskList.self,
            PersistentProject.self,
            PersistentProjectSubtask.self,
            PersistentItem.self,
            PersistentItemOccurrenceCompletion.self,
            PersistentTaskTemplate.self,
            PersistentSyncChange.self,
            PersistentSyncState.self,
            PersistentPeriodicTask.self,
            PersistentPairingHistory.self,
            configurations: configuration
        )
    }

    private static func migrateLegacyRelayStoreIfNeeded(errorOut: inout String) -> ModelContainer? {
        let backupURL: URL
        do {
            backupURL = try backupStoreFiles()
        } catch {
            errorOut = "backupStoreFiles: \(error)"
            return nil
        }

        defer { try? FileManager.default.removeItem(at: backupURL) }

        let legacyContainer: ModelContainer
        do {
            legacyContainer = try makeContainer(inMemory: false, includeLegacyRelayModels: true)
        } catch {
            errorOut = "makeLegacyContainer: \(error)"
            restoreStoreFiles(from: backupURL)
            return nil
        }

        do {
            let probeContext = ModelContext(legacyContainer)
            _ = try probeContext.fetchCount(FetchDescriptor<PersistentSpace>())
        } catch {
            errorOut = "probeLegacyStore: \(error)"
            restoreStoreFiles(from: backupURL)
            return nil
        }

        let snapshot: StoreSnapshot
        do {
            snapshot = try captureSnapshot(from: legacyContainer)
        } catch {
            errorOut = "captureSnapshot: \(error)"
            restoreStoreFiles(from: backupURL)
            return nil
        }

        deleteStoreFiles()

        let migratedContainer: ModelContainer
        do {
            migratedContainer = try makeContainer(inMemory: false, includeLegacyRelayModels: false)
            try restoreSnapshot(snapshot, into: migratedContainer)
            try cleanupLegacyPeriodicDataIfNeeded(container: migratedContainer, inMemory: false)
            try seedIfNeeded(container: migratedContainer)
            try injectDebugPairReviewFixtureIfNeeded(container: migratedContainer)
            StartupTrace.mark("PersistenceController.legacyRelayMigrationSucceeded")
            return migratedContainer
        } catch {
            restoreStoreFiles(from: backupURL)
            errorOut = "restoreSnapshot: \(error)"
            return nil
        }
    }

    private static func shouldAttemptLegacyRelayMigration(afterFailure firstError: String) -> Bool {
        firstError.contains("PersistentSyncRelayQueue")
        || firstError.contains("PersistentRelaySequence")
        || firstError.contains("LegacyRelay")
    }

    private static var persistentStoreURL: URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory

        let directory = applicationSupportDirectory.appendingPathComponent("Together", isDirectory: true)

        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("Together.store")
    }

    private static var persistentStoreSupportURL: URL {
        URL(fileURLWithPath: persistentStoreURL.path + "_SUPPORT")
    }

    private static func backupStoreFiles() throws -> URL {
        let backupRoot = persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("MigrationBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let backupURL = backupRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)

        for source in storeArtifactURLs() where FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.copyItem(at: source, to: backupURL.appendingPathComponent(source.lastPathComponent))
        }

        return backupURL
    }

    private static func restoreStoreFiles(from backupURL: URL) {
        deleteStoreFiles()
        for artifact in storeArtifactURLs() {
            let backupArtifact = backupURL.appendingPathComponent(artifact.lastPathComponent)
            guard FileManager.default.fileExists(atPath: backupArtifact.path) else { continue }
            try? FileManager.default.copyItem(at: backupArtifact, to: artifact)
        }
    }

    private static func storeArtifactURLs() -> [URL] {
        let storeURL = persistentStoreURL
        let base = storeURL.deletingLastPathComponent()
            .appendingPathComponent(storeURL.deletingPathExtension().lastPathComponent)
        let sqliteURLs = ["store", "store-shm", "store-wal"].map { base.appendingPathExtension($0) }
        return sqliteURLs + [persistentStoreSupportURL]
    }

    private struct UserProfileSnapshot {
        let userID: UUID
        let displayName: String
        let avatarSystemName: String?
        let avatarPhotoFileName: String?
        let avatarAssetID: String?
        let avatarVersion: Int
        let avatarPhotoData: Data?
        let taskReminderEnabled: Bool
        let dailySummaryEnabled: Bool
        let calendarReminderEnabled: Bool
        let futureCollaborationInviteEnabled: Bool
        let taskUrgencyWindowMinutes: Int
        let defaultSnoozeMinutes: Int
        let quickTimePresetMinutes: [Int]
        let completedTaskAutoArchiveEnabled: Bool
        let completedTaskAutoArchiveDays: Int
        let updatedAt: Date

        init(_ profile: PersistentUserProfile) {
            userID = profile.userID
            displayName = profile.displayName
            avatarSystemName = profile.avatarSystemName
            avatarPhotoFileName = profile.avatarPhotoFileName
            avatarAssetID = profile.avatarAssetID
            avatarVersion = profile.avatarVersion
            avatarPhotoData = profile.avatarPhotoData
            taskReminderEnabled = profile.taskReminderEnabled
            dailySummaryEnabled = profile.dailySummaryEnabled
            calendarReminderEnabled = profile.calendarReminderEnabled
            futureCollaborationInviteEnabled = profile.futureCollaborationInviteEnabled
            taskUrgencyWindowMinutes = profile.taskUrgencyWindowMinutes
            defaultSnoozeMinutes = profile.defaultSnoozeMinutes
            quickTimePresetMinutes = profile.quickTimePresetMinutes
            completedTaskAutoArchiveEnabled = profile.completedTaskAutoArchiveEnabled
            completedTaskAutoArchiveDays = profile.completedTaskAutoArchiveDays
            updatedAt = profile.updatedAt
        }

        func makePersistent() -> PersistentUserProfile {
            PersistentUserProfile(
                userID: userID,
                displayName: displayName,
                avatarSystemName: avatarSystemName,
                avatarPhotoFileName: avatarPhotoFileName,
                avatarAssetID: avatarAssetID,
                avatarVersion: avatarVersion,
                avatarPhotoData: avatarPhotoData,
                taskReminderEnabled: taskReminderEnabled,
                dailySummaryEnabled: dailySummaryEnabled,
                calendarReminderEnabled: calendarReminderEnabled,
                futureCollaborationInviteEnabled: futureCollaborationInviteEnabled,
                taskUrgencyWindowMinutes: taskUrgencyWindowMinutes,
                defaultSnoozeMinutes: defaultSnoozeMinutes,
                quickTimePresetMinutes: quickTimePresetMinutes,
                completedTaskAutoArchiveEnabled: completedTaskAutoArchiveEnabled,
                completedTaskAutoArchiveDays: completedTaskAutoArchiveDays,
                updatedAt: updatedAt
            )
        }
    }

    private struct PairSpaceSnapshot {
        let id: UUID
        let sharedSpaceID: UUID
        let statusRawValue: String
        let createdAt: Date
        let activatedAt: Date?
        let endedAt: Date?
        let cloudKitZoneName: String?
        let ownerRecordID: String?
        let isZoneOwner: Bool

        init(_ pairSpace: PersistentPairSpace) {
            id = pairSpace.id
            sharedSpaceID = pairSpace.sharedSpaceID
            statusRawValue = pairSpace.statusRawValue
            createdAt = pairSpace.createdAt
            activatedAt = pairSpace.activatedAt
            endedAt = pairSpace.endedAt
            cloudKitZoneName = pairSpace.cloudKitZoneName
            ownerRecordID = pairSpace.ownerRecordID
            isZoneOwner = pairSpace.isZoneOwner
        }

        func makePersistent() -> PersistentPairSpace {
            PersistentPairSpace(
                id: id,
                sharedSpaceID: sharedSpaceID,
                statusRawValue: statusRawValue,
                displayName: nil,
                createdAt: createdAt,
                activatedAt: activatedAt,
                endedAt: endedAt,
                cloudKitZoneName: cloudKitZoneName,
                ownerRecordID: ownerRecordID,
                isZoneOwner: isZoneOwner
            )
        }
    }

    private struct PairMembershipSnapshot {
        let id: UUID
        let pairSpaceID: UUID
        let userID: UUID
        let nickname: String
        let joinedAt: Date
        let avatarSystemName: String?
        let avatarPhotoFileName: String?
        let avatarAssetID: String?
        let avatarVersion: Int

        init(_ membership: PersistentPairMembership) {
            id = membership.id
            pairSpaceID = membership.pairSpaceID
            userID = membership.userID
            nickname = membership.nickname
            joinedAt = membership.joinedAt
            avatarSystemName = membership.avatarSystemName
            avatarPhotoFileName = membership.avatarPhotoFileName
            avatarAssetID = membership.avatarAssetID
            avatarVersion = membership.avatarVersion
        }

        func makePersistent() -> PersistentPairMembership {
            PersistentPairMembership(
                id: id,
                pairSpaceID: pairSpaceID,
                userID: userID,
                nickname: nickname,
                joinedAt: joinedAt,
                avatarSystemName: avatarSystemName,
                avatarPhotoFileName: avatarPhotoFileName,
                avatarAssetID: avatarAssetID,
                avatarVersion: avatarVersion
            )
        }
    }

    private struct InviteSnapshot {
        let id: UUID
        let pairSpaceID: UUID
        let inviterID: UUID
        let recipientUserID: UUID?
        let inviteCode: String
        let statusRawValue: String
        let sentAt: Date
        let respondedAt: Date?
        let expiresAt: Date

        init(_ invite: PersistentInvite) {
            id = invite.id
            pairSpaceID = invite.pairSpaceID
            inviterID = invite.inviterID
            recipientUserID = invite.recipientUserID
            inviteCode = invite.inviteCode
            statusRawValue = invite.statusRawValue
            sentAt = invite.sentAt
            respondedAt = invite.respondedAt
            expiresAt = invite.expiresAt
        }

        func makePersistent() -> PersistentInvite {
            PersistentInvite(
                id: id,
                pairSpaceID: pairSpaceID,
                inviterID: inviterID,
                recipientUserID: recipientUserID,
                inviteCode: inviteCode,
                statusRawValue: statusRawValue,
                sentAt: sentAt,
                respondedAt: respondedAt,
                expiresAt: expiresAt
            )
        }
    }

    private struct PairingHistorySnapshot {
        let id: UUID
        let pairSpaceID: UUID
        let memberARecordID: String
        let memberBRecordID: String
        let zoneName: String
        let pairedAt: Date
        let endedAt: Date?
        let isDeleted: Bool

        init(_ history: PersistentPairingHistory) {
            id = history.id
            pairSpaceID = history.pairSpaceID
            memberARecordID = history.memberARecordID
            memberBRecordID = history.memberBRecordID
            zoneName = history.zoneName
            pairedAt = history.pairedAt
            endedAt = history.endedAt
            isDeleted = history.isDeleted
        }

        func makePersistent() -> PersistentPairingHistory {
            PersistentPairingHistory(
                id: id,
                pairSpaceID: pairSpaceID,
                memberARecordID: memberARecordID,
                memberBRecordID: memberBRecordID,
                zoneName: zoneName,
                pairedAt: pairedAt,
                endedAt: endedAt,
                isDeleted: isDeleted
            )
        }
    }

    private struct OccurrenceCompletionSnapshot {
        let itemID: UUID
        let occurrenceDate: Date
        let completedAt: Date
        let createdAt: Date
        let updatedAt: Date

        init(_ completion: PersistentItemOccurrenceCompletion) {
            itemID = completion.itemID
            occurrenceDate = completion.occurrenceDate
            completedAt = completion.completedAt
            createdAt = completion.createdAt
            updatedAt = completion.updatedAt
        }

        var domainModel: ItemOccurrenceCompletion {
            ItemOccurrenceCompletion(
                occurrenceDate: occurrenceDate,
                completedAt: completedAt
            )
        }

        func makePersistent() -> PersistentItemOccurrenceCompletion {
            PersistentItemOccurrenceCompletion(
                itemID: itemID,
                occurrenceDate: occurrenceDate,
                completedAt: completedAt,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private struct StoreSnapshot {
        let userProfiles: [UserProfileSnapshot]
        let spaces: [Space]
        let pairSpaces: [PairSpaceSnapshot]
        let memberships: [PairMembershipSnapshot]
        let invites: [InviteSnapshot]
        let taskLists: [TaskList]
        let projects: [Project]
        let projectSubtasks: [ProjectSubtask]
        let items: [Item]
        let occurrenceCompletions: [OccurrenceCompletionSnapshot]
        let taskTemplates: [TaskTemplate]
        let syncChanges: [SyncChange]
        let syncStates: [SyncState]
        let periodicTasks: [PeriodicTask]
        let pairingHistories: [PairingHistorySnapshot]
    }

    private static func captureSnapshot(from container: ModelContainer) throws -> StoreSnapshot {
        let context = ModelContext(container)

        let userProfiles = try context.fetch(FetchDescriptor<PersistentUserProfile>()).map(UserProfileSnapshot.init)
        let spaces = try context.fetch(FetchDescriptor<PersistentSpace>()).map(\.domainModel)
        let pairSpaces = try context.fetch(FetchDescriptor<PersistentPairSpace>()).map(PairSpaceSnapshot.init)
        let memberships = try context.fetch(FetchDescriptor<PersistentPairMembership>()).map(PairMembershipSnapshot.init)
        let invites = try context.fetch(FetchDescriptor<PersistentInvite>()).map(InviteSnapshot.init)
        let taskLists = try context.fetch(FetchDescriptor<PersistentTaskList>()).map {
            TaskList(
                id: $0.id,
                spaceID: $0.spaceID,
                name: $0.name,
                kind: TaskListKind(rawValue: $0.kindRawValue) ?? .custom,
                colorToken: $0.colorToken,
                sortOrder: $0.sortOrder,
                isArchived: $0.isArchived,
                taskCount: 0,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let projects = try context.fetch(FetchDescriptor<PersistentProject>()).map {
            Project(
                id: $0.id,
                spaceID: $0.spaceID,
                name: $0.name,
                notes: $0.notes,
                colorToken: $0.colorToken,
                status: ProjectStatus(rawValue: $0.statusRawValue) ?? .active,
                targetDate: $0.targetDate,
                remindAt: $0.remindAt,
                taskCount: 0,
                subtasks: [],
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                completedAt: $0.completedAt
            )
        }
        let projectSubtasks = try context.fetch(FetchDescriptor<PersistentProjectSubtask>()).map { $0.domainModel() }
        let occurrenceCompletions = try context.fetch(FetchDescriptor<PersistentItemOccurrenceCompletion>())
            .map(OccurrenceCompletionSnapshot.init)
        let completionsByItemID = Dictionary(grouping: occurrenceCompletions, by: \.itemID)
        let items = try context.fetch(FetchDescriptor<PersistentItem>()).map {
            $0.domainModel(occurrenceCompletions: completionsByItemID[$0.id]?.map(\.domainModel) ?? [])
        }
        let taskTemplates = try context.fetch(FetchDescriptor<PersistentTaskTemplate>()).map(\.domainModel)
        let syncChanges = try context.fetch(FetchDescriptor<PersistentSyncChange>()).map(\.domainModel)
        let syncStates = try context.fetch(FetchDescriptor<PersistentSyncState>()).map(\.domainModel)
        let periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>()).map { $0.domainModel() }
        let pairingHistories = try context.fetch(FetchDescriptor<PersistentPairingHistory>()).map(PairingHistorySnapshot.init)

        return StoreSnapshot(
            userProfiles: userProfiles,
            spaces: spaces,
            pairSpaces: pairSpaces,
            memberships: memberships,
            invites: invites,
            taskLists: taskLists,
            projects: projects,
            projectSubtasks: projectSubtasks,
            items: items,
            occurrenceCompletions: occurrenceCompletions,
            taskTemplates: taskTemplates,
            syncChanges: syncChanges,
            syncStates: syncStates,
            periodicTasks: periodicTasks,
            pairingHistories: pairingHistories
        )
    }

    private static func restoreSnapshot(_ snapshot: StoreSnapshot, into container: ModelContainer) throws {
        let context = ModelContext(container)

        for profile in snapshot.userProfiles {
            context.insert(profile.makePersistent())
        }
        for space in snapshot.spaces {
            context.insert(PersistentSpace(space: space))
        }
        for pairSpace in snapshot.pairSpaces {
            context.insert(pairSpace.makePersistent())
        }
        for membership in snapshot.memberships {
            context.insert(membership.makePersistent())
        }
        for invite in snapshot.invites {
            context.insert(invite.makePersistent())
        }
        for list in snapshot.taskLists {
            context.insert(PersistentTaskList(list: list))
        }
        for project in snapshot.projects {
            context.insert(PersistentProject(project: project))
        }
        for subtask in snapshot.projectSubtasks {
            context.insert(PersistentProjectSubtask(subtask: subtask))
        }
        for item in snapshot.items {
            context.insert(PersistentItem(item: item))
        }
        for completion in snapshot.occurrenceCompletions {
            context.insert(completion.makePersistent())
        }
        for template in snapshot.taskTemplates {
            context.insert(PersistentTaskTemplate(template: template))
        }
        for syncChange in snapshot.syncChanges {
            context.insert(PersistentSyncChange(change: syncChange))
        }
        for syncState in snapshot.syncStates {
            context.insert(PersistentSyncState(state: syncState))
        }
        for periodicTask in snapshot.periodicTasks {
            context.insert(PersistentPeriodicTask(task: periodicTask))
        }
        for history in snapshot.pairingHistories {
            context.insert(history.makePersistent())
        }

        try context.save()
    }
    private static func seedIfNeeded(container: ModelContainer) throws {
        let context = ModelContext(container)
        let spaceCount = try context.fetchCount(FetchDescriptor<PersistentSpace>())

        guard spaceCount == 0 else { return }

        context.insert(PersistentSpace(space: MockDataFactory.makeSingleSpace()))
        context.insert(PersistentSpace(space: MockDataFactory.makePairSharedSpace()))
        context.insert(PersistentPairSpace(pairSpace: MockDataFactory.makePairSpace()))
        context.insert(
            PersistentPairMembership(
                pairSpaceID: MockDataFactory.makePairSpace().id,
                userID: MockDataFactory.currentUserID,
                nickname: MockDataFactory.makeCurrentUser().displayName,
                joinedAt: MockDataFactory.now.addingTimeInterval(-86_400 * 120)
            )
        )
        context.insert(
            PersistentPairMembership(
                pairSpaceID: MockDataFactory.makePairSpace().id,
                userID: MockDataFactory.partnerUserID,
                nickname: MockDataFactory.makePartnerUser().displayName,
                joinedAt: MockDataFactory.now.addingTimeInterval(-86_400 * 115)
            )
        )

        for list in MockDataFactory.makeTaskLists() {
            context.insert(PersistentTaskList(list: list))
        }

        for project in MockDataFactory.makeProjects() {
            context.insert(PersistentProject(project: project))
        }

        for subtask in MockDataFactory.makeProjectSubtasks() {
            context.insert(PersistentProjectSubtask(subtask: subtask))
        }

        for item in MockDataFactory.makeItems() {
            context.insert(PersistentItem(item: item))
        }

        try context.save()
    }

    private static func injectDebugPairReviewFixtureIfNeeded(container: ModelContainer) throws {
        let context = ModelContext(container)
        let dayStart = Calendar.current.startOfDay(for: .now)
        let fixtures: [Item] = [
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777774")!,
                spaceID: MockDataFactory.pairSharedSpaceID,
                listID: MockDataFactory.todayListID,
                projectID: nil,
                creatorID: MockDataFactory.partnerUserID,
                title: "对方发来的待确认任务",
                notes: "这张卡用于测试第 3 类：对方发给我，等待我处理。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 15),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 14 + 1_800),
                status: .pendingConfirmation,
                assignmentState: .pendingResponse,
                latestResponse: nil,
                responseHistory: [],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.partnerUserID,
                        body: "你先看看，合适的话就直接接受。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 9 + 1_200)
                    )
                ],
                lastActionByUserID: MockDataFactory.partnerUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 9 + 1_200),
                createdAt: dayStart.addingTimeInterval(-9_600),
                updatedAt: dayStart.addingTimeInterval(3_600 * 9 + 1_200),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777775")!,
                spaceID: MockDataFactory.pairSharedSpaceID,
                listID: MockDataFactory.todayListID,
                projectID: nil,
                creatorID: MockDataFactory.currentUserID,
                title: "我发出后被退回的任务",
                notes: "这张卡用于测试第 2 类：我发出去后被对方退回，等我二次处理。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 18 + 900),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 18),
                status: .declinedOrBlocked,
                assignmentState: .declined,
                latestResponse: ItemResponse(
                    responderID: MockDataFactory.partnerUserID,
                    kind: .notSuitable,
                    message: "没时间",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 12 + 600)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: MockDataFactory.partnerUserID,
                        kind: .notSuitable,
                        message: "没时间",
                        respondedAt: dayStart.addingTimeInterval(3_600 * 12 + 600)
                    )
                ],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.currentUserID,
                        body: "你方便的话帮我处理一下。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 10 + 1_800)
                    ),
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.partnerUserID,
                        body: "没时间",
                        createdAt: dayStart.addingTimeInterval(3_600 * 12 + 600)
                    )
                ],
                lastActionByUserID: MockDataFactory.partnerUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 12 + 600),
                createdAt: dayStart.addingTimeInterval(-7_200),
                updatedAt: dayStart.addingTimeInterval(3_600 * 12 + 600),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777776")!,
                spaceID: MockDataFactory.pairSharedSpaceID,
                listID: MockDataFactory.todayListID,
                projectID: nil,
                creatorID: MockDataFactory.partnerUserID,
                title: "我已确认进入待办的任务",
                notes: "这张卡用于测试第 1 类：我已经确认过，现已变成我的待办任务。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 20),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 19 + 1_800),
                status: .inProgress,
                assignmentState: .accepted,
                latestResponse: ItemResponse(
                    responderID: MockDataFactory.currentUserID,
                    kind: .willing,
                    message: nil,
                    respondedAt: dayStart.addingTimeInterval(3_600 * 11 + 300)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: MockDataFactory.currentUserID,
                        kind: .willing,
                        message: nil,
                        respondedAt: dayStart.addingTimeInterval(3_600 * 11 + 300)
                    )
                ],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: MockDataFactory.partnerUserID,
                        body: "你已经接受了，现在它应该像正常待办一样显示。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 11)
                    )
                ],
                lastActionByUserID: MockDataFactory.currentUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 11 + 300),
                createdAt: dayStart.addingTimeInterval(-5_400),
                updatedAt: dayStart.addingTimeInterval(3_600 * 11 + 300),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            )
        ]

        for fixture in fixtures {
            let existing = try context.fetch(
                FetchDescriptor<PersistentItem>(
                    predicate: #Predicate<PersistentItem> { $0.id == fixture.id }
                )
            )
            for item in existing {
                context.delete(item)
            }
            context.insert(PersistentItem(item: fixture))
        }

        if context.hasChanges {
            try context.save()
        }
    }
}
