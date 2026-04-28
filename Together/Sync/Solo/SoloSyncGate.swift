import Foundation

enum SoloSyncGateDecision: Hashable, Sendable {
    case allowed
    case blockedRequiresPro
}

enum SoloSyncGate {
    static func decision(platform: SoloDevicePlatform, isPro: Bool) -> SoloSyncGateDecision {
        switch platform {
        case .iphone:
            return .allowed
        case .ipad, .mac:
            return isPro ? .allowed : .blockedRequiresPro
        }
    }
}
