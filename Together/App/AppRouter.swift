import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    private(set) var activeComposer: ComposerRoute?
    var activeOCRReviewSession: OCRReviewSession?
    private(set) var pendingComposerTitle: String?
    var pendingPeriodicCycle: PeriodicCycle?
    var isProfilePresented = false
    var currentSurface: RootSurface = .today
    private(set) var rootResetRevision = 0
    private(set) var composerRequestRevision: UInt = 0

    /// When true, RoutinesListContent auto-selects the first cycle with pending tasks.
    /// Consumed (reset to false) after being read.
    var shouldAutoSelectPendingCycle = false

    var isRoutinesModePresented: Bool {
        currentSurface == .routines
    }

    func requestComposer(_ route: ComposerRoute, title: String? = nil) {
        pendingComposerTitle = title
        activeComposer = route
        composerRequestRevision &+= 1
    }

    func clearComposerRequest() {
        activeComposer = nil
        pendingComposerTitle = nil
    }

    func resetToToday() {
        clearComposerRequest()
        isProfilePresented = false
        currentSurface = .today
        rootResetRevision += 1
    }
}
