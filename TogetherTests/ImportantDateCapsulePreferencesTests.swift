import Foundation
import Testing
@testable import Together

@Suite("ImportantDateCapsulePreferences")
struct ImportantDateCapsulePreferencesTests {
    @Test("selected ID string round trip")
    func selectedIDStringRoundTrip() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let storageString = ImportantDateCapsulePreferences.storageString(for: id)
        let decoded = ImportantDateCapsulePreferences.selectedID(from: storageString)

        #expect(storageString == id.uuidString)
        #expect(decoded == id)
    }

    @Test("count modes JSON round trip ignores invalid UUID keys")
    func countModesJSONRoundTrip() {
        let firstID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let secondID = UUID(uuidString: "00000000-1111-2222-3333-444444444444")!
        let encoded = ImportantDateCapsulePreferences.encodeCountModes([
            firstID: .elapsed,
            secondID: .next
        ])

        let invalidKeyJSON = """
        {
          "\(firstID.uuidString)": "elapsed",
          "\(secondID.uuidString)": "next",
          "not-a-uuid": "elapsed"
        }
        """

        #expect(ImportantDateCapsulePreferences.decodeCountModes(encoded) == [
            firstID: .elapsed,
            secondID: .next
        ])
        #expect(ImportantDateCapsulePreferences.decodeCountModes(invalidKeyJSON) == [
            firstID: .elapsed,
            secondID: .next
        ])
    }

    @Test("invalid JSON returns empty")
    func invalidJSONReturnsEmpty() {
        #expect(ImportantDateCapsulePreferences.decodeCountModes("{") == [:])
    }
}
