import XCTest
@testable import Together

@MainActor
final class PinnedAnniversaryQuotaTests: XCTestCase {

    private func makeEvent(pinned: Bool, anchor: Date) -> ImportantDate {
        ImportantDate(
            id: UUID(),
            spaceID: UUID(),
            creatorID: UUID(),
            kind: .anniversary,
            title: "test",
            dateValue: anchor,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil,
            updatedAt: .now,
            isPinnedToToday: pinned
        )
    }

    func test_pinnedCap_isSix() {
        XCTAssertEqual(ImportantDatesViewModel.pinnedToTodayCap, 6)
    }

    func test_pinnedEvents_filtersAndSortsByAnchor() {
        // Build six events with displayAnchorDate spread across 5..30 days.
        let now = Date()
        let dates = [30, 5, 10, 25, 1, 15].map {
            Calendar.current.date(byAdding: .day, value: -$0 * 365 + 5, to: now)!
        }
        // Mark 4 of them pinned.
        let events = dates.enumerated().map { idx, anchor in
            makeEvent(pinned: idx < 4, anchor: anchor)
        }
        let sortedAnchors = events.prefix(4)
            .map { $0.displayAnchorDate() }
            .sorted()

        XCTAssertEqual(
            ImportantDatesViewModel.pinnedEvents(from: events).map { $0.displayAnchorDate() },
            sortedAnchors
        )
    }

    func test_canPinAnotherToToday_returnsFalseWhenAtCap() {
        let pinnedSix = (0..<6).map { _ in makeEvent(pinned: true, anchor: Date()) }
        XCTAssertFalse(ImportantDatesViewModel.canPinAnotherToToday(events: pinnedSix))
        let pinnedFive = (0..<5).map { _ in makeEvent(pinned: true, anchor: Date()) }
        XCTAssertTrue(ImportantDatesViewModel.canPinAnotherToToday(events: pinnedFive))
    }
}
