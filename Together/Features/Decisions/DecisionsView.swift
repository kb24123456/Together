import SwiftUI

struct DecisionsView: View {
    @Bindable var viewModel: DecisionsViewModel

    var body: some View {
        ZStack {
            AppTheme.colors.background.ignoresSafeArea()

            Text("决策")
                .font(AppTheme.typography.textStyle(.title2, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
        }
        .navigationTitle("决策")
        .toolbar(.visible, for: .navigationBar)
        .font(AppTheme.typography.body)
    }
}
