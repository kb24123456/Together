import Foundation

/// In-memory test double for UserProfileRemoteRepository.
actor MockUserProfileRemoteRepository: UserProfileRemoteRepositoryProtocol {
    private var rows: [UUID: UserProfileDTO]
    private(set) var upsertCallCount = 0
    private(set) var fetchByUserIDCallCount = 0
    private var ownUserID: UUID?

    init(seed: [UserProfileDTO] = [], ownUserID: UUID? = nil) {
        var indexed: [UUID: UserProfileDTO] = [:]
        for dto in seed { indexed[dto.userID] = dto }
        self.rows = indexed
        self.ownUserID = ownUserID
    }

    func setOwnUserID(_ id: UUID?) { self.ownUserID = id }

    func fetchOwn() async throws -> UserProfileDTO? {
        guard let ownUserID else { return nil }
        return rows[ownUserID]
    }

    func fetchByUserID(_ userID: UUID) async throws -> UserProfileDTO? {
        fetchByUserIDCallCount += 1
        return rows[userID]
    }

    func upsertOwn(_ dto: UserProfileDTO) async throws {
        rows[dto.userID] = dto
        upsertCallCount += 1
    }
}
