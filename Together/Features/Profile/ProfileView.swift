import SwiftUI

struct ProfileView: View {
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        ZStack {
            AppTheme.colors.background.ignoresSafeArea()

            Text("我")
                .font(AppTheme.typography.textStyle(.title2, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
        }
        .navigationTitle("我")
        .toolbar(.visible, for: .navigationBar)
        .font(AppTheme.typography.body)
    }
}
