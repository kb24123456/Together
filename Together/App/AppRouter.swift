import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var activeComposer: ComposerRoute?
    var pendingComposerTitle: String?
    var isProfilePresented = false
}
