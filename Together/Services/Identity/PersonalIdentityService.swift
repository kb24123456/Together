import Foundation
import SwiftData
import TogetherCore

enum PersonalIdentityResolution: Equatable {
    case ready(user: User, space: Space)
    case waitingForCloudRestore
    case requiresLocalStart
}

@MainActor
final class PersonalIdentityService {
    private let container: ModelContainer
    private let defaults: UserDefaults

    static let provisionalSpaceIDKey = "together.identity.provisionalSpaceID"

    init(container: ModelContainer, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
    }

    func resolve(afterInitialCloudImport: Bool) -> PersonalIdentityResolution {
        let context = ModelContext(container)
        let profiles = ((try? context.fetch(
            FetchDescriptor<PersistentUserProfile>(
                sortBy: [SortDescriptor(\PersistentUserProfile.updatedAt, order: .reverse)]
            )
        )) ?? [])
        let spaces = ((try? context.fetch(
            FetchDescriptor<PersistentSpace>(
                sortBy: [SortDescriptor(\PersistentSpace.updatedAt, order: .reverse)]
            )
        )) ?? []).filter {
            $0.typeRawValue == SpaceType.single.rawValue
                && $0.statusRawValue != SpaceStatus.archived.rawValue
        }

        let dataBearingSpaceIDs = Self.dataBearingSpaceIDs(in: context)
        if afterInitialCloudImport,
           mergeProvisionalSpaceIfNeeded(
               spaces: spaces,
               profiles: profiles,
               dataBearingSpaceIDs: dataBearingSpaceIDs,
               context: context
           ) {
            return resolve(afterInitialCloudImport: false)
        }
        let selectedSpace = spaces.first { dataBearingSpaceIDs.contains($0.id) }
            ?? spaces.first { space in profiles.contains { $0.userID == space.ownerUserID } }
            ?? spaces.first

        if let selectedSpace {
            let creatorIDs = Self.creatorIDs(in: selectedSpace.id, context: context)
            let selectedProfile = profiles.first { $0.userID == selectedSpace.ownerUserID }
                ?? profiles.first { creatorIDs.contains($0.userID) }
                ?? (dataBearingSpaceIDs.contains(selectedSpace.id) ? nil : profiles.first)

            guard let selectedProfile else {
                return .waitingForCloudRestore
            }
            return .ready(
                user: Self.makeUser(from: selectedProfile),
                space: selectedSpace.domainModel
            )
        }

        if profiles.isEmpty == false {
            return .waitingForCloudRestore
        }
        return afterInitialCloudImport ? .requiresLocalStart : .waitingForCloudRestore
    }

    func startLocally() throws -> PersonalIdentityResolution {
        let existing = resolve(afterInitialCloudImport: true)
        if case .ready = existing {
            return existing
        }

        let context = ModelContext(container)
        let profile = try context.fetch(
            FetchDescriptor<PersistentUserProfile>(
                sortBy: [SortDescriptor(\PersistentUserProfile.updatedAt, order: .reverse)]
            )
        ).first
        let spaceRecord = try context.fetch(
            FetchDescriptor<PersistentSpace>(
                sortBy: [SortDescriptor(\PersistentSpace.updatedAt, order: .reverse)]
            )
        ).first { $0.typeRawValue == SpaceType.single.rawValue && $0.statusRawValue != SpaceStatus.archived.rawValue }

        let user: User
        if let profile {
            user = Self.makeUser(from: profile)
        } else {
            user = Self.makeDefaultUser(id: spaceRecord?.ownerUserID ?? UUID())
            context.insert(PersistentUserProfile(user: user))
        }

        let space: Space
        if let spaceRecord {
            space = spaceRecord.domainModel
        } else {
            let now = Date.now
            space = Space(
                id: UUID(),
                type: .single,
                displayName: "我的空间",
                ownerUserID: user.id,
                status: .active,
                createdAt: now,
                updatedAt: now
            )
            context.insert(PersistentSpace(space: space))
        }

        try context.save()
        defaults.set(space.id.uuidString.lowercased(), forKey: Self.provisionalSpaceIDKey)
        return .ready(user: user, space: space)
    }

    private static func makeUser(from profile: PersistentUserProfile) -> User {
        profile.apply(to: User(
            id: profile.userID,
            displayName: profile.displayName,
            avatarSystemName: profile.avatarSystemName,
            avatarPhotoFileName: profile.avatarPhotoFileName,
            avatarAssetID: profile.avatarAssetID,
            avatarVersion: profile.avatarVersion,
            createdAt: profile.updatedAt,
            updatedAt: profile.updatedAt,
            preferences: NotificationSettings(
                taskReminderEnabled: profile.taskReminderEnabled,
                dailySummaryEnabled: profile.dailySummaryEnabled,
                calendarReminderEnabled: profile.calendarReminderEnabled
            )
        ))
    }

