import Foundation

/// Centralized permission checks for pair sync zero-conflict design.
///
/// Rules:
/// - Only the creator can edit/delete their tasks, lists, projects, periodic tasks
/// - Only the space owner (inviter) can rename the pair space
/// - Only the assignee can respond to / complete a task
/// - Both users can create new entities and unbind
///
/// All methods are pure, stateless, and usable from any layer (UI, Service, Sync).
/// In solo mode, creatorID == currentUserID naturally passes all checks.
enum PairPermissionService {

    // MARK: - Task

    static func canEditTask(_ task: Item, actorID: UUID) -> Bool {
        task.creatorID == actorID
    }

    static func canDeleteTask(_ task: Item, actorID: UUID) -> Bool {
        task.creatorID == actorID
    }

    // MARK: - TaskList

    static func canEditTaskList(_ list: TaskList, actorID: UUID) -> Bool {
        list.creatorID == actorID
    }

    static func canDeleteTaskList(_ list: TaskList, actorID: UUID) -> Bool {
        list.creatorID == actorID
    }

    // MARK: - Project

    static func canEditProject(_ project: Project, actorID: UUID) -> Bool {
        project.creatorID == actorID
    }

    static func canDeleteProject(_ project: Project, actorID: UUID) -> Bool {
        project.creatorID == actorID
    }

    // MARK: - PeriodicTask

    static func canEditPeriodicTask(_ task: PeriodicTask, actorID: UUID) -> Bool {
        task.creatorID == actorID
    }

    static func canDeletePeriodicTask(_ task: PeriodicTask, actorID: UUID) -> Bool {
        task.creatorID == actorID
    }

    // MARK: - Space

    static func canRenameSpace(_ space: Space, actorID: UUID) -> Bool {
        space.ownerUserID == actorID
    }

    // MARK: - Profile

    static func canEditProfile(profileUserID: UUID, actorID: UUID) -> Bool {
        profileUserID == actorID
    }
}
