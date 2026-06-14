import Foundation
import os

actor UserProfileRemoteRepository: UserProfileRemoteRepositoryProtocol {
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "UserProfileRemote")

    init() {}

    func fetchOwn() async throws -> UserProfileDTO? {
        nil
    }

    func fetchByUserID(_ userID: UUID) async throws -> UserProfileDTO? {
        logger.debug("remote profile fetch skipped; userID=\(userID.uuidString, privacy: .public)")
        return nil
    }

    func upsertOwn(_ dto: UserProfileDTO) async throws {
        logger.debug("remote profile upsert skipped; userID=\(dto.userID.uuidString, privacy: .public)")
    }
}
