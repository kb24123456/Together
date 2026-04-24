import Foundation
import Observation

@MainActor
@Observable
final class ProjectsViewModel {
    /// 免费用户自己创建的项目上限（spec § 产品切分）。
    static let freeProjectQuota = 3

    private let sessionStore: SessionStore
    private let projectRepository: ProjectRepositoryProtocol
    private let premiumGate: PremiumGate

    var loadState: LoadableState = .idle
    var projects: [Project] = []

    /// Upsell 信号。超配额时置 `.projectQuota`，View 观察后提示升级并调 `dismissUpsell()`。
    private(set) var pendingUpsellTrigger: UpsellTrigger?

    /// Fired after Repository recordLocalChange. AppContext wires this to
    /// flushRecordedSharedMutation to trigger the Supabase push.
    var onSharedMutationRecorded: ((SyncChange) -> Void)?

    init(
        sessionStore: SessionStore,
        projectRepository: ProjectRepositoryProtocol,
        premiumGate: PremiumGate
    ) {
        self.sessionStore = sessionStore
        self.projectRepository = projectRepository
        self.premiumGate = premiumGate
    }

    func dismissUpsell() {
        pendingUpsellTrigger = nil
    }

    /// View 层在弹 ProjectComposer 之前调用做预检。
    /// 返回 false 表示当前用户已超额，应直接 `requestQuotaUpsell()`，**不要**弹 Composer——
    /// 否则用户填了一堆 draft 才被告知付费，体验差。
    func canCreateAnotherForCurrentUser() -> Bool {
        guard let currentUserID = sessionStore.currentUser?.id, !premiumGate.isPremium else {
            return true
        }
        let ownCount = projects.filter { $0.creatorID == currentUserID }.count
        return ownCount < Self.freeProjectQuota
    }

    /// 配额预检失败后调用：触发 paywall，但不写 repo。
    func requestQuotaUpsell() {
        pendingUpsellTrigger = .projectQuota
    }

    private func emitMutationRecorded(projectID: UUID, operation: SyncOperationKind) {
        guard let spaceID = sessionStore.currentSpace?.id else { return }
        onSharedMutationRecorded?(
            SyncChange(entityKind: .project, operation: operation, recordID: projectID, spaceID: spaceID)
        )
    }

    var activeProjects: [Project] {
        projects.filter { $0.status == .active || $0.status == .onHold }
    }

    var archivedProjects: [Project] {
        projects.filter { $0.status == .completed || $0.status == .archived }
    }

    func toggleProjectCompletion(projectID: UUID) async {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        let actorID = sessionStore.currentUser?.id ?? UUID()

        do {
            let updated = try await projectRepository.setProjectCompleted(
                projectID: projectID,
                isCompleted: project.status != .completed,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: updated.status == .completed ? .complete : .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func addSubtask(projectID: UUID, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let creatorID = sessionStore.currentUser?.id ?? UUID()

        do {
            let updated = try await projectRepository.addSubtask(
                projectID: projectID,
                title: trimmed,
                isCompleted: false,
                creatorID: creatorID,
                actorID: creatorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleSubtask(projectID: UUID, subtaskID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.toggleSubtask(
                projectID: projectID,
                subtaskID: subtaskID,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.updateSubtask(
                projectID: projectID,
                subtaskID: subtaskID,
                title: title,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func deleteSubtask(projectID: UUID, subtaskID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.deleteSubtask(
                projectID: projectID,
                subtaskID: subtaskID,
                actorID: actorID
            )
            replaceProject(updated)
            emitMutationRecorded(projectID: projectID, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func archiveProject(projectID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let archived = try await projectRepository.archiveProject(projectID: projectID, actorID: actorID)
            replaceProject(archived)
            emitMutationRecorded(projectID: projectID, operation: .archive)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func canDeleteProject(_ project: Project) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return PairPermissionService.canDeleteProject(project, actorID: userID)
    }

    func canEditProject(_ project: Project) -> Bool {
        guard let userID = sessionStore.currentUser?.id else { return true }
        return PairPermissionService.canEditProject(project, actorID: userID)
    }

    func deleteProject(projectID: UUID) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            try await projectRepository.deleteProject(projectID: projectID, actorID: actorID)
            projects.removeAll { $0.id == projectID }
            emitMutationRecorded(projectID: projectID, operation: .delete)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateProject(_ project: Project) async {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        do {
            let updated = try await projectRepository.saveProject(project, actorID: actorID)
            replaceProject(updated)
            emitMutationRecorded(projectID: updated.id, operation: .upsert)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 新建项目。自带配额门禁：非 Pro 且 own count >= 3 时阻断并置 upsell trigger。
    /// 返回创建好的 `Project`；配额拦截时返回 nil，主叫方据此决定是否进一步交互。
    /// 子任务由主叫方传入，成功创建后按顺序写入仓库。
    @discardableResult
    func createNew(
        _ project: Project,
        subtasks: [(title: String, isCompleted: Bool)] = []
    ) async -> Project? {
        let actorID = sessionStore.currentUser?.id ?? UUID()
        if !premiumGate.isPremium {
            let ownCount = projects.filter { $0.creatorID == actorID }.count
            if ownCount >= Self.freeProjectQuota {
                pendingUpsellTrigger = .projectQuota
                return nil
            }
        }

        do {
            let created = try await projectRepository.saveProject(project, actorID: actorID)
            for subtask in subtasks {
                _ = try await projectRepository.addSubtask(
                    projectID: created.id,
                    title: subtask.title,
                    isCompleted: subtask.isCompleted,
                    creatorID: actorID,
                    actorID: actorID
                )
            }
            await load()
            emitMutationRecorded(projectID: created.id, operation: .upsert)
            return created
        } catch {
            loadState = .failed(error.localizedDescription)
            return nil
        }
    }

    func load() async {
        loadState = .loading

        do {
            projects = try await projectRepository.fetchProjects(spaceID: sessionStore.currentSpace?.id)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func replaceProject(_ updated: Project) {
        guard let index = projects.firstIndex(where: { $0.id == updated.id }) else {
            projects.append(updated)
            return
        }

        projects[index] = updated
    }
}
