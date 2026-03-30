import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

enum UserProfileSaveError: LocalizedError {
    case avatarFileWriteFailed(underlying: Error)
    case profilePersistenceFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .avatarFileWriteFailed:
            return "头像文件保存失败。"
        case .profilePersistenceFailed:
            return "资料写入本地数据库失败。"
        }
    }
}

actor LocalUserProfileRepository: UserProfileRepositoryProtocol {
    private let container: ModelContainer
    private let avatarMediaStore: UserAvatarMediaStoreProtocol

    init(
        container: ModelContainer,
        avatarMediaStore: UserAvatarMediaStoreProtocol = LocalUserAvatarMediaStore()
    ) {
        self.container = container
        self.avatarMediaStore = avatarMediaStore
    }

    func mergedUser(_ user: User?) async -> User? {
        guard let user else { return nil }
        let context = ModelContext(container)
        let userID = user.id
        let canonicalFileName = avatarMediaStore.canonicalFileName(for: userID)
        #if DEBUG
        StartupTrace.mark(
            "UserProfileRepository.merge.begin userID=\(userID.uuidString.lowercased()) canonicalFile=\(canonicalFileName) fileExists=\(avatarMediaStore.fileExists(named: canonicalFileName))"
        )
        #endif
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )

        guard let record = try? context.fetch(descriptor).first else {
            #if DEBUG
            StartupTrace.mark("UserProfileRepository.merge.recordMissing")
            #endif
            return recoverAvatarFromCanonicalFileIfNeeded(
                user: user,
                canonicalFileName: canonicalFileName,
                context: context
            )
        }

        #if DEBUG
        StartupTrace.mark(
            "UserProfileRepository.merge.recordFound avatarFile=\(record.avatarPhotoFileName ?? "nil") payloadBytes=\(record.avatarPhotoData?.count ?? 0)"
        )
        #endif

        repairAvatarMetadataIfNeeded(record: record, context: context, userID: userID)

        var mergedUser = record.apply(to: user)
        if record.avatarPhotoData != nil {
            mergedUser.avatarPhotoFileName = canonicalFileName
            if record.avatarPhotoFileName != canonicalFileName {
                record.avatarPhotoFileName = canonicalFileName
                try? context.save()
            }
        } else if let fileName = mergedUser.avatarPhotoFileName {
            if avatarMediaStore.fileExists(named: fileName) == false {
                if avatarMediaStore.fileExists(named: canonicalFileName) {
                    mergedUser.avatarPhotoFileName = canonicalFileName
                    record.avatarPhotoFileName = canonicalFileName
                    try? context.save()
                } else {
                    mergedUser.avatarPhotoFileName = nil
                }
            }
        } else if avatarMediaStore.fileExists(named: canonicalFileName) {
            mergedUser.avatarPhotoFileName = canonicalFileName
            record.avatarPhotoFileName = canonicalFileName
            try? context.save()
        }
        #if DEBUG
        StartupTrace.mark(
            "UserProfileRepository.merge.end mergedAvatarFile=\(mergedUser.avatarPhotoFileName ?? "nil") canonicalExists=\(avatarMediaStore.fileExists(named: canonicalFileName))"
        )
        #endif
        return mergedUser
    }

    func saveProfile(
        for user: User,
        displayName: String,
        avatarUpdate: UserAvatarUpdate
    ) async throws -> User {
        let context = ModelContext(container)
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )

        let sanitizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedUser = user
        updatedUser.displayName = sanitizedName
        updatedUser.updatedAt = .now
        var rollbackActions: [AvatarRollbackAction] = []

        switch avatarUpdate {
        case .preserveExisting:
            break
        case .removeCustomPhoto:
            if let existingFileName = updatedUser.avatarPhotoFileName {
                if let existingData = try? avatarMediaStore.avatarData(named: existingFileName) {
                    rollbackActions.append(.restore(fileName: existingFileName, data: existingData))
                }
                try? avatarMediaStore.removeAvatar(named: existingFileName)
            }
            updatedUser.avatarPhotoFileName = nil
        case .replacePhoto(let data):
            let fileName = avatarMediaStore.canonicalFileName(for: user.id)
            if avatarMediaStore.fileExists(named: fileName) {
                if let previousData = try? avatarMediaStore.avatarData(named: fileName) {
                    rollbackActions.append(.restore(fileName: fileName, data: previousData))
                }
            } else {
                rollbackActions.append(.remove(fileName: fileName))
            }

            do {
                try avatarMediaStore.persistAvatarData(data, fileName: fileName)
            } catch {
                throw UserProfileSaveError.avatarFileWriteFailed(underlying: error)
            }

            preloadRuntimeAvatarIfPossible(data: data, fileName: fileName)

            if let existingFileName = updatedUser.avatarPhotoFileName, existingFileName != fileName {
                if let existingData = try? avatarMediaStore.avatarData(named: existingFileName) {
                    rollbackActions.append(.restore(fileName: existingFileName, data: existingData))
                }
                try? avatarMediaStore.removeAvatar(named: existingFileName)
            }
            updatedUser.avatarPhotoFileName = fileName
        }

        do {
            if let existingRecord = try context.fetch(descriptor).first {
                existingRecord.update(from: updatedUser)
                applyAvatarPayload(to: existingRecord, avatarUpdate: avatarUpdate)
            } else {
                let record = PersistentUserProfile(user: updatedUser)
                applyAvatarPayload(to: record, avatarUpdate: avatarUpdate)
                context.insert(record)
            }

            try context.save()
            return updatedUser
        } catch {
            rollbackAvatarChanges(rollbackActions)
            throw UserProfileSaveError.profilePersistenceFailed(underlying: error)
        }
    }

    func savePreferences(
        for user: User,
        preferences: NotificationSettings
    ) async throws -> User {
        let context = ModelContext(container)
        let userID = user.id
        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )

        var updatedUser = user
        updatedUser.preferences = preferences
        updatedUser.updatedAt = .now

        if let existingRecord = try context.fetch(descriptor).first {
            existingRecord.update(from: updatedUser)
        } else {
            context.insert(PersistentUserProfile(user: updatedUser))
        }

        try context.save()
        return updatedUser
    }

    private func applyAvatarPayload(
        to record: PersistentUserProfile,
        avatarUpdate: UserAvatarUpdate
    ) {
        switch avatarUpdate {
        case .preserveExisting:
            break
        case .removeCustomPhoto:
            record.avatarPhotoData = nil
        case .replacePhoto(let data):
            record.avatarPhotoData = data
        }
    }

    private func repairAvatarMetadataIfNeeded(
        record: PersistentUserProfile,
        context: ModelContext,
        userID: UUID
    ) {
        let canonicalFileName = avatarMediaStore.canonicalFileName(for: userID)

        if let avatarPhotoData = record.avatarPhotoData {
            preloadRuntimeAvatarIfPossible(data: avatarPhotoData, fileName: canonicalFileName)
            do {
                try avatarMediaStore.persistAvatarData(avatarPhotoData, fileName: canonicalFileName)
            } catch {
                #if DEBUG
                StartupTrace.mark(
                    "UserProfileRepository.repair.persistFailed file=\(canonicalFileName) error=\(String(describing: error))"
                )
                #endif
            }

            if record.avatarPhotoFileName != canonicalFileName {
                record.avatarPhotoFileName = canonicalFileName
                try? context.save()
            }
            return
        }

        guard let storedFileName = record.avatarPhotoFileName else {
            return
        }

        var hasMutatedRecord = false

        if storedFileName != canonicalFileName, avatarMediaStore.fileExists(named: storedFileName) {
            try? avatarMediaStore.migrateAvatarIfNeeded(from: storedFileName, to: canonicalFileName)
            record.avatarPhotoFileName = canonicalFileName
            hasMutatedRecord = true
        }

        let resolvedFileName = record.avatarPhotoFileName ?? canonicalFileName
        if avatarMediaStore.fileExists(named: resolvedFileName) == false {
            if let avatarPhotoData = record.avatarPhotoData {
                try? avatarMediaStore.persistAvatarData(avatarPhotoData, fileName: canonicalFileName)
                record.avatarPhotoFileName = canonicalFileName
                hasMutatedRecord = true
            } else {
                record.avatarPhotoFileName = nil
                hasMutatedRecord = true
            }
        }

        if hasMutatedRecord {
            try? context.save()
        }
    }

    private func rollbackAvatarChanges(_ actions: [AvatarRollbackAction]) {
        for action in actions.reversed() {
            switch action {
            case .restore(let fileName, let data):
                try? avatarMediaStore.persistAvatarData(data, fileName: fileName)
            case .remove(let fileName):
                try? avatarMediaStore.removeAvatar(named: fileName)
            }
        }
    }

    private func recoverAvatarFromCanonicalFileIfNeeded(
        user: User,
        canonicalFileName: String,
        context: ModelContext
    ) -> User {
        guard avatarMediaStore.fileExists(named: canonicalFileName) else {
            return user
        }

        if let avatarData = try? avatarMediaStore.avatarData(named: canonicalFileName) {
            preloadRuntimeAvatarIfPossible(data: avatarData, fileName: canonicalFileName)
        }

        var recoveredUser = user
        recoveredUser.avatarPhotoFileName = canonicalFileName
        recoveredUser.updatedAt = .now

        context.insert(PersistentUserProfile(user: recoveredUser))
        try? context.save()
        return recoveredUser
    }

    private func preloadRuntimeAvatarIfPossible(data: Data, fileName: String) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return }
        UserAvatarRuntimeStore.store(image, for: fileName)
        #endif
    }
}

private enum AvatarRollbackAction {
    case restore(fileName: String, data: Data)
    case remove(fileName: String)
}
