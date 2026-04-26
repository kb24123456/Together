#if DEBUG
import Foundation

/// DEBUG-only stub。测试（`@testable import Together`）和 SwiftUI Preview 复用同一份。
///
/// 配置方式（actor，因此 setter 都是 async）:
/// ```
/// let stub = StubPaywallPurchasing()
/// await stub.setNextPurchaseOutcomes([.success(.success)])
/// ```
actor StubPaywallPurchasing: PaywallPurchasingProtocol {

    private var offering: PaywallOffering
    private var loadOfferingsError: Error?
    private var nextPurchaseOutcomes: [Result<PaywallPurchaseOutcome, Error>] = []
    private var nextRestoreOutcomes: [Result<PaywallPurchaseOutcome, Error>] = []

    private(set) var loadOfferingsCallCount = 0
    private(set) var purchaseCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var lastPurchasedPackageID: String?

    init(offering: PaywallOffering = StubPaywallPurchasing.sampleOffering) {
        self.offering = offering
    }

    // MARK: - Configuration

    func setOffering(_ o: PaywallOffering) { offering = o }
    func setLoadOfferingsError(_ e: Error?) { loadOfferingsError = e }
    func setNextPurchaseOutcomes(_ outcomes: [Result<PaywallPurchaseOutcome, Error>]) {
        nextPurchaseOutcomes = outcomes
    }
    func setNextRestoreOutcomes(_ outcomes: [Result<PaywallPurchaseOutcome, Error>]) {
        nextRestoreOutcomes = outcomes
    }

    // MARK: - Protocol

    func loadOfferings() async throws -> PaywallOffering {
        loadOfferingsCallCount += 1
        if let err = loadOfferingsError { throw err }
        return offering
    }

    func purchase(packageID: String) async throws -> PaywallPurchaseOutcome {
        purchaseCallCount += 1
        lastPurchasedPackageID = packageID
        guard !nextPurchaseOutcomes.isEmpty else { return .success }
        return try nextPurchaseOutcomes.removeFirst().get()
    }

    func restorePurchases() async throws -> PaywallPurchaseOutcome {
        restoreCallCount += 1
        guard !nextRestoreOutcomes.isEmpty else { return .nothingToRestore }
        return try nextRestoreOutcomes.removeFirst().get()
    }

    // MARK: - Fixture

    static let sampleOffering = PaywallOffering(
        offeringID: "default",
        packages: [
            PaywallPackage(
                id: "monthly", productID: "com.test.monthly",
                localizedTitle: "月度 Pro", localizedPriceString: "¥8",
                price: 8, currencyCode: "CNY",
                subscriptionPeriod: .month(1), introductoryOffer: nil
            ),
            PaywallPackage(
                id: "annual", productID: "com.test.annual",
                localizedTitle: "年度 Pro", localizedPriceString: "¥28",
                price: 28, currencyCode: "CNY",
                subscriptionPeriod: .year(1),
                introductoryOffer: PaywallIntroOffer(period: .day(7), price: 0)
            ),
            PaywallPackage(
                id: "lifetime", productID: "com.test.lifetime",
                localizedTitle: "终身 Pro", localizedPriceString: "¥38",
                price: 38, currencyCode: "CNY",
                subscriptionPeriod: nil, introductoryOffer: nil
            )
        ]
    )
}
#endif
