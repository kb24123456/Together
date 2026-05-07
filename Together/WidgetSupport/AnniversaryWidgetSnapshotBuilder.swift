import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct AnniversaryWidgetSnapshotBuilder: Sendable {
    private let calendar: Calendar
    private let avatarStore: LocalUserAvatarMediaStore

    init(calendar: Calendar = .current, avatarStore: LocalUserAvatarMediaStore = LocalUserAvatarMediaStore()) {
        self.calendar = calendar
        self.avatarStore = avatarStore
    }

    func build(
        currentUser: User?,
        partner: User?,
        records: [ImportantDateStoredRecord],
        referenceDate: Date = .now
    ) -> AnniversaryWidgetSnapshot {
        guard let currentUser, let partner else {
            return .empty
        }

        guard let anniversary = records
            .filter({ ImportantDateCapsulePlanner.isAnchor($0.event) })
            .sorted(by: { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            })
            .first?.event
        else {
            return AnniversaryWidgetSnapshot(
                generatedAt: .now,
                isPaired: true,
                title: "在一起",
                startDate: nil,
                daysTogether: 0,
                startDateText: "",
                startDateLongText: "",
                countdownDays: nil,
                nextMilestoneDays: nil,
                avatars: avatarSnapshots(currentUser: currentUser, partner: partner)
            )
        }

        let daysTogether = daysSinceStart(anniversary.dateValue, referenceDate: referenceDate)
        return AnniversaryWidgetSnapshot(
            generatedAt: .now,
            isPaired: true,
            title: "在一起",
            startDate: anniversary.dateValue,
            daysTogether: daysTogether,
            startDateText: numericDateText(for: anniversary.dateValue),
            startDateLongText: longDateText(for: anniversary.dateValue),
            countdownDays: nextAnnualCountdownDays(from: anniversary.dateValue, referenceDate: referenceDate),
            nextMilestoneDays: nextMilestone(after: daysTogether),
            avatars: avatarSnapshots(currentUser: currentUser, partner: partner)
        )
    }

    private func avatarSnapshots(currentUser: User, partner: User) -> [AnniversaryWidgetAvatarSnapshot] {
        [
            avatarSnapshot(for: currentUser, tintIndex: 0),
            avatarSnapshot(for: partner, tintIndex: 1)
        ]
    }

    private func avatarSnapshot(for user: User, tintIndex: Int) -> AnniversaryWidgetAvatarSnapshot {
        let rawImageData: Data?
        if let fileName = user.avatarCacheFileName {
            rawImageData = try? avatarStore.avatarData(named: fileName)
        } else {
            rawImageData = nil
        }

        return AnniversaryWidgetAvatarSnapshot(
            id: user.id,
            displayName: user.displayName,
            systemName: user.avatarSystemName ?? "person.crop.circle.fill",
            imageData: widgetAvatarData(from: rawImageData),
            tintIndex: tintIndex
        )
    }

    private func widgetAvatarData(from data: Data?) -> Data? {
        #if canImport(UIKit)
        guard let data, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return data
        }

        let side: CGFloat = 320
        let targetSize = CGSize(width: side, height: side)
        let scale = max(side / image.size.width, side / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawOrigin = CGPoint(
            x: (side - drawSize.width) / 2,
            y: (side - drawSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).jpegData(withCompressionQuality: 0.82) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
        #else
        return data
        #endif
    }

    private func daysSinceStart(_ startDate: Date, referenceDate: Date) -> Int {
        let start = calendar.startOfDay(for: startDate)
        let reference = calendar.startOfDay(for: referenceDate)
        return max(0, calendar.dateComponents([.day], from: start, to: reference).day ?? 0)
    }

    private func nextAnnualCountdownDays(from startDate: Date, referenceDate: Date) -> Int? {
        let today = calendar.startOfDay(for: referenceDate)
        let month = calendar.component(.month, from: startDate)
        let day = calendar.component(.day, from: startDate)
        var year = calendar.component(.year, from: today)

        for _ in 0..<5 {
            if let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.month, from: candidate) == month,
               calendar.component(.day, from: candidate) == day {
                let target = calendar.startOfDay(for: candidate)
                if target >= today {
                    return max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
                }
            }
            year += 1
        }

        return nil
    }

    private func nextMilestone(after daysTogether: Int) -> Int {
        max(100, ((daysTogether / 100) + 1) * 100)
    }

    private func numericDateText(for date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year).\(Self.twoDigit(month)).\(Self.twoDigit(day))"
    }

    private func longDateText(for date: Date) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year)年\(month)月\(day)日"
    }

    private static func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
