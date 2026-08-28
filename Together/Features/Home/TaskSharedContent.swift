import Foundation

enum TaskSharedElement: Hashable {
    case completion
    case title
    case note
    case progress
    case time
    case reminder
    case urgent
}

struct TaskSharedIdentityContent: Equatable {
    let title: String
    let note: String?
    let completedSubtaskCount: Int
    let totalSubtaskCount: Int
    let timeSummary: String?
    let reminderSummary: String?
    let isUrgent: Bool
    let isCompleted: Bool
    let isMuted: Bool

    var visibleElements: Set<TaskSharedElement> {
        var elements: Set<TaskSharedElement> = [.completion, .title]
        if note != nil { elements.insert(.note) }
        if totalSubtaskCount > 0 { elements.insert(.progress) }
        if timeSummary != nil { elements.insert(.time) }
        if reminderSummary != nil { elements.insert(.reminder) }
        if isUrgent, isCompleted == false { elements.insert(.urgent) }
        return elements
    }

    static func make(
        entry: HomeTimelineEntry,
        title: String? = nil,
        notes: String? = nil
    ) -> TaskSharedIdentityContent {
        let resolvedNote = (notes ?? entry.notes)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let time = entry.timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminder = entry.reminderText.trimmingCharacters(in: .whitespacesAndNewlines)

        return TaskSharedIdentityContent(
            title: title ?? entry.title,
            note: resolvedNote?.isEmpty == false ? resolvedNote : nil,
            completedSubtaskCount: entry.subtaskCompletedCount,
            totalSubtaskCount: entry.subtasks.count,
            timeSummary: time.isEmpty ? nil : time,
            reminderSummary: reminder.isEmpty ? nil : reminder,
            isUrgent: entry.isUrgent,
            isCompleted: entry.isCompleted,
            isMuted: entry.isMuted
        )
    }
}

enum TaskSharedAttributeText {
    static func reminderLead(
        dueAt: Date?,
        hasExplicitTime: Bool,
        remindAt: Date,
        calendar: Calendar
    ) -> String {
        guard let dueAt else { return "已设置" }
        let effectiveDueAt = hasExplicitTime
            ? dueAt
            : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt)
        let seconds = max(0, effectiveDueAt.timeIntervalSince(remindAt))
        let minutes = Int((seconds / 60).rounded())

        if minutes == 0 { return "准时提醒" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440) 天前" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60) 小时前" }
        return "\(minutes) 分钟前"
    }
}
