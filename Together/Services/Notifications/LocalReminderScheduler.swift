import Foundation

actor LocalReminderScheduler: ReminderSchedulerProtocol {
    private let notificationService: NotificationServiceProtocol
    private let calendar: Calendar
    private let searchWindowDays = 730

    init(
        notificationService: NotificationServiceProtocol,
        calendar: Calendar = .current
    ) {
        self.notificationService = notificationService
        self.calendar = calendar
    }

    func syncTaskReminder(for item: Item) async {
        if let notification = makeTaskNotification(for: item) {
            try? await notificationService.schedule([notification])
        } else {
            await notificationService.cancel([AppNotification.identifier(for: .item, targetID: item.id)])
        }
    }

    func removeTaskReminder(for itemID: UUID) async {
        await notificationService.cancel([AppNotification.identifier(for: .item, targetID: itemID)])
    }

    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async {
        let notification = AppNotification(
            id: UUID(),
            spaceID: nil,
            targetID: itemID,
            targetType: .item,
            channel: .localNotification,
            status: .scheduled,
            title: title,
            body: body,
            scheduledAt: .now.addingTimeInterval(delay),
            deliveredAt: nil
        )

        try? await notificationService.schedule([notification])
    }

    func syncProjectReminder(for project: Project) async {
        if let notification = makeProjectNotification(for: project) {
            try? await notificationService.schedule([notification])
        } else {
            await notificationService.cancel([AppNotification.identifier(for: .project, targetID: project.id)])
        }
    }

    func removeProjectReminder(for projectID: UUID) async {
        await notificationService.cancel([AppNotification.identifier(for: .project, targetID: projectID)])
    }

    func resync(tasks: [Item], projects: [Project]) async {
        let taskNotifications = tasks.compactMap(makeTaskNotification(for:))
        let projectNotifications = projects.compactMap(makeProjectNotification(for:))

        try? await notificationService.schedule(taskNotifications + projectNotifications)

        let desiredIdentifiers = Set((taskNotifications + projectNotifications).map(\.identifier))
        let allIdentifiers = Set(
            tasks.map { AppNotification.identifier(for: .item, targetID: $0.id) }
            + projects.map { AppNotification.identifier(for: .project, targetID: $0.id) }
        )
        let staleIdentifiers = Array(allIdentifiers.subtracting(desiredIdentifiers))
        await notificationService.cancel(staleIdentifiers)
    }

    private func makeTaskNotification(for item: Item) -> AppNotification? {
        guard item.isArchived == false else { return nil }
        guard item.repeatRule != nil || item.status != .completed else { return nil }
        guard let scheduledAt = nextReminderDate(for: item, now: .now) else { return nil }

        return AppNotification(
            id: UUID(),
            spaceID: item.spaceID,
            targetID: item.id,
            targetType: .item,
            channel: .localNotification,
            status: .scheduled,
            title: item.title,
            body: taskBody(for: item, scheduledAt: scheduledAt),
            scheduledAt: scheduledAt,
            deliveredAt: nil
        )
    }

    private func makeProjectNotification(for project: Project) -> AppNotification? {
        guard project.status != .archived, project.status != .completed else { return nil }
        guard
            let remindAt = project.remindAt,
            let scheduledAt = normalizedScheduledDate(remindAt, now: .now)
        else {
            return nil
        }

        return AppNotification(
            id: UUID(),
            spaceID: project.spaceID,
            targetID: project.id,
            targetType: .project,
            channel: .localNotification,
            status: .scheduled,
            title: project.name,
            body: projectBody(for: project),
            scheduledAt: scheduledAt,
            deliveredAt: nil
        )
    }

    private func nextReminderDate(for item: Item, now: Date) -> Date? {
        guard let remindAt = item.remindAt else { return nil }

        if item.repeatRule == nil {
            return normalizedScheduledDate(remindAt, now: now)
        }

        guard let dueAt = item.dueAt, let repeatRule = item.repeatRule else { return nil }
        let reminderTarget = reminderTargetDate(for: dueAt, hasExplicitTime: item.hasExplicitTime)
        let reminderLead = reminderTarget.timeIntervalSince(remindAt)
        let anchorDate = item.anchorDateForRepeatRule
        let threshold = now.addingTimeInterval(reminderLead)
        let startDay = calendar.startOfDay(for: max(anchorDate, threshold))

        for dayOffset in 0...searchWindowDays {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: startDay) else { continue }
            guard repeatRule.matches(referenceDate: candidateDay, anchorDate: anchorDate, calendar: calendar) else { continue }

            let candidateDueAt = merge(date: candidateDay, timeSource: dueAt)
            let candidateReminderTarget = reminderTargetDate(for: candidateDueAt, hasExplicitTime: item.hasExplicitTime)
            let candidateReminder = candidateReminderTarget.addingTimeInterval(-reminderLead)

            if let normalizedCandidate = normalizedScheduledDate(candidateReminder, now: now) {
                return normalizedCandidate
            }
        }

        return nil
    }

    private func normalizedScheduledDate(_ scheduledAt: Date, now: Date) -> Date? {
        if scheduledAt > now {
            return scheduledAt
        }

        return nil
    }

    private func taskBody(for item: Item, scheduledAt: Date) -> String {
        if let dueAt = item.dueAt {
            if item.hasExplicitTime {
                return "到期时间 \(dueAt.formatted(.dateTime.month().day().hour().minute()))"
            }
            return "截止日期 \(dueAt.formatted(.dateTime.month().day()))"
        }
        if item.repeatRule != nil {
            return "下一次提醒 \(scheduledAt.formatted(.dateTime.month().day().hour().minute()))"
        }
        return "你有一条待办需要处理"
    }

    private func projectBody(for project: Project) -> String {
        if let targetDate = project.targetDate {
            return "截止日期 \(targetDate.formatted(.dateTime.month().day()))"
        }
        return "项目提醒"
    }

    private func merge(date: Date, timeSource: Date) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
        return calendar.date(from: DateComponents(
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute,
            second: timeComponents.second
        )) ?? date
    }

    private func reminderTargetDate(for dueAt: Date, hasExplicitTime: Bool) -> Date {
        guard hasExplicitTime == false else { return dueAt }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
    }
}
