import AppIntents
import Foundation
import SQLite3
import WidgetKit

struct TodayTaskCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "完成今日任务"
    static var description = IntentDescription("从今日小组件完成任务。")
    static var openAppWhenRun = false

    @Parameter(title: "任务 ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard let taskUUID = UUID(uuidString: taskID) else {
            throw TodayWidgetCompletionError.invalidTaskID
        }

        let completedAt = Date.now
        try TodayWidgetCompletionStore().complete(taskID: taskUUID, referenceDate: completedAt)
        try? TodayWidgetSnapshotStore().markTaskCompletedForAnimation(taskID: taskUUID, completedAt: completedAt)

        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
        return .result()
    }
}

private enum TodayWidgetCompletionError: Error {
    case invalidTaskID
    case missingContext
    case missingStore
    case taskNotFound
    case storeOpenFailed(String)
    case storeWriteFailed(String)
    case schemaMismatch(String)
}

private struct TodayWidgetCompletionStore {
    private nonisolated let calendar = Calendar.current

    nonisolated init() {}

    nonisolated func complete(taskID: UUID, referenceDate: Date) throws {
        guard let sharedContext = TodayWidgetSharedContextStore().read() else {
            throw TodayWidgetCompletionError.missingContext
        }
        guard let storeURL = Self.storeURL() else {
            throw TodayWidgetCompletionError.missingStore
        }

        try withDatabase(at: storeURL) { database in
            try execute("BEGIN IMMEDIATE", database: database)
            do {
                try completeInTransaction(
                    taskID: taskID,
                    sharedContext: sharedContext,
                    referenceDate: referenceDate,
                    database: database
                )
                try execute("COMMIT", database: database)
            } catch {
                try? execute("ROLLBACK", database: database)
                throw error
            }
        }
    }

