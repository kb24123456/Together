import Foundation
import SwiftData
import TogetherCore
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
        let hasLegacyRepairPayload = record.avatarPhotoData != nil
        let resolvedAssetID = normalizedAvatarAssetID(
            currentAssetID: mergedUser.avatarAssetID,
            fallbackUserID: userID,
            hasAvatarPayload: mergedUser.avatarPhotoFileName != nil || hasLegacyRepairPayload
        )
        let resolvedCacheFileName = resolvedAssetID.map { avatarMediaStore.cacheFileName(for: $0) }
        if let fileName = mergedUser.avatarPhotoFileName {
            if avatarMediaStore.fileExists(named: fileName) == false {
                if avatarMediaStore.fileExists(named: canonicalFileName) {
                    if let resolvedCacheFileName {
                        try? avatarMediaStore.migrateAvatarIfNeeded(
                            from: canonicalFileName,
                            to: resolvedCacheFileName
                        )
                        mergedUser.avatarPhotoFileName = resolvedCacheFileName
                        record.avatarPhotoFileName = resolvedCacheFileName
                    }
                    mergedUser.avatarAssetID = resolvedAssetID
                    record.avatarAssetID = resolvedAssetID
                    try? context.save()
                } else if hasLegacyRepairPayload {
                    // Keep the current avatar reference while the legacy/local repair payload still
                    // exists. The blob is not shared-authority truth, but it is sufficient to avoid
                    // spuriously clearing local avatar metadata when file repair temporarily fails.
                } else if mergedUser.avatarAssetID == nil {
                    mergedUser.avatarPhotoFileName = nil
                }
            } else if let resolvedAssetID,
                      let resolvedCacheFileName,
                      (mergedUser.avatarAssetID != resolvedAssetID || fileName != resolvedCacheFileName) {
                try? avatarMediaStore.migrateAvatarIfNeeded(from: fileName, to: resolvedCacheFileName)
                mergedUser.avatarPhotoFileName = resolvedCacheFileName
                mergedUser.avatarAssetID = resolvedAssetID
                record.avatarPhotoFileName = resolvedCacheFileName
                record.avatarAssetID = resolvedAssetID
                try? context.save()
            }
        } else if avatarMediaStore.fileExists(named: canonicalFileName) {
            let repairedAssetID = normalizedAvatarAssetID(
                currentAssetID: record.avatarAssetID,
                fallbackUserID: userID,
                hasAvatarPayload: true
            )
            let repairedCacheFileName = repairedAssetID.map { avatarMediaStore.cacheFileName(for: $0) } ?? canonicalFileName
            try? avatarMediaStore.migrateAvatarIfNeeded(from: canonicalFileName, to: repairedCacheFileName)
            mergedUser.avatarPhotoFileName = repairedCacheFileName
            mergedUser.avatarAssetID = repairedAssetID
            record.avatarPhotoFileName = repairedCacheFileName
            record.avatarAssetID = repairedAssetID
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
            updatedUser.avatarAssetID = nil
            updatedUser.avatarVersion += 1
        case .replacePhoto(let data):
            let assetID = userID.uuidString.lowercased()
            let fileName = avatarMediaStore.cacheFileName(for: assetID)
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
            updatedUser.avatarAssetID = assetID
            updatedUser.avatarVersion += 1
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

    func hydrateFromRemote(
        for user: User,
        displayName: String,
        avatarBytes: Data?,
        avatarAssetID: String?,
        avatarSystemName: String?,
        avatarVersion: Int
    ) async throws -> User {
        let context = ModelContext(container)
        let userID = user.id

        var hydratedUser = user
        hydratedUser.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        hydratedUser.avatarSystemName = avatarSystemName
        hydratedUser.avatarAssetID = avatarAssetID
        hydratedUser.avatarVersion = avatarVersion
        hydratedUser.updatedAt = .now

        if let bytes = avatarBytes, let assetID = avatarAssetID {
            let fileName = avatarMediaStore.cacheFileName(for: assetID)
            do {
                try avatarMediaStore.persistAvatarData(bytes, fileName: fileName)
                hydratedUser.avatarPhotoFileName = fileName
                preloadRuntimeAvatarIfPossible(data: bytes, fileName: fileName)
            } catch {
                throw UserProfileSaveError.avatarFileWriteFailed(underlying: error)
            }
        } else {
            hydratedUser.avatarPhotoFileName = nil
        }

        let descriptor = FetchDescriptor<PersistentUserProfile>(
            predicate: #Predicate { $0.userID == userID }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.update(from: hydratedUser)
                if let bytes = avatarBytes {
                    existing.avatarPhotoData = bytes
                } else {
                    existing.avatarPhotoData = nil
                }
            } else {
                let record = PersistentUserProfile(user: hydratedUser)
                if let bytes = avatarBytes {
                    record.avatarPhotoData = bytes
                }
                context.insert(record)
            }
            try context.save()
            return hydratedUser
        } catch {
            throw UserProfileSaveError.profilePersistenceFailed(underlying: error)
        }
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
            record.avatarAssetID = nil
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
        let normalizedAssetID = normalizedAvatarAssetID(
            currentAssetID: record.avatarAssetID,
            fallbackUserID: userID,
            hasAvatarPayload: record.avatarPhotoFileName != nil || record.avatarPhotoData != nil
        )
        let normalizedCacheFileName = normalizedAssetID.map { avatarMediaStore.cacheFileName(for: $0) }

        if let avatarPhotoData = record.avatarPhotoData {
            let targetFileName = normalizedCacheFileName ?? canonicalFileName
            preloadRuntimeAvatarIfPossible(data: avatarPhotoData, fileName: targetFileName)
            do {
                try avatarMediaStore.persistAvatarData(avatarPhotoData, fileName: targetFileName)
            } catch {
                #if DEBUG
                StartupTrace.mark(
                    "UserProfileRepository.repair.persistFailed file=\(canonicalFileName) error=\(String(describing: error))"
                )
                #endif
            }

            if record.avatarPhotoFileName != targetFileName || record.avatarAssetID != normalizedAssetID {
                record.avatarPhotoFileName = targetFileName
                record.avatarAssetID = normalizedAssetID
                try? context.save()
            }
            return
        }

        guard let storedFileName = record.avatarPhotoFileName else {
            return
        }

        var hasMutatedRecord = false

        if let normalizedCacheFileName,
           storedFileName != normalizedCacheFileName,
           avatarMediaStore.fileExists(named: storedFileName) {
            try? avatarMediaStore.migrateAvatarIfNeeded(from: storedFileName, to: normalizedCacheFileName)
            record.avatarPhotoFileName = normalizedCacheFileName
            record.avatarAssetID = normalizedAssetID
            hasMutatedRecord = true
        } else if storedFileName != canonicalFileName, avatarMediaStore.fileExists(named: storedFileName) {
            try? avatarMediaStore.migrateAvatarIfNeeded(from: storedFileName, to: canonicalFileName)
            record.avatarPhotoFileName = canonicalFileName
            record.avatarAssetID = normalizedAssetID
            hasMutatedRecord = true
        }

        let resolvedFileName = record.avatarPhotoFileName ?? normalizedCacheFileName ?? canonicalFileName
        if avatarMediaStore.fileExists(named: resolvedFileName) == false {
            if let avatarPhotoData = record.avatarPhotoData {
                let targetFileName = normalizedCacheFileName ?? canonicalFileName
                try? avatarMediaStore.persistAvatarData(avatarPhotoData, fileName: targetFileName)
                record.avatarPhotoFileName = targetFileName
                record.avatarAssetID = normalizedAssetID
                hasMutatedRecord = true
            } else if record.avatarAssetID == nil {
                // A CloudKit external-storage payload may arrive after its profile
                // metadata. Preserve an explicit asset reference until a later import
                // can rebuild the local cache file; absence on disk is not a delete.
                record.avatarPhotoFileName = nil
                hasMutatedRecord = true
            }
        } else if record.avatarAssetID != normalizedAssetID || record.avatarPhotoFileName != resolvedFileName {
            record.avatarAssetID = normalizedAssetID
            record.avatarPhotoFileName = resolvedFileName
            hasMutatedRecord = true
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
        let assetID = normalizedAvatarAssetID(
            currentAssetID: user.avatarAssetID,
            fallbackUserID: user.id,
            hasAvatarPayload: true
        )
        let cacheFileName = assetID.map { avatarMediaStore.cacheFileName(for: $0) } ?? canonicalFileName
        let recoveryFileName: String
        if avatarMediaStore.fileExists(named: cacheFileName) {
            recoveryFileName = cacheFileName
        } else if avatarMediaStore.fileExists(named: canonicalFileName) {
            recoveryFileName = canonicalFileName
        } else {
            return user
        }

        if let avatarData = try? avatarMediaStore.avatarData(named: recoveryFileName) {
            preloadRuntimeAvatarIfPossible(data: avatarData, fileName: recoveryFileName)
        }

        var recoveredUser = user
        try? avatarMediaStore.migrateAvatarIfNeeded(from: recoveryFileName, to: cacheFileName)
        recoveredUser.avatarPhotoFileName = cacheFileName
        recoveredUser.avatarAssetID = assetID
        recoveredUser.updatedAt = .now

        context.insert(PersistentUserProfile(user: recoveredUser))
        try? context.save()
        return recoveredUser
    }

    private func normalizedAvatarAssetID(
        currentAssetID: String?,
        fallbackUserID: UUID,
        hasAvatarPayload: Bool
    ) -> String? {
        guard hasAvatarPayload else { return nil }
        if let currentAssetID,
           let normalizedUUID = UUID(uuidString: currentAssetID)?.uuidString.lowercased() {
            return normalizedUUID
        }
        return fallbackUserID.uuidString.lowercased()
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
