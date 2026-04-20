import Foundation
import Testing
@testable import Together

@MainActor
@Suite
struct CompletedHistoryViewModelPairTests {

    @Test func avatarAssetForCurrentUserIDReturnsCurrentUserAsset() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        guard let userID = context.sessionStore.currentUser?.id else {
            Issue.record("Bootstrap must seed a currentUser")
            return
        }
        let expected = context.sessionStore.currentUser?.avatarAsset ?? .system("person.crop.circle.fill")
        #expect(vm.avatarAsset(forUserID: userID) == expected)
    }

    @Test func avatarAssetForUnknownIDFallsBackToGenericPerson() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        let asset = vm.avatarAsset(forUserID: UUID())
        #expect(asset == .system("person.fill"))
    }

    @Test func avatarAssetForNilFallsBackToGenericPerson() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        let asset = vm.avatarAsset(forUserID: nil)
        #expect(asset == .system("person.fill"))
    }

    @Test func displayNameForUnknownIDFallsBack() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        #expect(vm.displayName(forUserID: UUID()) == "未知完成者")
        #expect(vm.displayName(forUserID: nil) == "未知完成者")
    }

    @Test func isPairModeReflectsSessionStore() {
        let context = AppContext.makeBootstrappedContext()
        let vm = context.profileViewModel.makeCompletedHistoryViewModel()
        // Bootstrap seeds a paired mock session
        #expect(vm.isPairMode == true)
    }
}
