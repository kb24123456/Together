import Foundation

enum BindingEvent {
    case completedTrialSignIn
    case inviteCreated
    case inviteReceived
    case inviteAccepted
    case unbound
    case signedOut
}

enum BindingStateMachine {
    static func nextState(from currentState: BindingState, event: BindingEvent) -> BindingState {
        switch (currentState, event) {
        case (_, .signedOut):
            return .singleTrial
        case (.singleTrial, .completedTrialSignIn):
            return .singleTrial
        case (.singleTrial, .inviteCreated):
            return .invitePending
        case (.singleTrial, .inviteReceived):
            return .inviteReceived
        case (.invitePending, .inviteAccepted), (.inviteReceived, .inviteAccepted):
            return .paired
        case (.paired, .unbound):
            return .unbound
        default:
            return currentState
        }
    }
}
