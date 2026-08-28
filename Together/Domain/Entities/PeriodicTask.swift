import Foundation

// MARK: - Periodic Cycle

enum PeriodicCycle: String, CaseIterable, Hashable, Sendable, Codable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly

    static let defaultVisibleCases: [PeriodicCycle] = [.daily, .weekly, .monthly]
    static let optionalVisibleCases: [PeriodicCycle] = [.quarterly, .yearly]

    nonisolated var title: String {
        switch self {
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .quarterly: "每季"
        case .yearly: "每年"
        }
    }

    nonisolated var currentPeriodPrefix: String {
        switch self {
        case .daily: "今天"
        case .weekly: "本周"
        case .monthly: "本月"
        case .quarterly: "本季度"
        case .yearly: "今年"
        }
    }
}

// MARK: - Reminder Rule

enum PeriodicReminderDelivery: String, Codable, Hashable, Sendable {
    case notification
    case alarm
}

enum PeriodicMonthWeekOrdinal: Int, CaseIterable, Codable, Hashable, Sendable {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4
    case last = -1

    nonisolated var title: String {
        switch self {
        case .first: "第一个"
        case .second: "第二个"
        case .third: "第三个"
        case .fourth: "第四个"
        case .last: "最后一个"
        }
    }
}

struct PeriodicReminderRule: Codable, Hashable, Sendable {
    enum Timing: Codable, Hashable, Sendable {
        case dayOfPeriod(Int)
        case businessDayOfPeriod(Int)
        case daysBeforeEnd(Int)
        case weekdayOfMonth(ordinal: PeriodicMonthWeekOrdinal, weekday: Int)
        case lastBusinessDay
    }

    var timing: Timing?
    var hour: Int?
    var minute: Int?
    var reminderLeadMinutes: Int?
    var reminderDelivery: PeriodicReminderDelivery?

    nonisolated init(
        timing: Timing? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        reminderLeadMinutes: Int? = nil,
        reminderDelivery: PeriodicReminderDelivery? = nil
    ) {
        self.timing = timing
        self.hour = hour
        self.minute = minute
        self.reminderLeadMinutes = reminderLeadMinutes
        // Retain the historical payload for older app versions. Current delivery
        // behavior comes from the device-level scheduler preference.
        self.reminderDelivery = reminderLeadMinutes == nil ? nil : (reminderDelivery ?? .notification)
    }

    nonisolated var hasTargetDay: Bool { timing != nil }

    nonisolated var hasTargetTime: Bool { hour != nil && minute != nil }

    nonisolated var hasReminder: Bool { reminderLeadMinutes != nil }

    nonisolated var isEmpty: Bool {
        hasTargetDay == false && hasTargetTime == false && hasReminder == false
    }

    nonisolated func hasCompleteTarget(for cycle: PeriodicCycle) -> Bool {
        hasTargetTime && (cycle == .daily || hasTargetDay)
    }

    private enum CodingKeys: String, CodingKey {
        case timing
        case hour
        case minute
        case reminderLeadMinutes
        case reminderDelivery
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timing = try container.decodeIfPresent(Timing.self, forKey: .timing)
        hour = try container.decodeIfPresent(Int.self, forKey: .hour)
        minute = try container.decodeIfPresent(Int.self, forKey: .minute)

        if container.contains(.reminderLeadMinutes) {
            reminderLeadMinutes = try container.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)
        } else {
            // Legacy rules scheduled a notification automatically whenever a target
            // time existed. Preserve that behavior without changing SwiftData schema.
            reminderLeadMinutes = hour != nil && minute != nil ? 0 : nil
        }

        if container.contains(.reminderDelivery) {
            reminderDelivery = try container.decodeIfPresent(
                PeriodicReminderDelivery.self,
                forKey: .reminderDelivery
            )
        } else {
            // Keep the historical payload value stable. Delivery is now a global,
            // device-level preference and this field is decoded only for compatibility.
            reminderDelivery = reminderLeadMinutes == nil ? nil : .notification
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(timing, forKey: .timing)
        try container.encodeIfPresent(hour, forKey: .hour)
        try container.encodeIfPresent(minute, forKey: .minute)
        // Encode nil explicitly so newly-created target-only rules are not mistaken
        // for legacy auto-reminder rules when decoded later.
        try container.encode(reminderLeadMinutes, forKey: .reminderLeadMinutes)
        try container.encode(reminderDelivery, forKey: .reminderDelivery)
    }
}

// MARK: - Completion Record

struct PeriodicCompletion: Codable, Hashable, Sendable {
    var periodKey: String
    var completedAt: Date
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
    var deferredUntil: Date?
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
        deferredUntil = try container.decodeIfPresent(Date.self, forKey: .deferredUntil)
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
        deferredUntil: Date? = nil,
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
        self.deferredUntil = deferredUntil
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
