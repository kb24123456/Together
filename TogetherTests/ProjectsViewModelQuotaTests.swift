import Foundation
import Testing
@testable import Together

/// 空 seed 的 ProjectRepository stub，用来让 quota 测试从零开始计数
/// （`MockProjectRepository` 初始就带 MockDataFactory.makeProjects()，
/// 会把 `me` 的项目数抬高 3 个污染配额断言）。
actor StubProjectRepository: ProjectRepositoryProtocol {
    private var projects: [Project] = []

    func fetchProjects(spaceID: UUID?) async throws -> [Project] {
        projects.filter { $0.spaceID == spaceID }
    }

    func saveProject(_ project: Project, actorID: UUID) async throws -> Project {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        return project
    }

    func addSubtask(projectID: UUID, title: String, isCompleted: Bool, creatorID: UUID, actorID: UUID) async throws -> Project {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else {
            throw RepositoryError.notFound
        }
        // 测试不断言 subtasks，只需 not-throw
        return projects[i]
    }

    func archiveProject(projectID: UUID, actorID: UUID) async throws -> Project { fatalError("unused") }
    func deleteProject(projectID: UUID, actorID: UUID) async throws { fatalError("unused") }
    func setProjectCompleted(projectID: UUID, isCompleted: Bool, actorID: UUID) async throws -> Project { fatalError("unused") }
    func toggleSubtask(projectID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Project { fatalError("unused") }
    func updateSubtask(projectID: UUID, subtaskID: UUID, title: String, actorID: UUID) async throws -> Project { fatalError("unused") }
    func deleteSubtask(projectID: UUID, subtaskID: UUID, actorID: UUID) async throws -> Project { fatalError("unused") }
}

@MainActor
@Suite
struct ProjectsViewModelQuotaTests {

    @Test func freeUnderQuotaAllowsCreate() async {
        let (vm, _, me, _) = await makeViewModel(meCount: 2)
        let result = await vm.createNew(makeDraft(creatorID: me))

        #expect(result != nil)
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.projects.filter { $0.creatorID == me }.count == 3)
    }

    @Test func freeAtQuotaBlocksCreate() async {
        let (vm, _, me, _) = await makeViewModel(meCount: 3)
        let result = await vm.createNew(makeDraft(creatorID: me))

        #expect(result == nil)
        #expect(vm.pendingUpsellTrigger == .projectQuota)
        #expect(vm.projects.filter { $0.creatorID == me }.count == 3)  // 未新增
    }

    @Test func proBypassesQuota() async {
        let (vm, gate, me, _) = await makeViewModel(meCount: 5)
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)

        let result = await vm.createNew(makeDraft(creatorID: me))

        #expect(result != nil)
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.projects.filter { $0.creatorID == me }.count == 6)
    }

    @Test func partnerProjectsDoNotCountAgainstMyQuota() async {
        let (vm, _, me, _) = await makeViewModel(meCount: 2, partnerCount: 50)
        let result = await vm.createNew(makeDraft(creatorID: me))

        #expect(result != nil)
        #expect(vm.pendingUpsellTrigger == nil)
    }

    @Test func dismissUpsellClearsTrigger() async {
        let (vm, _, me, _) = await makeViewModel(meCount: 3)
        _ = await vm.createNew(makeDraft(creatorID: me))
        #expect(vm.pendingUpsellTrigger == .projectQuota)

        vm.dismissUpsell()
        #expect(vm.pendingUpsellTrigger == nil)
    }

    // MARK: - Helpers

    private func makeViewModel(
        meCount: Int,
        partnerCount: Int = 0
    ) async -> (ProjectsViewModel, PremiumGate, UUID, UUID) {
        let currentUser = MockDataFactory.makeCurrentUser()
        let me = currentUser.id
        let partner = MockDataFactory.partnerUserID
        let spaceID = MockDataFactory.singleSpaceID

        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: currentUser,
            singleSpace: MockDataFactory.makeSingleSpace(),
            pairSummary: nil
        )

        let date = SystemDateProvider()
        let gate = PremiumGate(
            rcClient: StubRCClient(),
            grantsLoader: StubGrantsLoader(),
            cache: PremiumStatusCache(
                defaults: UserDefaults(suiteName: UUID().uuidString)!,
                dateProvider: date
            ),
            dateProvider: date
        )

        let repository = StubProjectRepository()
        for project in seedProjects(
            spaceID: spaceID,
            meID: me, partnerID: partner,
            meCount: meCount,
            partnerCount: partnerCount
        ) {
            _ = try? await repository.saveProject(project, actorID: project.creatorID)
        }

        let vm = ProjectsViewModel(
            sessionStore: sessionStore,
            projectRepository: repository,
            premiumGate: gate
        )
        await vm.load()
        return (vm, gate, me, partner)
    }

    private func makeDraft(creatorID: UUID, spaceID: UUID = MockDataFactory.singleSpaceID) -> Project {
        Project(
            id: UUID(),
            spaceID: spaceID,
            creatorID: creatorID,
            name: "New Project",
            notes: nil,
            colorToken: nil,
            status: .active,
            targetDate: nil,
            remindAt: nil,
            taskCount: 0,
            subtasks: [],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
    }

    private func seedProjects(
        spaceID: UUID,
        meID: UUID,
        partnerID: UUID,
        meCount: Int,
        partnerCount: Int
    ) -> [Project] {
        let mine = (0..<meCount).map { i in
            Project(
                id: UUID(), spaceID: spaceID, creatorID: meID,
                name: "Mine \(i)", notes: nil, colorToken: nil,
                status: .active, targetDate: nil, remindAt: nil,
                taskCount: 0, subtasks: [],
                createdAt: Date(), updatedAt: Date(), completedAt: nil
            )
        }
        let partners = (0..<partnerCount).map { i in
            Project(
                id: UUID(), spaceID: spaceID, creatorID: partnerID,
                name: "Partner \(i)", notes: nil, colorToken: nil,
                status: .active, targetDate: nil, remindAt: nil,
                taskCount: 0, subtasks: [],
                createdAt: Date(), updatedAt: Date(), completedAt: nil
            )
        }
        return mine + partners
    }
}
