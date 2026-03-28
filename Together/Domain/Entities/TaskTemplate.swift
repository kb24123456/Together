import Foundation

enum TaskTemplateCategory: String, Codable, Sendable {
    case task
    case periodic
}

struct TaskTemplateClockTime: Hashable, Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
    }

    var hour: Int
    var minute: Int

    nonisolated init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    nonisolated init?(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }

    nonisolated func date(on referenceDate: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: referenceDate)
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        )
    }

    nonisolated static func == (lhs: TaskTemplateClockTime, rhs: TaskTemplateClockTime) -> Bool {
        lhs.hour == rhs.hour && lhs.minute == rhs.minute
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
    }
}

struct TaskTemplate: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var spaceID: UUID?
    var title: String
    var notes: String?
    var listID: UUID?
    var projectID: UUID?
    var priority: ItemPriority
    var isPinned: Bool
    var hasExplicitTime: Bool
    var time: TaskTemplateClockTime?
    var reminderOffset: TimeInterval?
    var repeatRule: ItemRepeatRule?
    let createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        spaceID: UUID?,
        title: String,
        notes: String? = nil,
        listID: UUID? = nil,
        projectID: UUID? = nil,
        priority: ItemPriority = .normal,
        isPinned: Bool = false,
        hasExplicitTime: Bool = false,
        time: TaskTemplateClockTime? = nil,
        reminderOffset: TimeInterval? = nil,
        repeatRule: ItemRepeatRule? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.spaceID = spaceID
        self.title = title
        self.notes = notes
        self.listID = listID
        self.projectID = projectID
        self.priority = priority
        self.isPinned = isPinned
        self.hasExplicitTime = hasExplicitTime
        self.time = time
        self.reminderOffset = reminderOffset
        self.repeatRule = repeatRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated init(
        id: UUID = UUID(),
        spaceID: UUID?,
        draft: TaskDraft,
        calendar: Calendar = .current,
        createdAt: Date = .now
    ) {
        let trimmedNotes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTime = draft.hasExplicitTime ? draft.dueAt.flatMap { TaskTemplateClockTime(date: $0, calendar: calendar) } : nil
        let reminderOffset: TimeInterval?

        if let dueAt = draft.dueAt, let remindAt = draft.remindAt {
            let reminderTarget = Self.reminderTargetDate(
                for: dueAt,
                hasExplicitTime: draft.hasExplicitTime,
                calendar: calendar
            )
            reminderOffset = reminderTarget.timeIntervalSince(remindAt)
        } else {
            reminderOffset = nil
        }

        self.init(
            id: id,
            spaceID: spaceID,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes?.isEmpty == true ? nil : trimmedNotes,
            listID: draft.listID,
            projectID: draft.projectID,
            priority: draft.priority,
            isPinned: draft.isPinned,
            hasExplicitTime: draft.hasExplicitTime,
            time: resolvedTime,
            reminderOffset: reminderOffset,
            repeatRule: draft.repeatRule,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    nonisolated var category: TaskTemplateCategory {
        repeatRule == nil ? .task : .periodic
    }

    nonisolated func makeTaskDraft(for referenceDate: Date, calendar: Calendar = .current) -> TaskDraft {
        let anchorDate = calendar.startOfDay(for: referenceDate)
        let dueAt = hasExplicitTime
            ? (time?.date(on: anchorDate, calendar: calendar) ?? anchorDate)
            : anchorDate
        let reminderTarget = Self.reminderTargetDate(
            for: dueAt,
            hasExplicitTime: hasExplicitTime,
            calendar: calendar
        )
        let remindAt = reminderOffset.map { reminderTarget.addingTimeInterval(-$0) }

        return TaskDraft(
            title: title,
            notes: notes,
            listID: listID,
            projectID: projectID,
            dueAt: dueAt,
            hasExplicitTime: hasExplicitTime,
            remindAt: remindAt,
            priority: priority,
            isPinned: isPinned,
            repeatRule: repeatRule
        )
    }

    nonisolated func isSemanticallyEquivalent(to other: TaskTemplate) -> Bool {
        title == other.title
        && notes == other.notes
        && listID == other.listID
        && projectID == other.projectID
        && priority == other.priority
        && isPinned == other.isPinned
        && hasExplicitTime == other.hasExplicitTime
        && time == other.time
        && reminderOffset == other.reminderOffset
        && repeatRule == other.repeatRule
    }

    private nonisolated static func reminderTargetDate(
        for dueAt: Date,
        hasExplicitTime: Bool,
        calendar: Calendar
    ) -> Date {
        guard hasExplicitTime == false else { return dueAt }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
    }
}
