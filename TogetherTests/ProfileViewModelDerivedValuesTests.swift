import Foundation
import Testing
@testable import Together

/// NOTE: `makeBootstrappedContext()` seeds a fully-active pair (PairSpace.status == .active,
/// sharedSpace.createdAt ≈ 115 days ago). Tests reflect this real bootstrapped state rather
/// than an imagined "not paired" baseline — see MockDataFactory.makePairSpace().
@MainActor
@Suite
struct ProfileViewModelDerivedValuesTests {

    @Test func pairDaysCountIsPositiveWhenPaired() {
        let vm = makeViewModel()
        // Bootstrapped session is paired; count must be > 0
        #expect(vm.pairDaysCount > 0)
    }

    @Test func pairDaysLabelIsNonEmptyWhenPaired() {
        let vm = makeViewModel()
        // Paired bootstrap → label should be non-empty ("配对 N 天")
        #expect(!vm.pairDaysLabel.isEmpty)
    }

    @Test func proSubscriptionStatusDefaultsToFree() {
        let vm = makeViewModel()
        #expect(vm.proSubscriptionStatus == .free)
    }

    @Test func proSubtitleTextMatchesStatusSubtitle() {
        let vm = makeViewModel()
        #expect(vm.proSubtitleText == ProSubscriptionStatus.free.subtitleText)
    }

    // MARK: - Helper

    private func makeViewModel() -> ProfileViewModel {
        let context = AppContext.makeBootstrappedContext()
        return context.profileViewModel
    }
}
