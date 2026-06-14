import Foundation

/// Centralized permission checks for single-user data mutations.
///
/// Rules:
/// - The current user can edit/delete their own tasks, lists, projects, periodic tasks
/// - The space owner can rename the space
/// - Completion and restore actions stay local to the active user
///
/// All methods are pure, stateless, and usable from any layer.
enum SoloPermissionService {

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

    static func canToggleProjectCompletion(_ project: Project, actorID: UUID) -> Bool {
        project.creatorID == actorID
    }

    // MARK: - ProjectSubtask (inherits from parent Project)

    static func canEditProjectSubtask(projectCreatorID: UUID, actorID: UUID) -> Bool {
        projectCreatorID == actorID
    }

    static func canDeleteProjectSubtask(projectCreatorID: UUID, actorID: UUID) -> Bool {
        projectCreatorID == actorID
    }

    static func canToggleSubtaskCompletion(projectCreatorID: UUID, actorID: UUID) -> Bool {
        projectCreatorID == actorID
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
