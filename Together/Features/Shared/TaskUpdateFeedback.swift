import Foundation

/// A transient description of one confirmed edit, never a task or sync source of truth.
struct TaskUpdateFeedback: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let title: String
    let dueAt: Date?
    let hasExplicitTime: Bool
    let changedFields: [String]
    let isSnooze: Bool
    let followState: Bool?

    private init(
        taskID: UUID, title: String, dueAt: Date? = nil,
        hasExplicitTime: Bool = false, changedFields: [String] = [],
        isSnooze: Bool = false, followState: Bool? = nil
    ) {
        self.id = UUID()
        self.taskID = taskID
        self.title = title
        self.dueAt = dueAt
        self.hasExplicitTime = hasExplicitTime
        self.changedFields = changedFields
        self.isSnooze = isSnooze
        self.followState = followState
    }

    init?(before: Item, after: Item, isSnooze: Bool = false, calendar: Calendar = .current) {
        guard before.id == after.id,
              before.repeatRule == nil, after.repeatRule == nil,
              before.status != .completed, after.status != .completed,
              before.completedAt == nil, after.completedAt == nil,
              !before.isDraft, !after.isDraft, !before.isArchived, !after.isArchived else { return nil }

        var fields: [String] = []
        if before.dueAt.map({ calendar.startOfDay(for: $0) }) != after.dueAt.map({ calendar.startOfDay(for: $0) }) {
            fields.append("日期")
        }
        if before.hasExplicitTime != after.hasExplicitTime
            || (after.hasExplicitTime && before.dueAt.map({ calendar.dateComponents([.hour, .minute], from: $0) })
                != after.dueAt.map({ calendar.dateComponents([.hour, .minute], from: $0) })) {
            fields.append("时间")
        }
        // Moving a date/time also moves its relative reminder; that is one schedule edit.
        let previousLead = before.remindAt.flatMap { reminder in before.dueAt.map { $0.timeIntervalSince(reminder) } }
        let nextLead = after.remindAt.flatMap { reminder in after.dueAt.map { $0.timeIntervalSince(reminder) } }
        if previousLead != nextLead { fields.append("提醒") }
        if before.isUrgent != after.isUrgent { fields.append("优先级") }
        if before.isFollowed != after.isFollowed { fields.append("关注") }
        if before.title != after.title { fields.append("标题") }
        if (before.notes ?? "") != (after.notes ?? "") { fields.append("备注") }
        let previousSubtasks = TaskDraft(item: before).subtasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let nextSubtasks = TaskDraft(item: after).subtasks.sorted { $0.id.uuidString < $1.id.uuidString }
        if previousSubtasks != nextSubtasks { fields.append("子任务") }
        guard !fields.isEmpty else { return nil }
        self.init(
            taskID: after.id, title: after.title, dueAt: after.dueAt,
            hasExplicitTime: after.hasExplicitTime, changedFields: fields,
            isSnooze: isSnooze,
            followState: fields == ["关注"] ? after.isFollowed : nil
        )
    }

    init?(before: PeriodicTask, after: PeriodicTask, isSnooze: Bool = false) {
        guard before.id == after.id else { return nil }
        var fields: [String] = []
        if before.cycle != after.cycle { fields.append("周期") }
        if before.reminderRules.compactMap(\.timing) != after.reminderRules.compactMap(\.timing) { fields.append("日期") }
        if before.reminderRules.compactMap(\.hour) != after.reminderRules.compactMap(\.hour)
            || before.reminderRules.compactMap(\.minute) != after.reminderRules.compactMap(\.minute) { fields.append("时间") }
        if before.reminderRules.compactMap(\.reminderLeadMinutes) != after.reminderRules.compactMap(\.reminderLeadMinutes)
            || before.reminderRules.compactMap(\.reminderDelivery) != after.reminderRules.compactMap(\.reminderDelivery) { fields.append("提醒") }
        if before.title != after.title { fields.append("标题") }
        if (before.notes ?? "") != (after.notes ?? "") { fields.append("备注") }
        if isSnooze, before.deferredUntil != after.deferredUntil { fields.append("日期") }
        guard !fields.isEmpty else { return nil }
        self.init(taskID: after.id, title: after.title, dueAt: isSnooze ? after.deferredUntil : nil,
                  changedFields: fields, isSnooze: isSnooze)
    }

    func message(relativeTo now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if dueAt != nil, isSnooze || changedFields.allSatisfy({ $0 == "日期" || $0 == "时间" }) {
            return "\(isSnooze ? "已推迟到" : "已改到")\(destinationText(relativeTo: now, calendar: calendar, locale: locale))"
        }
        if let followState { return followState ? "已关注任务" : "已取消关注" }
        if changedFields.count > 3 { return "已更新 \(changedFields.count) 项内容" }
        return "已更新\(changedFields.joined(separator: "、"))"
    }

    func destinationText(
        relativeTo now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let dueAt else { return "" }
        let targetDay = calendar.startOfDay(for: dueAt)
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        let dayText: String

        if targetDay == today || targetDay == tomorrow {
            // Anchor at the destination so a near-midnight edit still says “tomorrow”,
            // including a 23- or 25-hour day, instead of “in a few minutes”.
            dayText = Date.AnchoredRelativeFormatStyle(
                anchor: targetDay,
                allowedFields: [.day],
                presentation: .named,
                locale: locale,
                calendar: calendar
            ).format(today)
        } else {
            var style = Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            ).month().day()
            if calendar.isDate(dueAt, equalTo: now, toGranularity: .year) == false {
                style = style.year()
            }
            dayText = dueAt.formatted(style)
        }

        guard hasExplicitTime else { return dayText }
        let timeText = dueAt.formatted(Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        ))
        return "\(dayText) · \(timeText)"
    }
}
