import Foundation

struct PeriodicTaskDraft: Hashable, Sendable {
    var title: String
    var notes: String?
    var cycle: PeriodicCycle
    var reminderRules: [PeriodicReminderRule]

    nonisolated init(
        title: String = "",
        notes: String? = nil,
        cycle: PeriodicCycle = .monthly,
        reminderRules: [PeriodicReminderRule] = []
    ) {
        self.title = title
        self.notes = notes
        self.cycle = cycle
        self.reminderRules = reminderRules
    }

    nonisolated init(task: PeriodicTask) {
        self.init(
            title: task.title,
            notes: task.notes,
            cycle: task.cycle,
            reminderRules: task.reminderRules
        )
    }
}
