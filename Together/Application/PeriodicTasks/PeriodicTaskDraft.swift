import Foundation

struct PeriodicTaskDraft: Hashable, Sendable {
    var title: String
    var notes: String?
    var cycle: PeriodicCycle
    var reminderRules: [PeriodicReminderRule]
    var subtasks: [PeriodicSubtask]

    nonisolated init(
        title: String = "",
        notes: String? = nil,
        cycle: PeriodicCycle = .monthly,
        reminderRules: [PeriodicReminderRule] = [],
        subtasks: [PeriodicSubtask] = []
    ) {
        self.title = title
        self.notes = notes
        self.cycle = cycle
        self.reminderRules = reminderRules
        self.subtasks = subtasks
    }

    nonisolated init(task: PeriodicTask) {
        self.init(
            title: task.title,
            notes: task.notes,
            cycle: task.cycle,
            reminderRules: task.reminderRules,
            subtasks: task.subtasks
        )
    }
}
