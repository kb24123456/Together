import Foundation
import Testing
@testable import Together

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Suite("Anniversary Widget Snapshot Builder")
struct AnniversaryWidgetSnapshotBuilderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("builds paired anniversary snapshot from anchor date")
    func buildsPairedAnniversarySnapshot() {
        let startDate = calendar.date(from: DateComponents(year: 2024, month: 12, day: 1))!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        let spaceID = UUID()
        let currentUser = user(displayName: "虎皮小猪", symbol: "person.crop.circle.fill")
        let partner = user(displayName: "伴侣", symbol: "heart.circle.fill")
        let event = ImportantDate(
            id: UUID(),
            spaceID: spaceID,
            creatorID: currentUser.id,
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: startDate,
            recurrence: .none,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: "heart.fill",
            presetHolidayID: nil,
            showsElapsedDays: true,
            updatedAt: referenceDate
        )

        let snapshot = AnniversaryWidgetSnapshotBuilder(calendar: calendar).build(
            currentUser: currentUser,
            partner: partner,
            records: [ImportantDateStoredRecord(event: event, createdAt: startDate)],
            referenceDate: referenceDate
        )

        #expect(snapshot.isPaired)
        #expect(snapshot.title == "在一起")
        #expect(snapshot.startDate == startDate)
        #expect(snapshot.daysTogether == 519)
        #expect(snapshot.startDateText == "2024.12.01")
        #expect(snapshot.startDateLongText == "2024年12月1日")
        #expect(snapshot.countdownDays == 211)
        #expect(snapshot.nextMilestoneDays == 600)
        #expect(snapshot.avatars.map(\.displayName) == ["虎皮小猪", "伴侣"])
    }

    @Test("returns empty snapshot when unpaired")
    func returnsEmptyWhenUnpaired() {
        let snapshot = AnniversaryWidgetSnapshotBuilder(calendar: calendar).build(
            currentUser: user(displayName: "虎皮小猪", symbol: "person.crop.circle.fill"),
            partner: nil,
            records: [],
            referenceDate: .now
        )

        #expect(snapshot.isPaired == false)
        #expect(snapshot.avatars.isEmpty)
    }

    #if canImport(UIKit)
    @Test("downsizes avatar photos for widget snapshots")
    func downsizesAvatarPhotosForWidgetSnapshots() throws {
        let store = LocalUserAvatarMediaStore()
        let currentFileName = "widget-avatar-\(UUID().uuidString)-current.jpg"
        let partnerFileName = "widget-avatar-\(UUID().uuidString)-partner.jpg"

        try store.persistAvatarData(Self.avatarFixtureData(firstColor: .systemOrange, secondColor: .systemPink), fileName: currentFileName)
        try store.persistAvatarData(Self.avatarFixtureData(firstColor: .systemRed, secondColor: .systemYellow), fileName: partnerFileName)
        defer {
            try? store.removeAvatar(named: currentFileName)
            try? store.removeAvatar(named: partnerFileName)
        }

        var currentUser = user(displayName: "虎皮小猪", symbol: "person.crop.circle.fill")
        currentUser.avatarPhotoFileName = currentFileName
        var partner = user(displayName: "伴侣", symbol: "heart.circle.fill")
        partner.avatarPhotoFileName = partnerFileName

        let startDate = calendar.date(from: DateComponents(year: 2020, month: 4, day: 16))!
        let event = ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: currentUser.id,
            kind: .anniversary,
            title: "我们的纪念日",
            dateValue: startDate,
            recurrence: .none,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: "heart.fill",
            presetHolidayID: nil,
            showsElapsedDays: true,
            updatedAt: startDate
        )

        let snapshot = AnniversaryWidgetSnapshotBuilder(calendar: calendar, avatarStore: store).build(
            currentUser: currentUser,
            partner: partner,
            records: [ImportantDateStoredRecord(event: event, createdAt: startDate)],
            referenceDate: startDate
        )

        let avatarData = try #require(snapshot.avatars.first?.imageData)
        let avatarImage = try #require(UIImage(data: avatarData))
        #expect(max(avatarImage.size.width, avatarImage.size.height) <= 320)
        #expect(snapshot.avatars.reduce(0) { $0 + ($1.imageData?.count ?? 0) } <= 180_000)
    }
    #endif

    private func user(displayName: String, symbol: String) -> User {
        User(
            id: UUID(),
            appleUserID: nil,
            displayName: displayName,
            avatarSystemName: symbol,
            createdAt: .now,
            updatedAt: .now,
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: true,
                calendarReminderEnabled: true,
                futureCollaborationInviteEnabled: true,
                taskUrgencyWindowMinutes: 30,
                defaultSnoozeMinutes: 30,
                quickTimePresetMinutes: [5, 30, 60],
                completedTaskAutoArchiveEnabled: true,
                completedTaskAutoArchiveDays: 30
            )
        )
    }

    #if canImport(UIKit)
    private static func avatarFixtureData(firstColor: UIColor, secondColor: UIColor) -> Data {
        let size = CGSize(width: 900, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.95) { context in
            firstColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            secondColor.setFill()
            for index in stride(from: 0, through: 900, by: 36) {
                context.cgContext.fillEllipse(in: CGRect(x: index - 80, y: 900 - index - 80, width: 190, height: 190))
            }
        }
    }
    #endif
}
