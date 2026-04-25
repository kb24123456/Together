import Testing
import Foundation
import OSLog
@testable import Together

// MARK: - Test helpers

@MainActor
private final class FinishRecorder {
    var reasons: [PaywallFinishReason] = []
}

@MainActor
private func makeGate(
    rc: StubRCClient = StubRCClient(),
    grants: StubGrantsLoader = StubGrantsLoader(),
    now: Date = Date()
) -> (gate: PremiumGate, rc: StubRCClient, grants: StubGrantsLoader) {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let cache = PremiumStatusCache(defaults: defaults, dateProvider: FixedDateProvider(fixed: now))
    let gate = PremiumGate(
        rcClient: rc,
        grantsLoader: grants,
        cache: cache,
        dateProvider: FixedDateProvider(fixed: now)
    )
    return (gate, rc, grants)
}

@MainActor
private func makeVM(
    gate: PremiumGate,
    stub: StubPaywallPurchasing,
    recorder: FinishRecorder,
    holdDuration: Duration = .zero
) -> PaywallViewModel {
    PaywallViewModel(
        purchasing: stub,
        premiumGate: gate,
        onFinished: { recorder.reasons.append($0) },
        successHoldDuration: holdDuration,
        logger: Logger(subsystem: "test", category: "paywall")
    )
}

/// bootstrap 一个 Pro 活跃的 gate（RC 订阅激活），`isPremium == true`。
@MainActor
private func bootstrapActivePro(gate: PremiumGate, rc: StubRCClient) async {
    await rc.setNextResult(.success(RCEntitlementSnapshot(isProActive: true, proExpirationDate: nil)))
    await gate.bootstrap(userID: UUID())
}

// MARK: - Load

@MainActor
@Suite
struct PaywallViewModelLoadTests {
    @Test func initialStateIsIdle() {
        let (gate, _, _) = makeGate()
        let vm = makeVM(gate: gate, stub: StubPaywallPurchasing(), recorder: FinishRecorder())
        #expect(vm.state == .idle)
        #expect(vm.selectedPackageID == nil)
        #expect(vm.isInFlight == false)
    }

    @Test func loadSuccessMovesToReadyAndAutoSelectsTrialPackage() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        let vm = makeVM(gate: gate, stub: stub, recorder: FinishRecorder())
        await vm.load()

        if case .ready(let offering) = vm.state {
            #expect(offering.packages.count == 3)
        } else {
            Issue.record("expected .ready, got \(vm.state)")
        }
        // sampleOffering 年包带免费试用 → 自动选中
        #expect(vm.selectedPackageID == "annual")
        #expect(vm.cachedOffering != nil)
    }

    @Test func loadFailureMovesToFailed() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setLoadOfferingsError(PaywallError.noOfferings)
        let vm = makeVM(gate: gate, stub: stub, recorder: FinishRecorder())
        await vm.load()

        #expect(vm.state == .failed(.noOfferings))
    }

    @Test func genericErrorIsTranslatedToUnknown() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setLoadOfferingsError(NSError(domain: "other", code: 0))
        let vm = makeVM(gate: gate, stub: stub, recorder: FinishRecorder())
        await vm.load()

        #expect(vm.state == .failed(.unknown))
    }
}

// MARK: - Purchase

@MainActor
@Suite
struct PaywallViewModelPurchaseTests {
    @Test func successWithIsPremiumTrueFinishesPurchased() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()

        #expect(vm.state == .succeeded)
        #expect(rec.reasons == [.purchasedOrRestored])
    }

    @Test func successButIsPremiumFalseYieldsEntitlementNotReady() async {
        let (gate, _, _) = makeGate()
        // 不 bootstrap → isPremium == false
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()

        #expect(vm.state == .failed(.entitlementNotReady))
        #expect(rec.reasons.isEmpty)
    }

    #if DEBUG
    @Test func successWithOverrideStatusYieldsDebugOverrideMasksPro() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        gate.overrideStatus = .free   // override 压住 isPremium
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()

        #expect(vm.state == .failed(.debugOverrideMasksPro))
        #expect(rec.reasons.isEmpty)
    }
    #endif

    @Test func cancelledReturnsToReadyWithoutFinish() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.cancelled)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()

        if case .ready = vm.state {} else {
            Issue.record("expected .ready, got \(vm.state)")
        }
        #expect(rec.reasons.isEmpty)
        // selectedPackageID 保持
        #expect(vm.selectedPackageID == "annual")
    }

    @Test func pendingMovesToPendingApprovalAndFinishesPending() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.pending)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()

        #expect(vm.state == .pendingApproval)
        #expect(rec.reasons == [.pendingApproval])
    }

    @Test func networkErrorFromPaywallErrorIsPreserved() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        // 直接注入 PaywallError，避免依赖 init(from:) 翻译逻辑（由 PaywallErrorTests 独立覆盖）
        await stub.setNextPurchaseOutcomes([.failure(PaywallError.network)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()

        #expect(vm.state == .failed(.network))
    }

    @Test func purchaseSelectedFromNonReadyIsNoOp() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        // 未 load → state = .idle
        await vm.purchaseSelected()

        #expect(vm.state == .idle)
        let purchaseCount = await stub.purchaseCallCount
        #expect(purchaseCount == 0)
    }
}

// MARK: - Restore

@MainActor
@Suite
struct PaywallViewModelRestoreTests {
    @Test func restoreSuccessWithIsPremiumTrueFinishesPurchased() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        let stub = StubPaywallPurchasing()
        await stub.setNextRestoreOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.restore()

