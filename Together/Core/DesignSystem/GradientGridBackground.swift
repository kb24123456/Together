import SwiftUI

struct GradientGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private let gridSpacing: CGFloat = 36
    private let gridLineWidth: CGFloat = 0.5

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

            Canvas { context, size in
                let shading = GraphicsContext.Shading.color(AppTheme.colors.gridLine)

                // Vertical lines
                var x: CGFloat = 0
                while x <= size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: shading, lineWidth: gridLineWidth)
                    x += gridSpacing
                }

                // Horizontal lines
                var y: CGFloat = 0
                while y <= size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: shading, lineWidth: gridLineWidth)
                    y += gridSpacing
                }
            }
        }
        .ignoresSafeArea()
    }
}
