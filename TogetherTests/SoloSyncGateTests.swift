import Testing
@testable import Together

@Suite("SoloSyncGate")
struct SoloSyncGateTests {
    @Test("iPhone is allowed without Pro for restore")
    func iPhoneAllowedWithoutPro() {
        let decision = SoloSyncGate.decision(platform: .iphone, isPro: false)
        #expect(decision == .allowed)
    }

    @Test("iPad is blocked without Pro")
    func iPadBlockedWithoutPro() {
        let decision = SoloSyncGate.decision(platform: .ipad, isPro: false)
        #expect(decision == .blockedRequiresPro)
    }

    @Test("Mac is blocked without Pro")
    func macBlockedWithoutPro() {
        let decision = SoloSyncGate.decision(platform: .mac, isPro: false)
        #expect(decision == .blockedRequiresPro)
    }

    @Test("iPad and Mac are allowed with Pro")
    func proAllowsNonPhonePlatforms() {
        #expect(SoloSyncGate.decision(platform: .ipad, isPro: true) == .allowed)
        #expect(SoloSyncGate.decision(platform: .mac, isPro: true) == .allowed)
    }
}
