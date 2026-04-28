import Foundation
import Testing
@testable import Together

@Suite("AppContext solo mutation Supabase sync")
@MainActor
struct AppContextSoloMutationSyncTests {
    @Test("iPhone single-space mutation pushes pending solo changes to Supabase")
    func iphoneSingleMutationPushesPendingSoloChanges() async throws {
        let service = RecordingSoloSyncService()
        let context = makeContext(soloSyncService: service)
        let supabaseUserID = UUID()

        await context.pushSoloSupabaseMutationIfEligible(
            spaceID: MockDataFactory.singleSpaceID,
            supabaseUserID: supabaseUserID,
            platform: .iphone
        )

        let pushes = await service.pushes()
        #expect(pushes.count == 1)
        #expect(pushes.first?.spaceID == MockDataFactory.singleSpaceID)
        #expect(pushes.first?.userID == supabaseUserID)
    }

    @Test("non-Pro iPad single mutation does not push pending solo changes")
    func nonProIPadSingleMutationDoesNotPushPendingSoloChanges() async throws {
        let service = RecordingSoloSyncService()
        let context = makeContext(soloSyncService: service)

        await context.pushSoloSupabaseMutationIfEligible(
            spaceID: MockDataFactory.singleSpaceID,
            supabaseUserID: UUID(),
            platform: .ipad
        )

        #expect(await service.pushes().isEmpty)
    }

    @Test("pair-space mutation does not enter solo Supabase push path")
    func pairSpaceMutationDoesNotEnterSoloSupabasePushPath() async throws {
        let service = RecordingSoloSyncService()
        let context = makeContext(soloSyncService: service)

        await context.pushSoloSupabaseMutationIfEligible(
            spaceID: MockDataFactory.pairSharedSpaceID,
            supabaseUserID: UUID(),
            platform: .iphone
        )

        #expect(await service.pushes().isEmpty)
    }

    @Test("recorded single-space mutation pushes through production callback path")
    func recordedSingleMutationPushesThroughProductionCallbackPath() async throws {
        let service = RecordingSoloSyncService()
        let context = makeContext(soloSyncService: service)
        let supabaseUserID = UUID()

        await context.flushRecordedMutation(
            SyncChange(
                entityKind: .task,
                operation: .upsert,
                recordID: UUID(),
                spaceID: MockDataFactory.singleSpaceID
            ),
            supabaseUserID: supabaseUserID,
            platform: .iphone
        )

        let pushes = await service.pushes()
        #expect(pushes.count == 1)
        #expect(pushes.first?.spaceID == MockDataFactory.singleSpaceID)
        #expect(pushes.first?.userID == supabaseUserID)
    }

    private func makeContext(soloSyncService: RecordingSoloSyncService) -> AppContext {
        let sessionStore = SessionStore()
        sessionStore.seedMock(
            currentUser: MockDataFactory.makeCurrentUser(),
            singleSpace: MockDataFactory.makeSingleSpace(),
            pairSummary: MockDataFactory.makePairSpaceSummary()
        )
        return AppContext(
            container: MockServiceFactory.makeContainer(supabaseSoloSyncService: soloSyncService),
            sessionStore: sessionStore,
            router: AppRouter()
        )
    }
}

private actor RecordingSoloSyncService: SupabaseSoloSyncServicing {
    private var recordedPushes: [(spaceID: UUID, userID: UUID)] = []

    func pushes() -> [(spaceID: UUID, userID: UUID)] {
        recordedPushes
    }

    func start(
        userID: UUID,
        localUserID: UUID,
        displayName: String,
        platform: SoloDevicePlatform,
        isPro: Bool
    ) async throws {}

    func pushPending(spaceID: UUID, userID: UUID) async throws {
        recordedPushes.append((spaceID, userID))
    }

    func diagnostics(
        userID: UUID,
        spaceID: UUID?,
        platform: SoloDevicePlatform,
        isPro: Bool
    ) async -> SoloSyncDiagnosticSnapshot {
        SoloSyncDiagnosticSnapshot(
            userID: userID,
            spaceID: spaceID,
            platform: platform,
            gateDecision: SoloSyncGate.decision(platform: platform, isPro: isPro),
            localTaskCount: 0,
            remoteTaskCount: 0,
            pendingMutationCount: 0,
            failedMutationCount: 0,
            lastPulledAt: nil,
            lastPushedAt: nil,
            migrationCompletedAt: nil,
            lastError: nil
        )
    }
}
