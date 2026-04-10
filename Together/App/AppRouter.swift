import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var activeComposer: ComposerRoute?
    var pendingComposerTitle: String?
    var isProfilePresented = false
    var currentSurface: RootSurface = .today

    var isProjectModePresented: Bool {
        currentSurface == .projects
    }

    var isRoutinesModePresented: Bool {
        currentSurface == .routines
    }

    var selectedDockDestination: DockDestination? {
        if isProfilePresented {
            return .profile
        }

        switch currentSurface {
        case .today:
            return nil
        case .calendar:
            return .calendar
        case .routines:
            return .routines
        case .projects:
            return .projects
        }
    }
}
