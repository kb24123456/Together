import Foundation

enum TaskSnoozeOption: Sendable, Hashable {
    case tomorrow
    case minutes(Int)
    case custom(Date)
}
