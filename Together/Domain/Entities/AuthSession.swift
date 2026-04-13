import Foundation

enum AppMode: String, CaseIterable, Hashable, Sendable {
    case single
    case pair
}

enum WorkspaceSelection: String, CaseIterable, Hashable, Sendable {
    case single
    case pair

    var appMode: AppMode {
        switch self {
        case .single: .single
        case .pair: .pair
        }
    }
}

enum PairBindingState: String, Hashable, Sendable {
    case unpaired
    case invitePending
    case inviteReceived
    case pairMetadataPending
    case pairedReady
    case unbound
}

struct AuthSession: Hashable, Sendable {
    var state: AuthState
    var user: User?
}

struct PairSpaceSummary: Hashable, Sendable {
    var sharedSpace: Space
    var pairSpace: PairSpace
    var partner: User?
}

struct SpaceContext: Hashable, Sendable {
    var singleSpace: Space?
    var pairSpaceSummary: PairSpaceSummary?
    var activeMode: AppMode
    var availableModes: [AppMode]

    var activeSpace: Space? {
        switch activeMode {
        case .single:
            return singleSpace
        case .pair:
            return pairSpaceSummary?.sharedSpace
        }
    }

    var availableSpaces: [Space] {
        [singleSpace, pairSpaceSummary?.sharedSpace].compactMap { $0 }
    }
}

struct PairingContext: Hashable, Sendable {
    var state: BindingState
    var pairSpaceSummary: PairSpaceSummary?
    var activeInvite: Invite?
}
