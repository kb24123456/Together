import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var activeComposer: ComposerRoute?
    var pendingComposerTitle: String?
    var isProfilePresented = false
    var currentSurface: RootSurface = .today

    /// When true, RoutinesListContent auto-selects the first cycle with pending tasks.
    /// Consumed (reset to false) after being read.
    var shouldAutoSelectPendingCycle = false

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
