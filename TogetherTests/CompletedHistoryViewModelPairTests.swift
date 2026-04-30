import Foundation
import Testing
@testable import Together

@MainActor
@Suite
struct CompletedHistoryViewModelPairTests {

    private func makeGate() -> PremiumGate {
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
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        return gate
    }

    @Test func avatarAssetForCurrentUserIDReturnsCurrentUserAsset() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        guard let userID = context.sessionStore.currentUser?.id else {
            Issue.record("Bootstrap must seed a currentUser")
            return
        }
        let expected = context.sessionStore.currentUser?.avatarAsset ?? .system("person.crop.circle.fill")
        #expect(vm.avatarAsset(forUserID: userID) == expected)
    }

    @Test func avatarAssetForUnknownIDFallsBackToGenericPerson() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        let asset = vm.avatarAsset(forUserID: UUID())
        #expect(asset == .system("person.fill"))
    }

    @Test func avatarAssetForNilFallsBackToGenericPerson() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        let asset = vm.avatarAsset(forUserID: nil)
        #expect(asset == .system("person.fill"))
    }

    @Test func displayNameForUnknownIDFallsBack() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        #expect(vm.displayName(forUserID: UUID()) == "未知完成者")
        #expect(vm.displayName(forUserID: nil) == "未知完成者")
    }

    @Test func isPairModeReflectsSessionStore() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        // Bootstrap seeds a paired mock session
        #expect(vm.isPairMode == true)
    }

    @Test func deleteFallsBackForLegacyHistoryRowsWhoseCreatorDrifted() async throws {
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace(),
            pairSummary: MockDataFactory.makePairSpaceSummary()
        )
        sessionStore.switchWorkspace(to: .pair)

        let repository = TestItemRepository()
        let taskID = UUID()
        let completedAt = Date.now
        let legacyItem = Item(
            id: taskID,
            spaceID: MockDataFactory.pairSharedSpaceID,
            listID: nil,
            projectID: nil,
            creatorID: UUID(),
            title: "旧配对残留日志",
            notes: nil,
            locationText: nil,
            executionRole: .initiator,
            dueAt: completedAt,
            hasExplicitTime: false,
            remindAt: nil,
            status: .completed,
            latestResponse: nil,
            responseHistory: [],
            createdAt: completedAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            completedByUserID: nil,
            isPinned: false,
            isDraft: false
        )
        _ = try await repository.saveItem(legacyItem)

        let viewModel = CompletedHistoryViewModel(
            sessionStore: sessionStore,
            itemRepository: repository,
            taskApplicationService: DefaultTaskApplicationService(
                itemRepository: repository,
                taskMessageRepository: NoopTaskMessageRepository(),
                syncCoordinator: NoOpSyncCoordinator(),
                reminderScheduler: MockReminderScheduler()
            ),
            taskListRepository: MockTaskListRepository(),
            projectRepository: MockProjectRepository(reminderScheduler: MockReminderScheduler()),
            premiumGate: makeGate()
        )
        viewModel.items = [legacyItem]

        await viewModel.delete(legacyItem)

        let remaining = try await repository.fetchCompletedItems(
            spaceID: MockDataFactory.pairSharedSpaceID,
            searchText: nil,
            before: nil,
            since: nil,
            limit: 10
        )
        #expect(viewModel.items.isEmpty)
        #expect(remaining.contains { $0.id == taskID } == false)
    }
}