    private static func makeDefaultUser(id: UUID) -> User {
        let now = Date.now
        return User(
            id: id,
            displayName: "我",
            avatarSystemName: "person.crop.circle.fill",
            createdAt: now,
            updatedAt: now,
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: false,
                calendarReminderEnabled: true
            )
        )
    }

    private func mergeProvisionalSpaceIfNeeded(
        spaces: [PersistentSpace],
        profiles: [PersistentUserProfile],
        dataBearingSpaceIDs: Set<UUID>,
        context: ModelContext
    ) -> Bool {
        guard let provisionalIDString = defaults.string(forKey: Self.provisionalSpaceIDKey),
              let provisionalID = UUID(uuidString: provisionalIDString),
              let provisionalSpace = spaces.first(where: { $0.id == provisionalID }),
              let remoteSpace = spaces.first(where: { space in
                  space.id != provisionalID && profiles.contains { $0.userID == space.ownerUserID }
              })
        else { return false }

        // Do not treat a second empty local record as cloud authority. The restored
        // space must either carry data or have a matching restored profile.
        guard dataBearingSpaceIDs.contains(remoteSpace.id)
                || profiles.contains(where: { $0.userID == remoteSpace.ownerUserID })
        else { return false }

        let localUserID = provisionalSpace.ownerUserID
        let remoteUserID = remoteSpace.ownerUserID

        let items = (try? context.fetch(FetchDescriptor<PersistentItem>())) ?? []
        let remoteItemIDs = Set(items.filter { $0.spaceID == remoteSpace.id }.map(\.id))
        let localItemIDs = Set(items.filter { $0.spaceID == provisionalID }.map(\.id))
        for item in items where item.spaceID == provisionalID {
            if remoteItemIDs.contains(item.id) {
                context.delete(item)
            } else {
                item.spaceID = remoteSpace.id
                if item.creatorID == localUserID { item.creatorID = remoteUserID }
                if item.lastActionByUserID == localUserID { item.lastActionByUserID = remoteUserID }
                if item.completedByUserID == localUserID { item.completedByUserID = remoteUserID }
            }
        }

        let lists = (try? context.fetch(FetchDescriptor<PersistentTaskList>())) ?? []
        let remoteListIDs = Set(lists.filter { $0.spaceID == remoteSpace.id }.map(\.id))
        for list in lists where list.spaceID == provisionalID {
            if remoteListIDs.contains(list.id) {
                context.delete(list)
            } else {
                list.spaceID = remoteSpace.id
                if list.creatorID == localUserID { list.creatorID = remoteUserID }
            }
        }

        let projects = (try? context.fetch(FetchDescriptor<PersistentProject>())) ?? []
        let remoteProjectIDs = Set(projects.filter { $0.spaceID == remoteSpace.id }.map(\.id))
        let localProjectIDs = Set(projects.filter { $0.spaceID == provisionalID }.map(\.id))
        for project in projects where project.spaceID == provisionalID {
            if remoteProjectIDs.contains(project.id) {
                context.delete(project)
            } else {
                project.spaceID = remoteSpace.id
                if project.creatorID == localUserID { project.creatorID = remoteUserID }
            }
        }

        let periodicTasks = (try? context.fetch(FetchDescriptor<PersistentPeriodicTask>())) ?? []
        let remotePeriodicIDs = Set(periodicTasks.filter { $0.spaceID == remoteSpace.id }.map(\.id))
        for task in periodicTasks where task.spaceID == provisionalID {
            if remotePeriodicIDs.contains(task.id) {
                context.delete(task)
            } else {
                task.spaceID = remoteSpace.id
                if task.creatorID == localUserID { task.creatorID = remoteUserID }
            }
        }

        let templates = (try? context.fetch(FetchDescriptor<PersistentTaskTemplate>())) ?? []
        let remoteTemplateIDs = Set(templates.filter { $0.spaceID == remoteSpace.id }.map(\.id))
        for template in templates where template.spaceID == provisionalID {
            if remoteTemplateIDs.contains(template.id) {
                context.delete(template)
            } else {
                template.spaceID = remoteSpace.id
            }
        }

        let taskSubtasks = (try? context.fetch(FetchDescriptor<PersistentTaskSubtask>())) ?? []
        for subtask in taskSubtasks where localItemIDs.contains(subtask.itemID) && subtask.creatorID == localUserID {
            subtask.creatorID = remoteUserID
        }
        let projectSubtasks = (try? context.fetch(FetchDescriptor<PersistentProjectSubtask>())) ?? []
        for subtask in projectSubtasks where localProjectIDs.contains(subtask.projectID) && subtask.creatorID == localUserID {
            subtask.creatorID = remoteUserID
        }

        context.delete(provisionalSpace)
        for profile in profiles where profile.userID == localUserID && localUserID != remoteUserID {
            context.delete(profile)
        }

        do {
            try context.save()
            defaults.removeObject(forKey: Self.provisionalSpaceIDKey)
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    private static func dataBearingSpaceIDs(in context: ModelContext) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in (try? context.fetch(FetchDescriptor<PersistentItem>())) ?? []
            where item.isLocallyDeleted == false && item.isArchived == false {
            if let spaceID = item.spaceID { ids.insert(spaceID) }
        }
        for list in (try? context.fetch(FetchDescriptor<PersistentTaskList>())) ?? []
            where list.isLocallyDeleted == false && list.isArchived == false {
            ids.insert(list.spaceID)
        }
        for project in (try? context.fetch(FetchDescriptor<PersistentProject>())) ?? []
            where project.isLocallyDeleted == false {
            ids.insert(project.spaceID)
        }
        for task in (try? context.fetch(FetchDescriptor<PersistentPeriodicTask>())) ?? []
            where task.isLocallyDeleted == false && task.isActive {
            if let spaceID = task.spaceID { ids.insert(spaceID) }
        }
        return ids
    }

    private static func creatorIDs(in spaceID: UUID, context: ModelContext) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in (try? context.fetch(FetchDescriptor<PersistentItem>())) ?? [] where item.spaceID == spaceID {
            ids.insert(item.creatorID)
        }
        for list in (try? context.fetch(FetchDescriptor<PersistentTaskList>())) ?? [] where list.spaceID == spaceID {
            ids.insert(list.creatorID)
        }
        for project in (try? context.fetch(FetchDescriptor<PersistentProject>())) ?? [] where project.spaceID == spaceID {
            ids.insert(project.creatorID)
        }
        for task in (try? context.fetch(FetchDescriptor<PersistentPeriodicTask>())) ?? [] where task.spaceID == spaceID {
            ids.insert(task.creatorID)
        }
        return ids
    }
}
