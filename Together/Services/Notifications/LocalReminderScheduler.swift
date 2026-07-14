import Foundation

actor LocalReminderScheduler: ReminderSchedulerProtocol {
    private let notificationService: NotificationServiceProtocol
    private let routineAlarmService: RoutineAlarmServiceProtocol
    private let calendar: Calendar
    private let searchWindowDays = 730
    private var taskRemindersEnabled = true

    init(
        notificationService: NotificationServiceProtocol,
        routineAlarmService: RoutineAlarmServiceProtocol = LocalRoutineAlarmService(),
        calendar: Calendar = .current
    ) {
        self.notificationService = notificationService
        self.routineAlarmService = routineAlarmService
        self.calendar = calendar
    }

    func syncTaskReminder(for item: Item) async {
        let notificationID = AppNotification.identifier(for: .item, targetID: item.id)

        guard taskRemindersEnabled else {
            await notificationService.cancel([notificationID])
            await routineAlarmService.cancel(id: item.id)
            return
        }

        guard let notification = makeTaskNotification(for: item) else {
            await notificationService.cancel([notificationID])
            await routineAlarmService.cancel(id: item.id)
            return
        }

        if shouldPreferAlarm(for: item) {
            if await scheduleAlarmIfPossible(for: item, at: notification.scheduledAt) {
                await notificationService.cancel([notificationID])
                return
            }
        } else {
            await routineAlarmService.cancel(id: item.id)
        }

        await routineAlarmService.cancel(id: item.id)
        try? await notificationService.schedule([notification])
    }

    func removeTaskReminder(for itemID: UUID) async {
        await notificationService.cancel([AppNotification.identifier(for: .item, targetID: itemID)])
        await routineAlarmService.cancel(id: itemID)
    }

    func snoozeTaskReminder(itemID: UUID, title: String, body: String, delay: TimeInterval) async {
        guard taskRemindersEnabled else {
            await removeTaskReminder(for: itemID)
            return
        }

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
        guard taskRemindersEnabled else {
            await removeProjectReminder(for: project.id)
            return
        }

        if let notification = makeProjectNotification(for: project) {
            try? await notificationService.schedule([notification])
        } else {
            await notificationService.cancel([AppNotification.identifier(for: .project, targetID: project.id)])
        }
    }

    func removeProjectReminder(for projectID: UUID) async {
        await notificationService.cancel([AppNotification.identifier(for: .project, targetID: projectID)])
    }

    func syncDailySummary(for spaceID: UUID, tasks: [Item]) async {
        guard taskRemindersEnabled else {
            await notificationService.cancel([AppNotification.identifier(for: .dailySummary, targetID: spaceID)])
            return
        }

        if let notification = makeDailySummaryNotification(spaceID: spaceID, tasks: tasks, now: .now) {
            try? await notificationService.schedule([notification])
        } else {
            await notificationService.cancel([AppNotification.identifier(for: .dailySummary, targetID: spaceID)])
        }
    }

    func resync(
        tasks: [Item],
        projects: [Project],
        includeTaskReminders: Bool,
        includeDailySummary: Bool
    ) async {
        taskRemindersEnabled = includeTaskReminders
        let projectNotifications = includeTaskReminders
            ? projects.compactMap(makeProjectNotification(for:))
            : []
        let spaceIDs = Set(tasks.compactMap(\.spaceID) + projects.compactMap(\.spaceID))
        let dailySummaryNotifications = includeDailySummary
            ? spaceIDs.compactMap { spaceID in
                makeDailySummaryNotification(spaceID: spaceID, tasks: tasks, now: .now)
            }
            : []

        try? await notificationService.schedule(projectNotifications + dailySummaryNotifications)

        for task in tasks {
            if includeTaskReminders {
                await syncTaskReminder(for: task)
            } else {
                await removeTaskReminder(for: task.id)
            }
        }

        let desiredIdentifiers = Set((projectNotifications + dailySummaryNotifications).map(\.identifier))
        let allIdentifiers = Set(
            projects.map { AppNotification.identifier(for: .project, targetID: $0.id) }
            + spaceIDs.map { AppNotification.identifier(for: .dailySummary, targetID: $0) }
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

    private func shouldPreferAlarm(for item: Item) -> Bool {
        guard item.repeatRule == nil else { return false }
        guard item.isArchived == false else { return false }
        guard item.status != .completed, item.completedAt == nil else { return false }
        guard item.hasExplicitTime else { return false }
        guard item.dueAt != nil, item.remindAt != nil else { return false }
        return true
    }

    private func scheduleAlarmIfPossible(for item: Item, at date: Date) async -> Bool {
        let status = await alarmAuthorizationStatusForScheduling()
        guard status == .authorized else { return false }

        do {
            try await routineAlarmService.schedule(id: item.id, title: item.title, at: date)
            return true
        } catch {
            return false
        }
    }

    private func alarmAuthorizationStatusForScheduling() async -> RoutineAlarmAuthorizationStatus {
        switch await routineAlarmService.authorizationStatus() {
        case .authorized:
            return .authorized
        case .notDetermined:
            return (try? await routineAlarmService.requestAuthorization()) ?? .denied
        case .denied:
            return .denied
        case .unavailable:
            return .unavailable
        }
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

    private func makeDailySummaryNotification(spaceID: UUID, tasks: [Item], now: Date) -> AppNotification? {
        let incompleteNoDueCount = tasks.filter { item in
            item.spaceID == spaceID
                && item.isArchived == false
                && item.dueAt == nil
                && item.status != .completed
                && item.completedAt == nil
        }.count

        guard incompleteNoDueCount > 0 else { return nil }
        guard let scheduledAt = nextDailySummaryDate(now: now) else { return nil }

        return AppNotification(
            id: UUID(),
            spaceID: spaceID,
            targetID: spaceID,
            targetType: .dailySummary,
            channel: .localNotification,
            status: .scheduled,
            title: "今天还有 \(incompleteNoDueCount) 件事没完成",
            body: "打开 Together 收尾没有到期时间的待办",
            scheduledAt: scheduledAt,
            deliveredAt: nil
        )
    }

    private func nextReminderDate(for item: Item, now: Date) -> Date? {
        let reminderDate = item.remindAt ?? item.dueAt.map {
            reminderTargetDate(for: $0, hasExplicitTime: item.hasExplicitTime)
        }
        guard let reminderDate else { return nil }

        if item.repeatRule == nil {
            return normalizedScheduledDate(reminderDate, now: now)
        }

        guard let dueAt = item.dueAt, let repeatRule = item.repeatRule else { return nil }
        let reminderTarget = reminderTargetDate(for: dueAt, hasExplicitTime: item.hasExplicitTime)
        let reminderLead = reminderTarget.timeIntervalSince(reminderDate)
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

    private func nextDailySummaryDate(now: Date) -> Date? {
        let todaySummary = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        if let todaySummary, todaySummary > now {
            return todaySummary
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return nil
        }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)
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

    // MARK: - Periodic Task Reminders

    func syncPeriodicTaskReminder(for task: PeriodicTask, referenceDate: Date) async {
        let periodKey = PeriodicCycleCalculator.periodKey(for: task.cycle, date: referenceDate, calendar: calendar)
        let notificationID = AppNotification.identifier(for: .periodicTask, targetID: task.id)

        guard task.isActive, !task.isCompleted(forPeriodKey: periodKey) else {
            await notificationService.cancel([notificationID])
            await routineAlarmService.cancel(id: task.id)
            return
        }

        let schedule: PeriodicReminderSchedule?
        if let deferredUntil = task.deferredUntil, deferredUntil > .now {
            schedule = deferredPeriodicReminderSchedule(for: task)
        } else {
            schedule = nextPeriodicReminderSchedule(for: task, referenceDate: referenceDate)
        }
        guard let schedule else {
            await notificationService.cancel([notificationID])
            await routineAlarmService.cancel(id: task.id)
            return
        }

        let notification = makePeriodicTaskNotification(
            for: task,
            periodKey: periodKey,
            scheduledAt: schedule.date
        )

        if schedule.delivery == .alarm {
            await notificationService.cancel([notificationID])
            do {
                try await routineAlarmService.schedule(id: task.id, title: task.title, at: schedule.date)
                return
            } catch {
                // AlarmKit is unavailable before iOS 26 and can also be denied.
                // Preserve the reminder by falling back to the existing notification.
            }
        } else {
            await routineAlarmService.cancel(id: task.id)
        }

        try? await notificationService.schedule([notification])
    }

    func removePeriodicTaskReminder(for taskID: UUID) async {
        await notificationService.cancel([
            AppNotification.identifier(for: .periodicTask, targetID: taskID)
        ])
        await routineAlarmService.cancel(id: taskID)
    }

    func alarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus {
        await routineAlarmService.authorizationStatus()
    }

    func requestAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus {
        try await routineAlarmService.requestAuthorization()
    }

    func periodicAlarmAuthorizationStatus() async -> RoutineAlarmAuthorizationStatus {
        await alarmAuthorizationStatus()
    }

    func requestPeriodicAlarmAuthorization() async throws -> RoutineAlarmAuthorizationStatus {
        try await requestAlarmAuthorization()
    }

    private struct PeriodicReminderSchedule {
        let date: Date
        let delivery: PeriodicReminderDelivery
    }

    private func nextPeriodicReminderSchedule(
        for task: PeriodicTask,
        referenceDate: Date
    ) -> PeriodicReminderSchedule? {
        let now = Date.now
        var earliest: PeriodicReminderSchedule?

        for rule in task.reminderRules {
            guard let triggerDate = PeriodicCycleCalculator.periodicReminderDate(
                rule: rule,
                cycle: task.cycle,
                date: referenceDate,
                calendar: calendar
            ) else { continue }

            if triggerDate > now {
                if earliest == nil || triggerDate < earliest!.date {
                    earliest = PeriodicReminderSchedule(
                        date: triggerDate,
                        delivery: rule.reminderDelivery ?? .notification
                    )
                }
            }
        }

        return earliest
    }

    private func deferredPeriodicReminderSchedule(
        for task: PeriodicTask
    ) -> PeriodicReminderSchedule? {
        let now = Date.now
        guard let deferredUntil = task.deferredUntil, deferredUntil > now else { return nil }

        var earliest: PeriodicReminderSchedule?
        for rule in task.reminderRules {
            guard let leadMinutes = rule.reminderLeadMinutes,
                  let hour = rule.hour,
                  let minute = rule.minute,
                  let targetDate = calendar.date(
                    bySettingHour: hour,
                    minute: minute,
                    second: 0,
                    of: deferredUntil
                  ),
                  let reminderDate = calendar.date(
                    byAdding: .minute,
                    value: -leadMinutes,
                    to: targetDate
                  ) else { continue }

            let scheduledDate = max(reminderDate, deferredUntil)
            guard scheduledDate > now else { continue }
            if earliest == nil || scheduledDate < earliest!.date {
                earliest = PeriodicReminderSchedule(
                    date: scheduledDate,
                    delivery: rule.reminderDelivery ?? .notification
                )
            }
        }
        return earliest
    }

    private func makePeriodicTaskNotification(
        for task: PeriodicTask,
        periodKey: String,
        scheduledAt: Date
    ) -> AppNotification {
        return AppNotification(
            id: UUID(),
            spaceID: task.spaceID,
            targetID: task.id,
            targetType: .periodicTask,
            channel: .localNotification,
            status: .scheduled,
            title: task.title,
            body: "\(task.cycle.currentPeriodPrefix)还未完成",
            scheduledAt: scheduledAt,
            deliveredAt: nil
        )
    }

}