    private nonisolated static func storeURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier)?
            .appending(path: "Together.store")
    }

    private nonisolated func withDatabase(
        at storeURL: URL,
        operation: (OpaquePointer) throws -> Void
    ) throws {
        var rawDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(storeURL.path(percentEncoded: false), &rawDatabase, flags, nil)
        guard openResult == SQLITE_OK, let database = rawDatabase else {
            let message = rawDatabase.map { sqliteMessage($0) } ?? "sqlite3_open_v2 failed: \(openResult)"
            if let rawDatabase {
                sqlite3_close(rawDatabase)
            }
            throw TodayWidgetCompletionError.storeOpenFailed(message)
        }

        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 2_500)
        try operation(database)
    }

    private struct TaskRecord {
        let primaryKey: Int64
        let hasRepeatRule: Bool
    }

    private nonisolated func completeInTransaction(
        taskID: UUID,
        sharedContext: TodayWidgetSharedContext,
        referenceDate: Date,
        database: OpaquePointer
    ) throws {
        guard let record = try fetchTaskRecord(
            taskID: taskID,
            spaceID: sharedContext.spaceID,
            database: database
        ) else {
            throw TodayWidgetCompletionError.taskNotFound
        }

        let completedAt = Date.now
        if record.hasRepeatRule {
            try upsertOccurrenceCompletion(
                itemID: taskID,
                referenceDate: referenceDate,
                completedAt: completedAt,
                database: database
            )
            try markRepeatingTaskTouched(
                recordPrimaryKey: record.primaryKey,
                actorID: sharedContext.actorID,
                updatedAt: completedAt,
                database: database
            )
        } else {
            try markSingleTaskCompleted(
                recordPrimaryKey: record.primaryKey,
                actorID: sharedContext.actorID,
                completedAt: completedAt,
                database: database
            )
        }

        try upsertSyncChange(
            taskID: taskID,
            spaceID: sharedContext.spaceID,
            changedAt: completedAt,
            database: database
        )
    }

    private nonisolated func fetchTaskRecord(
        taskID: UUID,
        spaceID: UUID,
        database: OpaquePointer
    ) throws -> TaskRecord? {
        let sql = """
        SELECT Z_PK, ZREPEATRULEDATA
        FROM ZPERSISTENTITEM
        WHERE ZID = ?
          AND ZSPACEID = ?
          AND COALESCE(ZISARCHIVED, 0) = 0
          AND COALESCE(ZISLOCALLYDELETED, 0) = 0
        LIMIT 1
        """

        return try withStatement(sql, database: database) { statement in
            bind(uuid: taskID, at: 1, statement: statement)
            bind(uuid: spaceID, at: 2, statement: statement)

            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE { return nil }
                throw sqliteFailure(database)
            }

            return TaskRecord(
                primaryKey: sqlite3_column_int64(statement, 0),
                hasRepeatRule: sqlite3_column_type(statement, 1) != SQLITE_NULL
            )
        }
    }

    private nonisolated func markSingleTaskCompleted(
        recordPrimaryKey: Int64,
        actorID: UUID,
        completedAt: Date,
        database: OpaquePointer
    ) throws {
        if try tableHasColumn("ZPERSISTENTITEM", columnName: "ZCOMPLETEDBYUSERID", database: database) {
            let sql = """
            UPDATE ZPERSISTENTITEM
            SET Z_OPT = COALESCE(Z_OPT, 0) + 1,
                ZASSIGNMENTSTATERAWVALUE = ?,
                ZSTATUSRAWVALUE = ?,
                ZCOMPLETEDAT = ?,
                ZLASTACTIONBYUSERID = ?,
                ZLASTACTIONAT = ?,
                ZCOMPLETEDBYUSERID = ?,
                ZISARCHIVED = 0,
                ZARCHIVEDAT = NULL,
                ZUPDATEDAT = ?
            WHERE Z_PK = ?
            """

            try withStatement(sql, database: database) { statement in
                bind(text: "completed", at: 1, statement: statement)
                bind(text: "completed", at: 2, statement: statement)
                bind(date: completedAt, at: 3, statement: statement)
                bind(uuid: actorID, at: 4, statement: statement)
                bind(date: completedAt, at: 5, statement: statement)
                bind(uuid: actorID, at: 6, statement: statement)
                bind(date: completedAt, at: 7, statement: statement)
                sqlite3_bind_int64(statement, 8, recordPrimaryKey)
                try stepDone(statement, database: database)
            }
        } else {
            let sql = """
            UPDATE ZPERSISTENTITEM
            SET Z_OPT = COALESCE(Z_OPT, 0) + 1,
                ZASSIGNMENTSTATERAWVALUE = ?,
                ZSTATUSRAWVALUE = ?,
                ZCOMPLETEDAT = ?,
                ZLASTACTIONBYUSERID = ?,
                ZLASTACTIONAT = ?,
                ZISARCHIVED = 0,
                ZARCHIVEDAT = NULL,
                ZUPDATEDAT = ?
            WHERE Z_PK = ?
            """

            try withStatement(sql, database: database) { statement in
                bind(text: "completed", at: 1, statement: statement)
                bind(text: "completed", at: 2, statement: statement)
                bind(date: completedAt, at: 3, statement: statement)
                bind(uuid: actorID, at: 4, statement: statement)
                bind(date: completedAt, at: 5, statement: statement)
                bind(date: completedAt, at: 6, statement: statement)
                sqlite3_bind_int64(statement, 7, recordPrimaryKey)
                try stepDone(statement, database: database)
            }
        }

        guard sqlite3_changes(database) == 1 else {
            throw TodayWidgetCompletionError.taskNotFound
        }
    }

    private nonisolated func markRepeatingTaskTouched(
        recordPrimaryKey: Int64,
        actorID: UUID,
        updatedAt: Date,
        database: OpaquePointer
    ) throws {
        if try tableHasColumn("ZPERSISTENTITEM", columnName: "ZCOMPLETEDBYUSERID", database: database) {
            let sql = """
            UPDATE ZPERSISTENTITEM
            SET Z_OPT = COALESCE(Z_OPT, 0) + 1,
                ZCOMPLETEDAT = NULL,
                ZLASTACTIONBYUSERID = ?,
                ZLASTACTIONAT = ?,
                ZCOMPLETEDBYUSERID = ?,
                ZISARCHIVED = 0,
                ZARCHIVEDAT = NULL,
                ZUPDATEDAT = ?
            WHERE Z_PK = ?
            """

            try withStatement(sql, database: database) { statement in
                bind(uuid: actorID, at: 1, statement: statement)
                bind(date: updatedAt, at: 2, statement: statement)
                bind(uuid: actorID, at: 3, statement: statement)
                bind(date: updatedAt, at: 4, statement: statement)
                sqlite3_bind_int64(statement, 5, recordPrimaryKey)
                try stepDone(statement, database: database)
            }
        } else {
            let sql = """
            UPDATE ZPERSISTENTITEM
            SET Z_OPT = COALESCE(Z_OPT, 0) + 1,
                ZCOMPLETEDAT = NULL,
                ZLASTACTIONBYUSERID = ?,
                ZLASTACTIONAT = ?,
                ZISARCHIVED = 0,
                ZARCHIVEDAT = NULL,
                ZUPDATEDAT = ?
            WHERE Z_PK = ?
            """

            try withStatement(sql, database: database) { statement in
                bind(uuid: actorID, at: 1, statement: statement)
                bind(date: updatedAt, at: 2, statement: statement)
                bind(date: updatedAt, at: 3, statement: statement)
                sqlite3_bind_int64(statement, 4, recordPrimaryKey)
                try stepDone(statement, database: database)
            }
        }

        guard sqlite3_changes(database) == 1 else {
            throw TodayWidgetCompletionError.taskNotFound
        }
    }

    private nonisolated func upsertOccurrenceCompletion(
        itemID: UUID,
        referenceDate: Date,
        completedAt: Date,
        database: OpaquePointer
    ) throws {
        let occurrenceDate = calendar.startOfDay(for: referenceDate)
        if let existingPrimaryKey = try fetchOccurrenceCompletionPrimaryKey(
            itemID: itemID,
            occurrenceDate: occurrenceDate,
            database: database
        ) {
            let sql = """
            UPDATE ZPERSISTENTITEMOCCURRENCECOMPLETION
            SET Z_OPT = COALESCE(Z_OPT, 0) + 1,
                ZCOMPLETEDAT = ?,
                ZUPDATEDAT = ?
            WHERE Z_PK = ?
            """

            try withStatement(sql, database: database) { statement in
                bind(date: completedAt, at: 1, statement: statement)
                bind(date: completedAt, at: 2, statement: statement)
                sqlite3_bind_int64(statement, 3, existingPrimaryKey)
                try stepDone(statement, database: database)
            }
            return
        }

        let primaryKey = try nextPrimaryKey(
            entityName: "PersistentItemOccurrenceCompletion",
            database: database
        )
        let sql = """
        INSERT INTO ZPERSISTENTITEMOCCURRENCECOMPLETION
        (Z_PK, Z_ENT, Z_OPT, ZCOMPLETEDAT, ZCREATEDAT, ZOCCURRENCEDATE, ZUPDATEDAT, ZID, ZITEMID)
        VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?)
        """

        try withStatement(sql, database: database) { statement in
            sqlite3_bind_int64(statement, 1, primaryKey.value)
            sqlite3_bind_int64(statement, 2, Int64(primaryKey.entityID))
            bind(date: completedAt, at: 3, statement: statement)
            bind(date: completedAt, at: 4, statement: statement)
            bind(date: occurrenceDate, at: 5, statement: statement)
            bind(date: completedAt, at: 6, statement: statement)
            bind(uuid: UUID(), at: 7, statement: statement)
            bind(uuid: itemID, at: 8, statement: statement)
            try stepDone(statement, database: database)
        }
    }

    private nonisolated func fetchOccurrenceCompletionPrimaryKey(
        itemID: UUID,
        occurrenceDate: Date,
        database: OpaquePointer
    ) throws -> Int64? {
        let sql = """
        SELECT Z_PK
        FROM ZPERSISTENTITEMOCCURRENCECOMPLETION
        WHERE ZITEMID = ?
          AND ZOCCURRENCEDATE >= ?
          AND ZOCCURRENCEDATE < ?
        LIMIT 1
        """
        let start = occurrenceDate.timeIntervalSinceReferenceDate - 0.5
        let end = occurrenceDate.timeIntervalSinceReferenceDate + 0.5

        return try withStatement(sql, database: database) { statement in
            bind(uuid: itemID, at: 1, statement: statement)
            sqlite3_bind_double(statement, 2, start)
            sqlite3_bind_double(statement, 3, end)

            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE { return nil }
                throw sqliteFailure(database)
            }
            return sqlite3_column_int64(statement, 0)
        }
    }

    private nonisolated func upsertSyncChange(
        taskID: UUID,
        spaceID: UUID,
        changedAt: Date,
        database: OpaquePointer
    ) throws {
        if let existingPrimaryKey = try fetchSyncChangePrimaryKey(taskID: taskID, database: database) {
            let sql = """
            UPDATE ZPERSISTENTSYNCCHANGE
            SET Z_OPT = COALESCE(Z_OPT, 0) + 1,
                ZOPERATIONRAWVALUE = ?,
                ZSPACEID = ?,
                ZCHANGEDAT = ?,
                ZLIFECYCLESTATERAWVALUE = ?,
                ZLASTATTEMPTEDAT = NULL,
                ZCONFIRMEDAT = NULL,
                ZLASTERROR = NULL
            WHERE Z_PK = ?
            """

            try withStatement(sql, database: database) { statement in
                bind(text: "complete", at: 1, statement: statement)
                bind(uuid: spaceID, at: 2, statement: statement)
                bind(date: changedAt, at: 3, statement: statement)
                bind(text: "pending", at: 4, statement: statement)
                sqlite3_bind_int64(statement, 5, existingPrimaryKey)
                try stepDone(statement, database: database)
            }
            return
        }

        let primaryKey = try nextPrimaryKey(entityName: "PersistentSyncChange", database: database)
        let sql = """
        INSERT INTO ZPERSISTENTSYNCCHANGE
        (Z_PK, Z_ENT, Z_OPT, ZCHANGEDAT, ZENTITYKINDRAWVALUE, ZLIFECYCLESTATERAWVALUE, ZOPERATIONRAWVALUE, ZID, ZRECORDID, ZSPACEID)
        VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
        """

        try withStatement(sql, database: database) { statement in
            sqlite3_bind_int64(statement, 1, primaryKey.value)
            sqlite3_bind_int64(statement, 2, Int64(primaryKey.entityID))
            bind(date: changedAt, at: 3, statement: statement)
            bind(text: "task", at: 4, statement: statement)
            bind(text: "pending", at: 5, statement: statement)
            bind(text: "complete", at: 6, statement: statement)
            bind(uuid: UUID(), at: 7, statement: statement)
            bind(uuid: taskID, at: 8, statement: statement)
            bind(uuid: spaceID, at: 9, statement: statement)
            try stepDone(statement, database: database)
        }
    }

    private nonisolated func fetchSyncChangePrimaryKey(
        taskID: UUID,
        database: OpaquePointer
    ) throws -> Int64? {
        let sql = """
        SELECT Z_PK
        FROM ZPERSISTENTSYNCCHANGE
        WHERE ZRECORDID = ?
          AND ZENTITYKINDRAWVALUE = ?
        LIMIT 1
        """

        return try withStatement(sql, database: database) { statement in
            bind(uuid: taskID, at: 1, statement: statement)
            bind(text: "task", at: 2, statement: statement)

            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE { return nil }
                throw sqliteFailure(database)
            }
            return sqlite3_column_int64(statement, 0)
        }
    }

    private struct PrimaryKey {
        let entityID: Int32
        let value: Int64
    }

    private nonisolated func nextPrimaryKey(
        entityName: String,
        database: OpaquePointer
    ) throws -> PrimaryKey {
        let fetchSQL = "SELECT Z_ENT, Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = ? LIMIT 1"
        let current: PrimaryKey? = try withStatement(fetchSQL, database: database) { statement in
            bind(text: entityName, at: 1, statement: statement)

            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE { return nil }
                throw sqliteFailure(database)
            }
            return PrimaryKey(
                entityID: sqlite3_column_int(statement, 0),
                value: sqlite3_column_int64(statement, 1)
            )
        }

        guard let current else {
            throw TodayWidgetCompletionError.schemaMismatch("Missing Z_PRIMARYKEY row for \(entityName)")
        }

        let next = current.value + 1
        let updateSQL = "UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = ?"
        try withStatement(updateSQL, database: database) { statement in
            sqlite3_bind_int64(statement, 1, next)
            bind(text: entityName, at: 2, statement: statement)
            try stepDone(statement, database: database)
        }

        return PrimaryKey(entityID: current.entityID, value: next)
    }

    private nonisolated func execute(_ sql: String, database: OpaquePointer) throws {
        try withStatement(sql, database: database) { statement in
            try stepDone(statement, database: database)
        }
    }

    private nonisolated func withStatement<T>(
        _ sql: String,
        database: OpaquePointer,
        operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw sqliteFailure(database)
        }

        defer { sqlite3_finalize(statement) }
        return try operation(statement)
    }

    private nonisolated func tableHasColumn(
        _ tableName: String,
        columnName: String,
        database: OpaquePointer
    ) throws -> Bool {
        let sql = "PRAGMA table_info(\(tableName))"
        return try withStatement(sql, database: database) { statement in
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return false }
                guard result == SQLITE_ROW else { throw sqliteFailure(database) }
                if columnText(statement, 1) == columnName {
                    return true
                }
            }
        }
    }

    private nonisolated func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw sqliteFailure(database)
        }
    }

    private nonisolated func sqliteFailure(_ database: OpaquePointer) -> TodayWidgetCompletionError {
        .storeWriteFailed(sqliteMessage(database))
    }

    private nonisolated func sqliteMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error" }
        return String(cString: message)
    }

    private nonisolated func bind(uuid: UUID, at index: Int32, statement: OpaquePointer) {
        bind(data: uuidData(uuid), at: index, statement: statement)
    }

    private nonisolated func bind(data: Data, at index: Int32, statement: OpaquePointer) {
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransientDestructor)
        }
    }

    private nonisolated func bind(text: String, at index: Int32, statement: OpaquePointer) {
        _ = text.withCString { value in
            sqlite3_bind_text(statement, index, value, -1, sqliteTransientDestructor)
        }
    }

    private nonisolated func bind(date: Date, at index: Int32, statement: OpaquePointer) {
        sqlite3_bind_double(statement, index, date.timeIntervalSinceReferenceDate)
    }

    private nonisolated func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private nonisolated func uuidData(_ uuid: UUID) -> Data {
        var value = uuid.uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private nonisolated var sqliteTransientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
