import SwiftUI

struct GradientGridBackground: View {
    var showsAmbientParticles = false
    var ambientParticlesEnabled = true
    var ambientParticlesOpacity: CGFloat = 1
    var isParticleMotionSuppressed = false
    var isSurfaceVisible = true

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: AppTheme.colors.background, location: 0),
                    .init(color: AppTheme.colors.background, location: 0.65),
                    .init(color: AppTheme.colors.gradientBottom, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if showsAmbientParticles {
                AmbientParticleBackground(
                    isEnabled: ambientParticlesEnabled,
                    isMotionSuppressed: isParticleMotionSuppressed,
                    isSurfaceVisible: isSurfaceVisible
                )
                .opacity(ambientParticlesOpacity)
            }
        }
        .ignoresSafeArea()
    }
}
