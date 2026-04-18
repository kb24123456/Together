import SwiftUI

struct AppLaunchView: View {
    @State private var strokeProgress: CGFloat = 0
    @State private var containerScale: CGFloat = 0.94
    @State private var glowScale: CGFloat = 0.3
    @State private var glowOpacity: Double = 0
    @State private var glowBlur: CGFloat = 20
    @State private var brandOpacity: Double = 0
    @State private var brandOffset: CGFloat = 10
    @State private var subtitleOpacity: Double = 0
    @State private var subtitleOffset: CGFloat = 6

    private let containerSize: CGFloat = 120
    private let shortArmTip = CGPoint(x: 0.22, y: 0.58)
    private let cornerPoint = CGPoint(x: 0.44, y: 0.80)
    private let longArmTip = CGPoint(x: 0.86, y: 0.28)

    var body: some View {
        ZStack {
            AppTheme.colors.background
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacing.xl) {
                checkmarkCluster
                brandStack
            }
            .padding(AppTheme.spacing.xl)
        }
        .task {
            StartupTrace.mark("AppLaunchView.visible")
            await runIntroAnimation()
        }
    }

    private var checkmarkCluster: some View {
        ZStack {
            glow(color: AppTheme.colors.coral, at: shortArmTip)
            glow(color: AppTheme.colors.sky, at: longArmTip)

            CheckmarkShape(
                shortArmTip: shortArmTip,
                cornerPoint: cornerPoint,
                longArmTip: longArmTip
            )
            .trim(from: 0, to: strokeProgress)
            .stroke(
                AppTheme.colors.title,
                style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: containerSize, height: containerSize)
        .scaleEffect(containerScale)
    }

    private func glow(color: Color, at relativePoint: CGPoint) -> some View {
        let glowSize: CGFloat = 96
        return Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [color, color.opacity(0)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: glowSize / 2
                )
            )
            .frame(width: glowSize, height: glowSize)
            .blur(radius: glowBlur)
            .opacity(glowOpacity)
            .scaleEffect(glowScale)
            .position(
                x: relativePoint.x * containerSize,
                y: relativePoint.y * containerSize
            )
    }

    private var brandStack: some View {
        VStack(spacing: 6) {
            Text("一二")
                .font(AppTheme.typography.sized(44, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)
                .opacity(brandOpacity)
                .offset(y: brandOffset)

            Text("Together")
                .font(AppTheme.typography.sized(13, weight: .regular))
                .tracking(2)
                .foregroundStyle(AppTheme.colors.body)
                .opacity(subtitleOpacity)
                .offset(y: subtitleOffset)
        }
    }

    private func runIntroAnimation() async {
        withAnimation(.easeOut(duration: 0.55)) {
            strokeProgress = 1
            containerScale = 1.0
        }
        try? await Task.sleep(for: .milliseconds(500))

        withAnimation(.easeOut(duration: 0.40)) {
            glowScale = 1.4
            glowOpacity = 0.55
            glowBlur = 44
        }
        try? await Task.sleep(for: .milliseconds(150))

        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            brandOpacity = 1
            brandOffset = 0
        }
        try? await Task.sleep(for: .milliseconds(200))

        withAnimation(.easeOut(duration: 0.30)) {
            subtitleOpacity = 0.7
            subtitleOffset = 0
        }
    }
}

private struct CheckmarkShape: Shape {
    let shortArmTip: CGPoint
    let cornerPoint: CGPoint
    let longArmTip: CGPoint

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(
                x: shortArmTip.x * rect.width,
                y: shortArmTip.y * rect.height
            ))
            path.addLine(to: CGPoint(
                x: cornerPoint.x * rect.width,
                y: cornerPoint.y * rect.height
            ))
            path.addLine(to: CGPoint(
                x: longArmTip.x * rect.width,
                y: longArmTip.y * rect.height
            ))
        }
    }
}

#Preview {
    AppLaunchView()
}
