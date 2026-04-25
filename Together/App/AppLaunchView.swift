import SwiftUI

struct AppLaunchView: View {
    @State private var meshOpacity: Double = 0
    @State private var meshBreathe = false

    var body: some View {
        ZStack {
            AppTheme.colors.background
                .ignoresSafeArea()

            atmosphericMesh
                .opacity(meshOpacity * (meshBreathe ? 0.82 : 1.0))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            BrandLogoStatic()
        }
        .task {
            StartupTrace.mark("AppLaunchView.visible")
            await runIntroAnimation()
        }
    }

    /// 静态多色 MeshGradient + 中等模糊。色彩融合成 atmospheric 弥散感（无独立色块）。
    /// 灵动感来自 opacity 缓慢呼吸（仅 transition 帧重渲，无 60Hz 持续重绘）。
    private var atmosphericMesh: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0),    .init(0.5, 0),    .init(1, 0),
                .init(0, 0.5),  .init(0.5, 0.5),  .init(1, 0.5),
                .init(0, 1),    .init(0.5, 1),    .init(1, 1)
            ],
            colors: meshColors
        )
        .blur(radius: 25)
    }

    private var meshColors: [Color] {
        let bg = AppTheme.colors.background
        let coral = AppTheme.colors.coral.opacity(0.30)
        let sky = AppTheme.colors.sky.opacity(0.30)
        let gold = AppTheme.colors.sun.opacity(0.18)
        let violet = AppTheme.colors.violet.opacity(0.15)

        return [
            bg,    coral, bg,
            sky,   gold,  coral,
            bg,    violet, bg
        ]
    }

    private func runIntroAnimation() async {
        // 1) Mesh atmosphere fade in
        withAnimation(.easeOut(duration: 0.8)) {
            meshOpacity = 1
        }

        // 2) Mesh opacity 缓慢呼吸（4s 一轮）— 灵动感不靠 60Hz 重渲
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(
            .easeInOut(duration: 4.0).repeatForever(autoreverses: true)
        ) {
            meshBreathe = true
        }
    }
}

#Preview {
    AppLaunchView()
}
