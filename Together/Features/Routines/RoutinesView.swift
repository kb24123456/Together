import SwiftUI

struct RoutinesView: View {
    @Environment(AppContext.self) private var appContext
    @State private var morphSession = HomeMorphSession()

    private var viewModel: RoutinesViewModel {
        appContext.routinesViewModel
    }

    var body: some View {
        RoutinesListContent(
            viewModel: viewModel,
            morphSession: morphSession,
            isPresented: true,
            contentTopPadding: AppTheme.spacing.xs,
            contentBottomPadding: 120,
            showsCanvasBackground: true
        )
    }
}
