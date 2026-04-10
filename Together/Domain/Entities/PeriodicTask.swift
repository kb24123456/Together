import Foundation

// MARK: - Periodic Cycle

enum PeriodicCycle: String, CaseIterable, Hashable, Sendable, Codable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var title: String {
        switch self {
        case .weekly: "每周"
        case .monthly: "每月"
        case .quarterly: "每季度"
        case .yearly: "每年"
        }
    }

    var currentPeriodPrefix: String {
        switch self {
        case .weekly: "本周"
        case .monthly: "本月"
        case .quarterly: "本季度"
        case .yearly: "今年"
        }
    }
}

// MARK: - Reminder Rule

struct PeriodicReminderRule: Codable, Hashable, Sendable {
    enum Timing: Codable, Hashable, Sendable {
        case dayOfPeriod(Int)
        case businessDayOfPeriod(Int)
        case daysBeforeEnd(Int)
    }

    var timing: Timing
    var hour: Int
    var minute: Int

    nonisolated init(timing: Timing, hour: Int = 9, minute: Int = 0) {
        self.timing = timing
        self.hour = hour
        self.minute = minute
    }
}

// MARK: - Completion Record

struct PeriodicCompletion: Codable, Hashable, Sendable {
    var periodKey: String
    var completedAt: Date
}

// MARK: - Subtask

struct PeriodicSubtask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var isCompleted: Bool

    nonisolated init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

// MARK: - Periodic Task Entity

struct PeriodicTask: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var spaceID: UUID?
    let creatorID: UUID
    var title: String
    var notes: String?
    var cycle: PeriodicCycle
    var reminderRules: [PeriodicReminderRule]
    var completions: [PeriodicCompletion]
    var subtasks: [PeriodicSubtask]
    var sortOrder: Double
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        creatorID = try container.decode(UUID.self, forKey: .creatorID)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        cycle = try container.decode(PeriodicCycle.self, forKey: .cycle)
        reminderRules = try container.decode([PeriodicReminderRule].self, forKey: .reminderRules)
        completions = try container.decode([PeriodicCompletion].self, forKey: .completions)
        subtasks = try container.decodeIfPresent([PeriodicSubtask].self, forKey: .subtasks) ?? []
        sortOrder = try container.decode(Double.self, forKey: .sortOrder)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    nonisolated init(
        id: UUID = UUID(),
        spaceID: UUID? = nil,
        creatorID: UUID,
        title: String,
        notes: String? = nil,
        cycle: PeriodicCycle,
        reminderRules: [PeriodicReminderRule] = [],
        completions: [PeriodicCompletion] = [],
        subtasks: [PeriodicSubtask] = [],
        sortOrder: Double = 0,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.spaceID = spaceID
        self.creatorID = creatorID
        self.title = title
        self.notes = notes
        self.cycle = cycle
        self.reminderRules = reminderRules
        self.completions = completions
        self.subtasks = subtasks
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated func isCompleted(forPeriodKey key: String) -> Bool {
        completions.contains { $0.periodKey == key }
    }

    nonisolated func completionDate(forPeriodKey key: String) -> Date? {
        completions.first { $0.periodKey == key }?.completedAt
    }
}
