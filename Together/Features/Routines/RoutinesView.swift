import SwiftUI

struct RoutinesView: View {
    @Environment(AppContext.self) private var appContext
    @State private var focusModel = HomeFocusPresentationModel()

    private var viewModel: RoutinesViewModel {
        appContext.routinesViewModel
    }

    var body: some View {
        RoutinesListContent(
            viewModel: viewModel,
            focusModel: focusModel,
            isPresented: true,
            contentTopPadding: AppTheme.spacing.xs,
            contentBottomPadding: 120,
            showsCanvasBackground: true
        )
    }
}