        #expect(vm.state == .succeeded)
        #expect(rec.reasons == [.purchasedOrRestored])
    }

    @Test func restoreSuccessDoesNotRequireIsPremiumTrue() async {
        // Restore 信任 RC 的 .success（isActive 校验在生产实现里）；
        // 若 PremiumGate 延迟传播 isPremium 仍 false，也要进 .succeeded
        let (gate, _, _) = makeGate()
        // 不 bootstrap → isPremium == false
        let stub = StubPaywallPurchasing()
        await stub.setNextRestoreOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.restore()

        #expect(vm.state == .succeeded)
        #expect(rec.reasons == [.purchasedOrRestored])
    }

    #if DEBUG
    @Test func restoreSuccessWithOverrideYieldsDebugOverrideMasksPro() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        gate.overrideStatus = .free
        let stub = StubPaywallPurchasing()
        await stub.setNextRestoreOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.restore()

        #expect(vm.state == .failed(.debugOverrideMasksPro))
        #expect(rec.reasons.isEmpty)
    }
    #endif

    @Test func restoreNothingToRestoreMovesToFailed() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setNextRestoreOutcomes([.success(.nothingToRestore)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.restore()

        #expect(vm.state == .failed(.nothingToRestore))
        #expect(rec.reasons.isEmpty)
    }

    @Test func restoreNetworkErrorIsPreserved() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setNextRestoreOutcomes([.failure(PaywallError.network)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.restore()

        #expect(vm.state == .failed(.network))
        #expect(rec.reasons.isEmpty)
    }

    @Test func restoreGenericErrorMappedToUnknown() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setNextRestoreOutcomes([.failure(NSError(domain: "test", code: -1))])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.restore()

        #expect(vm.state == .failed(.unknown))
        #expect(rec.reasons.isEmpty)
    }
}

// MARK: - finishOnce gate / isInFlight / dismissError / requestClose

@MainActor
@Suite
struct PaywallViewModelLifecycleTests {
    @Test func isInFlightCoversPurchasingRestoringSucceeded() async {
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        let stub = StubPaywallPurchasing()
        // 足够长的 hold，让我们能观察 .succeeded 期间 isInFlight 为 true
        await stub.setNextPurchaseOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec, holdDuration: .milliseconds(200))

        await vm.load()
        #expect(vm.isInFlight == false)

        // 启动 purchase，不等 finish
        let task = Task { await vm.purchaseSelected() }
        // 让 state 先进 purchasing
        try? await Task.sleep(for: .milliseconds(20))
        // 此时可能处于 purchasing 或 succeeded（RC 返回后立刻 refresh 再 succeeded）
        #expect(vm.isInFlight == true)

        await task.value
        // hold 结束 → state == .succeeded（仍 isInFlight）且 onFinished 已调
        // 注：测试完后 state 仍为 .succeeded，isInFlight 持续为 true（关 sheet 由外部做）
        #expect(vm.state == .succeeded)
        #expect(vm.isInFlight == true)
    }

    @Test func shortHoldLetsPurchaseFinishBeforeClose() async {
        // hold 极短，purchase 先赢：reason 恒为 .purchasedOrRestored
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec, holdDuration: .zero)

        await vm.load()
        await vm.purchaseSelected()
        vm.requestClose()    // close 到达时 hasFinished 已 true

        #expect(rec.reasons == [.purchasedOrRestored])
    }

    @Test func longHoldLetsCloseWinRace() async {
        // hold 极长，close 先赢：reason 恒为 .userClosed
        let (gate, rc, _) = makeGate()
        await bootstrapActivePro(gate: gate, rc: rc)
        let stub = StubPaywallPurchasing()
        await stub.setNextPurchaseOutcomes([.success(.success)])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec, holdDuration: .seconds(10))

        await vm.load()
        let purchaseTask = Task { await vm.purchaseSelected() }
        try? await Task.sleep(for: .milliseconds(50))  // 等 purchase 进 succeeded 态 & hold
        vm.requestClose()

        purchaseTask.cancel()
        _ = await purchaseTask.value

        // hold 的 Task.sleep 被 cancel 提前返回，holdThenFinish 调 finishOnce 会被 gate 拦
        #expect(rec.reasons == [.userClosed])
    }

    @Test func requestCloseFromReadyFinishesUserClosed() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        vm.requestClose()

        #expect(rec.reasons == [.userClosed])
    }

    @Test func finishOnceGateBlocksSecondCall() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        vm.requestClose()
        vm.requestClose()   // 第二次应被 gate 拦
        vm.requestClose()

        #expect(rec.reasons == [.userClosed])
    }

    @Test func dismissErrorWithCachedOfferingReturnsToReady() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        // 先成功 load，再让 purchase 失败
        await stub.setNextPurchaseOutcomes([.failure(NSError(domain: "test", code: -1))])
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        await vm.purchaseSelected()
        #expect(vm.state == .failed(.unknown))

        vm.dismissError()
        if case .ready = vm.state {} else {
            Issue.record("expected .ready, got \(vm.state)")
        }
    }

    @Test func dismissErrorWithoutCachedOfferingReturnsToIdle() async {
        let (gate, _, _) = makeGate()
        let stub = StubPaywallPurchasing()
        await stub.setLoadOfferingsError(PaywallError.noOfferings)
        let rec = FinishRecorder()
        let vm = makeVM(gate: gate, stub: stub, recorder: rec)

        await vm.load()
        #expect(vm.state == .failed(.noOfferings))

        vm.dismissError()
        #expect(vm.state == .idle)
    }
}
