import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    var activeComposer: ComposerRoute?
    var activeOCRReviewSession: OCRReviewSession?
    var pendingComposerTitle: String?
    var pendingPeriodicCycle: PeriodicCycle?
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
}
