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

    /// Rename / metadata edits (name, notes, target date) — creator only.
    static func canEditProject(_ project: Project, actorID: UUID) -> Bool {
        project.creatorID == actorID
    }

    static func canDeleteProject(_ project: Project, actorID: UUID) -> Bool {
        project.creatorID == actorID
    }

    /// Toggle project completion — **both partners** may mark a shared project
    /// as completed or reopen it. Space membership is already enforced by
    /// Supabase RLS at the Repository boundary.
    static func canToggleProjectCompletion(_ project: Project, actorID: UUID) -> Bool {
        true
    }

    // MARK: - ProjectSubtask (inherits from parent Project)

    /// Rename subtask title, add subtask, delete subtask — creator-of-the-project only.
    static func canEditProjectSubtask(projectCreatorID: UUID, actorID: UUID) -> Bool {
        projectCreatorID == actorID
    }

    static func canDeleteProjectSubtask(projectCreatorID: UUID, actorID: UUID) -> Bool {
        projectCreatorID == actorID
    }

    /// Toggle a subtask's completion — **both partners** may check / uncheck a
    /// shared subtask. Space membership already enforced upstream.
    static func canToggleSubtaskCompletion(projectCreatorID: UUID, actorID: UUID) -> Bool {
        true
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
