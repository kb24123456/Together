import Testing
import Foundation
@testable import Together

@Suite
struct LegalURLsTests {
    @Test func privacyURLIsHTTPS() {
        #expect(LegalURLs.privacy.scheme == "https")
    }

    @Test func termsURLIsHTTPS() {
        #expect(LegalURLs.terms.scheme == "https")
    }

    @Test func privacyURLHostIsNotExampleDotCom() {
        let host = LegalURLs.privacy.host ?? ""
        #expect(!host.contains("example.com"))
    }

    @Test func termsURLHostIsNotExampleDotCom() {
        let host = LegalURLs.terms.host ?? ""
        #expect(!host.contains("example.com"))
    }

    @Test func bothURLsAreNonEmpty() {
        #expect(!LegalURLs.privacy.absoluteString.isEmpty)
        #expect(!LegalURLs.terms.absoluteString.isEmpty)
    }

    @Test func privacyURLHostIsNotPlaceholder() {
        let host = LegalURLs.privacy.host ?? ""
        #expect(!host.contains("placeholder"))
    }

    @Test func termsURLHostIsNotPlaceholder() {
        let host = LegalURLs.terms.host ?? ""
        #expect(!host.contains("placeholder"))
    }

    @Test func privacyURLPathContainsPrivacyPolicy() {
        #expect(LegalURLs.privacy.path.contains("privacy-policy"))
    }

    @Test func termsURLPathContainsTermsOfService() {
        #expect(LegalURLs.terms.path.contains("terms-of-service"))
    }
}
