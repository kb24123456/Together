import Foundation
import Testing
@testable import Together

@Suite("Today Widget Deep Link")
struct TodayWidgetDeepLinkTests {
    @Test("builds today deep link")
    func buildsTodayDeepLink() {
        #expect(DeepLinkConfiguration.todayURL.absoluteString == "together://today")
    }

    @Test("recognizes today deep link")
    func recognizesTodayDeepLink() {
        #expect(DeepLinkConfiguration.isTodayURL(URL(string: "together://today")!))
        #expect(DeepLinkConfiguration.isTodayURL(URL(string: "together://today/")!))
        #expect(!DeepLinkConfiguration.isTodayURL(URL(string: "https://onetwotogether.xyz/invite/abc")!))
    }
}
