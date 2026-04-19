import Foundation
import os

/// 诊断 `Item.status` / `completedAt` 在哪一条路径上被修改。
///
/// 用法：Console.app filter `subsystem:com.together.diagnosis category:item-status`
///
/// 所有方法打 `.info` 级别。Release build 由 unified logging 自动过滤；
/// 纯观测，不改任何行为，因此不需要 `#if DEBUG` 包裹。
enum ItemStatusDiagnosisLog {
    private static let logger = Logger(
        subsystem: "com.together.diagnosis",
        category: "item-status"
    )

    // MARK: - markCompleted path

    static func markCompletedBegin(
        itemID: UUID,
        oldStatus: String,
        oldCompletedAt: Date?,
        actorID: UUID,
        creatorID: UUID,
        hasRepeatRule: Bool
    ) {
        logger.info("""
            markCompleted.begin \
            itemID=\(itemID.uuidString, privacy: .public) \
            oldStatus=\(oldStatus, privacy: .public) \
            oldCompletedAt=\(oldCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            actorID=\(actorID.uuidString, privacy: .public) \
            creatorID=\(creatorID.uuidString, privacy: .public) \
            hasRepeatRule=\(hasRepeatRule, privacy: .public)
            """)
    }

    static func markCompletedSaved(
        itemID: UUID,
        newStatus: String,
        newCompletedAt: Date?
    ) {
        logger.info("""
            markCompleted.saved \
            itemID=\(itemID.uuidString, privacy: .public) \
            newStatus=\(newStatus, privacy: .public) \
            newCompletedAt=\(newCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public)
            """)
    }

    static func markCompletedReadback(
        itemID: UUID,
        readbackStatus: String?,
        readbackCompletedAt: Date?
    ) {
        logger.info("""
            markCompleted.readback \
            itemID=\(itemID.uuidString, privacy: .public) \
            readbackStatus=\(readbackStatus ?? "nil", privacy: .public) \
            readbackCompletedAt=\(readbackCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public)
            """)
    }

    // MARK: - Solo CKSyncEngine apply path

    enum ApplyDecision: String {
        case applied
        case skippedStale
        case skippedNotFound
    }

    static func soloSyncApplyBegin(
        itemID: UUID,
        incomingStatus: String,
        incomingCompletedAt: Date?,
        localStatus: String?,
        localCompletedAt: Date?,
        incomingUpdatedAt: Date,
        localUpdatedAt: Date?,
        hasPendingLocalSave: Bool
    ) {
        logger.info("""
            soloSync.apply.begin \
            itemID=\(itemID.uuidString, privacy: .public) \
            incomingStatus=\(incomingStatus, privacy: .public) \
            incomingCompletedAt=\(incomingCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            localStatus=\(localStatus ?? "nil", privacy: .public) \
            localCompletedAt=\(localCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            incomingUpdatedAt=\(incomingUpdatedAt.iso8601, privacy: .public) \
            localUpdatedAt=\(localUpdatedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            hasPendingLocalSave=\(hasPendingLocalSave, privacy: .public)
            """)
    }

    static func soloSyncApplyDone(itemID: UUID, decision: ApplyDecision) {
        logger.info("""
            soloSync.apply.done \
            itemID=\(itemID.uuidString, privacy: .public) \
            decision=\(decision.rawValue, privacy: .public)
            """)
    }

    // MARK: - Supabase apply path

    static func supabaseApplyBegin(
        itemID: UUID,
        incomingStatus: String,
        incomingCompletedAt: Date?,
        localStatus: String?,
        localCompletedAt: Date?,
        incomingUpdatedAt: Date,
        localUpdatedAt: Date?
    ) {
        logger.info("""
            supabaseSync.apply.begin \
            itemID=\(itemID.uuidString, privacy: .public) \
            incomingStatus=\(incomingStatus, privacy: .public) \
            incomingCompletedAt=\(incomingCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            localStatus=\(localStatus ?? "nil", privacy: .public) \
            localCompletedAt=\(localCompletedAt.map { $0.iso8601 } ?? "nil", privacy: .public) \
            incomingUpdatedAt=\(incomingUpdatedAt.iso8601, privacy: .public) \
            localUpdatedAt=\(localUpdatedAt.map { $0.iso8601 } ?? "nil", privacy: .public)
            """)
    }

    static func supabaseApplyDone(itemID: UUID, decision: ApplyDecision) {
        logger.info("""
            supabaseSync.apply.done \
            itemID=\(itemID.uuidString, privacy: .public) \
            decision=\(decision.rawValue, privacy: .public)
            """)
    }
}

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
