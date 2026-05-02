import Foundation
import Testing
@testable import Together

@MainActor
@Suite
struct ImportantDatesViewModelQuotaTests {

    // 配额从 5 调整为 3（2026-04-24 产品决策，纪念日比项目高频更适合做付费门槛）

    @Test func freeUnderQuotaAllowsCreate() async {
        let (vm, _, me, _) = await makeViewModel(existingCountByMe: 2)
        await vm.createNew(makeDraft(creatorID: me))

        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.events.filter { $0.creatorID == me }.count == 3)
    }

    @Test func freeAtQuotaBlocksCreate() async {
        let (vm, _, me, _) = await makeViewModel(existingCountByMe: 3)
        await vm.createNew(makeDraft(creatorID: me))

        #expect(vm.pendingUpsellTrigger == .anniversaryQuota)
        #expect(vm.events.filter { $0.creatorID == me }.count == 3)  // 未新增
    }

    @Test func proBypassesQuota() async {
        let (vm, gate, me, _) = await makeViewModel(existingCountByMe: 10)
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)

        await vm.createNew(makeDraft(creatorID: me))

        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.events.filter { $0.creatorID == me }.count == 11)
    }

    @Test func gracePeriodDoesNotBypassQuota() async {
        let (vm, gate, me, _) = await makeViewModel(existingCountByMe: 3)
        gate.overrideStatus = .gracePeriod(
            originalExpiry: Date(timeIntervalSinceNow: -3600),
            logbookFullUntil: Date(timeIntervalSinceNow: 7 * 86400)
        )

        await vm.createNew(makeDraft(creatorID: me))

        #expect(vm.pendingUpsellTrigger == .anniversaryQuota)
        #expect(vm.events.filter { $0.creatorID == me }.count == 3)
    }

    @Test func partnerEventsDoNotCountAgainstMyQuota() async {
        let (vm, _, me, _) = await makeViewModel(
            existingCountByMe: 2,
            existingCountByPartner: 100
        )
        await vm.createNew(makeDraft(creatorID: me))

        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.events.filter { $0.creatorID == me }.count == 3)
    }

    @Test func dismissUpsellClearsTrigger() async {
        let (vm, _, me, _) = await makeViewModel(existingCountByMe: 3)
        await vm.createNew(makeDraft(creatorID: me))
        #expect(vm.pendingUpsellTrigger == .anniversaryQuota)

        vm.dismissUpsell()
        #expect(vm.pendingUpsellTrigger == nil)
    }

    // MARK: - Helpers

    private func makeViewModel(
        existingCountByMe: Int,
        existingCountByPartner: Int = 0
    ) async -> (ImportantDatesViewModel, PremiumGate, UUID, UUID) {
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

        // 预置 repository 里已有事件，再通过 load() 拉回 ViewModel.events。
        // 走真实 repo 路径，这样 createNew 里的 persist() → load() 能正确更新 events。
        let repository = MockImportantDateRepository()
        for event in seedEvents(
            spaceID: spaceID,
            meID: me, partnerID: partner,
            meCount: existingCountByMe,
            partnerCount: existingCountByPartner
        ) {
            try? await repository.save(event)
        }

        let vm = ImportantDatesViewModel(
            sessionStore: sessionStore,
            premiumGate: gate,
            repository: repository
        )
        vm.configure(spaceID: spaceID)
        await vm.load()
        return (vm, gate, me, partner)
    }

    private func makeDraft(creatorID: UUID, spaceID: UUID = MockDataFactory.singleSpaceID) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: spaceID,
            creatorID: creatorID,
            kind: .custom,
            title: "New event",
            dateValue: Date(),
            recurrence: .none,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: Date()
        )
    }

    private func seedEvents(
        spaceID: UUID,
        meID: UUID,
        partnerID: UUID,
        meCount: Int,
        partnerCount: Int
    ) -> [ImportantDate] {
        let mine = (0..<meCount).map { i in
            ImportantDate(
                id: UUID(), spaceID: spaceID, creatorID: meID,
                kind: .custom, title: "Mine \(i)",
                dateValue: Date(), recurrence: .none,
                notifyDaysBefore: 7, notifyOnDay: true,
                icon: nil, presetHolidayID: nil, updatedAt: Date()
            )
        }
        let partners = (0..<partnerCount).map { i in
            ImportantDate(
                id: UUID(), spaceID: spaceID, creatorID: partnerID,
                kind: .custom, title: "Partner \(i)",
                dateValue: Date(), recurrence: .none,
                notifyDaysBefore: 7, notifyOnDay: true,
                icon: nil, presetHolidayID: nil, updatedAt: Date()
            )
        }
        return mine + partners
    }
}
