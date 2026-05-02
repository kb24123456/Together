import Testing
import Foundation
@testable import Together

@Suite
struct PaywallErrorFromErrorTests {
    // RC ErrorCode rawValue 参考（Sources/Error Handling/ErrorCode.swift）：
    // purchaseCancelledError = 1
    // networkError = 10
    // paymentPendingError = 20
    // offlineConnectionError = 35
    // storeProblemError = 2 等

    @Test func networkErrorIsMappedToNetwork() {
        let err = NSError(domain: "RevenueCat.ErrorCode", code: 10)
        #expect(PaywallError(from: err) == .network)
    }

    @Test func offlineConnectionErrorIsMappedToNetwork() {
        let err = NSError(domain: "RevenueCat.ErrorCode", code: 35)
        #expect(PaywallError(from: err) == .network)
    }

    @Test func nsURLErrorDomainIsMappedToNetwork() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(PaywallError(from: err) == .network)
    }

    @Test func purchaseCancelledMapsToDedicatedCase() {
        // SDK 现代 API 通常通过 outcome 区分 cancel；如果抛到这里也不能展示泛化错误。
        let err = NSError(domain: "RevenueCat.ErrorCode", code: 1)
        #expect(PaywallError(from: err) == .purchaseCancelled)
    }

    @Test func paymentPendingMapsToDedicatedCase() {
        let err = NSError(domain: "RevenueCat.ErrorCode", code: 20)
        #expect(PaywallError(from: err) == .paymentPending)
    }

    @Test func unknownErrorCodeIsMappedToUnknown() {
        let err = NSError(domain: "RevenueCat.ErrorCode", code: 99999)
        #expect(PaywallError(from: err) == .unknown)
    }

    @Test func unrelatedDomainIsMappedToUnknown() {
        let err = NSError(domain: "com.some.other", code: 42)
        #expect(PaywallError(from: err) == .unknown)
    }
}
