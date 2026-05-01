import Foundation
import Testing
@testable import Together

@Suite("ImportantDate recurrence options")
struct ImportantDateRecurrenceOptionsTests {
    @Test("birthdays only expose annual recurrence options")
    func birthdaysOnlyExposeAnnualRecurrenceOptions() {
        #expect(ImportantDate.editableRecurrences(for: .birthday(memberUserID: UUID())) == [
            .solarAnnual,
            .lunarAnnual
        ])
    }

    @Test("normalizing a birthday never leaves one-time recurrence")
    func normalizingBirthdayNeverLeavesOneTimeRecurrence() {
        #expect(
            ImportantDate.normalizedRecurrence(.none, for: .birthday(memberUserID: UUID())) == .solarAnnual
        )
    }

    @Test("custom dates can still be one-time")
    func customDatesCanStillBeOneTime() {
        #expect(ImportantDate.editableRecurrences(for: .custom).contains(.none))
        #expect(ImportantDate.normalizedRecurrence(.none, for: .custom) == .none)
    }
}
