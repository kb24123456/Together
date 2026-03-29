import SwiftUI

struct AppLaunchView: View {
    var body: some View {
        ZStack {
            AppTheme.colors.homeBackground
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacing.lg) {
                ProgressView()
                    .controlSize(.large)

                Text("正在准备 Together")
                    .font(AppTheme.typography.body)
                    .foregroundStyle(AppTheme.colors.body)
            }
            .padding(AppTheme.spacing.xl)
        }
        .task {
            StartupTrace.mark("AppLaunchView.visible")
        }
    }
}
