import Foundation

struct AuthSession: Hashable, Sendable {
    var state: AuthState
    var user: User?
}

struct BindingContext: Hashable, Sendable {
    var state: BindingState
    var pairSpace: PairSpace?
    var activeInvite: Invite?
}
