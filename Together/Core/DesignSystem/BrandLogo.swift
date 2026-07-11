import SwiftUI

enum BrandLogoMetrics {
    static let containerSize: CGFloat = 120
    /// 入场 spring 终态前的初始 scale（弹入 from）。
    static let introInitialScale: CGFloat = 0.85
    /// 呼吸幅度：scale 在 1.0 ↔ peakScale 之间，opacity 在 minOpacity ↔ 1.0 之间。
    static let breathePeakScale: CGFloat = 1.03
    static let breatheMinOpacity: Double = 0.88
    /// 单次呼吸周期。
    static let breatheDuration: Double = 2.4
}

/// 品牌 logo（入场 spring + 持续呼吸）。
/// 直接复用 app icon transparent PNG（已抠白底），保留原设计的 checkmark + 红蓝光晕。
/// splash / 数据恢复页 / 设置页等所有稳态场景共用。
struct BrandLogoStatic: View {
    @State private var hasAppeared = false
    @State private var isBreathing = false

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: BrandLogoMetrics.containerSize, height: BrandLogoMetrics.containerSize)
            .scaleEffect(currentScale)
            .opacity(hasAppeared ? currentOpacity : 0)
            .task {
                await runIntroAnimation()
            }
    }

    private var currentScale: CGFloat {
        guard hasAppeared else { return BrandLogoMetrics.introInitialScale }
        return isBreathing ? BrandLogoMetrics.breathePeakScale : 1.0
    }

    private var currentOpacity: Double {
        isBreathing ? BrandLogoMetrics.breatheMinOpacity : 1.0
    }

    private func runIntroAnimation() async {
        // 1) 弹性入场：scale 0.85 → 1.0 + opacity 0 → 1
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
            hasAppeared = true
        }

        // 2) 等入场弹簧落定再起呼吸（避免叠加抖动）
        try? await Task.sleep(for: .milliseconds(700))

        // 3) 持续呼吸：scale + opacity 同步脉动
        withAnimation(
            .easeInOut(duration: BrandLogoMetrics.breatheDuration)
                .repeatForever(autoreverses: true)
        ) {
            isBreathing = true
        }
    }
}

#Preview {
    BrandLogoStatic()
        .padding(60)
        .background(AppTheme.colors.background)
}
