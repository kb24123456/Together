import Foundation
import UserNotifications
import os

protocol AnniversaryNotificationSchedulerProtocol: Sendable {
    func refresh(spaceID: UUID) async
}

actor AnniversaryNotificationScheduler: AnniversaryNotificationSchedulerProtocol {
    private let repository: ImportantDateRepositoryProtocol
    private let center: UNUserNotificationCenter
    private let partnerDisplayNameProvider: @Sendable () -> String?
    private let myDisplayNameProvider: @Sendable () -> String?
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "AnniversaryScheduler")

    private static let identifierPrefix = "anniversary-"

    init(
        repository: ImportantDateRepositoryProtocol,
        center: UNUserNotificationCenter = .current(),
        partnerDisplayNameProvider: @escaping @Sendable () -> String? = { nil },
        myDisplayNameProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.repository = repository
        self.center = center
        self.partnerDisplayNameProvider = partnerDisplayNameProvider
        self.myDisplayNameProvider = myDisplayNameProvider
    }

    func refresh(spaceID: UUID) async {
        // 1. Check authorization via notificationSettings()
        let settings = await center.notificationSettings()
        let status = settings.authorizationStatus
        guard status == .authorized || status == .provisional else {
            logger.info("not authorized (\(status.rawValue)); skipping refresh")
            return
        }

        // 2. Remove any existing anniversary-prefixed pending
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }.map(\.identifier)
        if !ourIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ourIDs)
        }

        // 3. Fetch events + sort by nextOccurrence
        guard let events = try? await repository.fetchAll(spaceID: spaceID) else { return }
        let now = Date.now
        let upcoming = events
            .compactMap { event -> (ImportantDate, Date)? in
                guard let next = event.nextOccurrence(after: now) else { return nil }
                return (event, next)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(32)

        // 4. Schedule 2 notifications per event (advance + day-of)
        for (event, next) in upcoming {
            if event.notifyDaysBefore > 0,
               let advanceDate = Calendar.current.date(byAdding: .day, value: -event.notifyDaysBefore, to: next),
               let triggerDate = calendarDateWithTime(advanceDate, hour: 9, minute: 0),
               triggerDate > now {
                await schedule(
                    identifier: "\(Self.identifierPrefix)\(event.id)-before",
                    triggerDate: triggerDate,
                    title: advanceTitle(for: event),
                    body: advanceBody(for: event, daysUntil: event.notifyDaysBefore)
                )
            }
            if event.notifyOnDay,
               let triggerDate = calendarDateWithTime(next, hour: 9, minute: 0),
               triggerDate > now {
                await schedule(
                    identifier: "\(Self.identifierPrefix)\(event.id)-day",
                    triggerDate: triggerDate,
                    title: dayOfTitle(for: event),
                    body: dayOfBody(for: event)
                )
            }
        }

        logger.info("scheduled anniversary notifications for \(upcoming.count) events")
    }

    private func calendarDateWithTime(_ date: Date, hour: Int, minute: Int) -> Date? {
        var cal = Calendar.current
        cal.timeZone = .current
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    private func schedule(identifier: String, triggerDate: Date, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            logger.error("schedule add failed id=\(identifier): \(error.localizedDescription)")
        }
    }

    // MARK: - Copy

    private func advanceTitle(for event: ImportantDate) -> String {
        switch event.kind {
        case .birthday: return "💝 生日快到啦"
        case .anniversary: return "💕 纪念日提醒"
        case .holiday: return "✨ \(event.title)快到啦"
        case .custom: return "📌 \(event.title)"
        }
    }

    private func advanceBody(for event: ImportantDate, daysUntil: Int) -> String {
        switch event.kind {
        case .birthday(let memberID):
            let name = isMyself(memberID) ? "你的" : (partnerDisplayNameProvider().map { "\($0) 的" } ?? "伴侣的")
            return "\(name)生日还有 \(daysUntil) 天"
        case .anniversary:
            return "纪念日还有 \(daysUntil) 天"
        case .holiday:
            return "\(event.title) 还有 \(daysUntil) 天"
        case .custom:
            return "\(event.title) 还有 \(daysUntil) 天"
        }
    }

    private func dayOfTitle(for event: ImportantDate) -> String {
        switch event.kind {
        case .birthday(let memberID):
            return isMyself(memberID) ? "🎉 生日快乐！" : "🎂 今天是伴侣生日"
        case .anniversary: return "💕 纪念日快乐"
        case .holiday: return "✨ \(event.title)快乐"
        case .custom: return "📌 今天是\(event.title)"
        }
    }

    private func dayOfBody(for event: ImportantDate) -> String {
        switch event.kind {
        case .birthday(let memberID):
            return isMyself(memberID) ? "祝自己生日快乐 🎂" : "别忘了说声生日快乐 💌"
        case .anniversary:
            let years = Calendar.current.dateComponents([.year], from: event.dateValue, to: .now).year ?? 0
            return years > 0 ? "今天是你们在一起的第 \(years) 周年" : "今天是你们的纪念日"
        case .holiday: return "祝你们节日愉快"
        case .custom: return event.title
        }
    }

    private func isMyself(_ memberID: UUID) -> Bool {
        // Hook for future use; v1 scheduler doesn't know which user is local.
        false
    }
}
