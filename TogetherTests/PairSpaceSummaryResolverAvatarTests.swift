import Testing
import Foundation
@testable import Together

@Suite("PairSpaceSummaryResolver — avatar")
struct PairSpaceSummaryResolverAvatarTests {

    // MARK: - Helpers

    private static let myUserID = UUID()
    private static let partnerUserID = UUID()
    private static let pairSpaceID = UUID()
    private static let sharedSpaceID = UUID()
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSharedSpace() -> PersistentSpace {
        PersistentSpace(
            id: Self.sharedSpaceID,
            typeRawValue: "pair",
            displayName: "Us",
            ownerUserID: Self.myUserID,
            statusRawValue: "active",
            createdAt: Self.now,
            updatedAt: Self.now,
            archivedAt: nil
        )
    }

    private func makePairSpace() -> PersistentPairSpace {
        PersistentPairSpace(
            id: Self.pairSpaceID,
            sharedSpaceID: Self.sharedSpaceID,
            statusRawValue: "active",
            createdAt: Self.now,
            activatedAt: Self.now,
            endedAt: nil,
            isZoneOwner: false
        )
    }

    private func makeMemberships(
        avatarAssetID: String?,
        avatarSystemName: String?,
        avatarPhotoFileName: String?,
        avatarVersion: Int
    ) -> [PersistentPairMembership] {
        [
            PersistentPairMembership(
                pairSpaceID: Self.pairSpaceID,
                userID: Self.myUserID,
                nickname: "Me",
                joinedAt: Self.now
            ),
            PersistentPairMembership(
                pairSpaceID: Self.pairSpaceID,
                userID: Self.partnerUserID,
                nickname: "Partner",
                joinedAt: Self.now,
                avatarSystemName: avatarSystemName,
                avatarPhotoFileName: avatarPhotoFileName,
                avatarAssetID: avatarAssetID,
                avatarVersion: avatarVersion
            )
        ]
    }

    // MARK: - Tests

    @Test("Partner User inherits avatarAssetID + avatarSystemName + avatarVersion from membership")
    func resolverPassesAllAvatarFields() throws {
        let memberships = makeMemberships(
            avatarAssetID: "asset-partner-1",
            avatarSystemName: nil,
            avatarPhotoFileName: "asset-asset-partner-1.jpg",
            avatarVersion: 9
        )

        let summary = try #require(
            PairSpaceSummaryResolver.resolve(
                for: Self.myUserID,
                spaces: [makeSharedSpace()],
                pairSpaces: [makePairSpace()],
                memberships: memberships
            )
        )

        #expect(summary.partner?.avatarAssetID == "asset-partner-1")
        #expect(summary.partner?.avatarVersion == 9)
        // Resolver substitutes the default SF symbol when avatarSystemName is nil
        #expect(summary.partner?.avatarSystemName == "person.crop.circle.fill")
        #expect(summary.partner?.avatarPhotoFileName == "asset-asset-partner-1.jpg")
    }

    @Test("Partner User gets SF Symbol name when asset is symbol-only")
    func resolverPassesSystemName() throws {
        let memberships = makeMemberships(
            avatarAssetID: nil,
            avatarSystemName: "person.crop.circle.fill",
            avatarPhotoFileName: nil,
            avatarVersion: 2
        )

        let summary = try #require(
            PairSpaceSummaryResolver.resolve(
                for: Self.myUserID,
                spaces: [makeSharedSpace()],
                pairSpaces: [makePairSpace()],
                memberships: memberships
            )
        )

        #expect(summary.partner?.avatarSystemName == "person.crop.circle.fill")
        #expect(summary.partner?.avatarAssetID == nil)
        #expect(summary.partner?.avatarPhotoFileName == nil)
    }
}
