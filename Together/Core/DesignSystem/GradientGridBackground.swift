import SwiftUI

struct GradientGridBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: AppTheme.colors.background, location: 0),
                .init(color: AppTheme.colors.background, location: 0.65),
                .init(color: AppTheme.colors.gradientBottom, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
