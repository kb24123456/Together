import Foundation

enum DecisionTemplate: String, CaseIterable, Hashable, Sendable {
    case buy
    case eat
    case go

    var title: String {
        switch self {
        case .buy:
            return "买不买"
        case .eat:
            return "吃不吃"
        case .go:
            return "去不去"
        }
    }
}

enum DecisionVoteValue: String, CaseIterable, Hashable, Sendable {
    case agree
    case neutral
    case reject

    func label(for template: DecisionTemplate) -> String {
        switch (template, self) {
        case (.buy, .agree):
            return "想买"
        case (.buy, .neutral):
            return "再看看"
        case (.buy, .reject):
            return "不买"
        case (.eat, .agree):
            return "想吃"
        case (.eat, .neutral):
            return "再想想"
        case (.eat, .reject):
            return "不吃"
        case (.go, .agree):
            return "想去"
        case (.go, .neutral):
            return "再看看"
        case (.go, .reject):
            return "不去"
        }
    }
}

enum DecisionStatus: String, Hashable, Sendable {
    case pendingResponse
    case consensusReached
    case noConsensusYet
    case archived

    var title: String {
        switch self {
        case .pendingResponse:
            return "待表态"
        case .consensusReached:
            return "已达成一致"
        case .noConsensusYet:
            return "暂未达成一致"
        case .archived:
            return "已归档"
        }
    }
}
