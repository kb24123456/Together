import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var activeComposer: ComposerRoute?
}
