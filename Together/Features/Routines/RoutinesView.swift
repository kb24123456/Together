import SwiftUI

struct RoutinesView: View {
    @Environment(AppContext.self) private var appContext

    private var viewModel: RoutinesViewModel {
        appContext.routinesViewModel
    }

    var body: some View {
        RoutinesListContent(
            viewModel: viewModel,
            isPresented: true,
            contentTopPadding: AppTheme.spacing.xs,
            contentBottomPadding: 120,
            showsCanvasBackground: true
        )
    }
}
