import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var activeComposer: ComposerRoute?
    var isProjectLayerPresented = false
    var isProfilePresented = false
}
