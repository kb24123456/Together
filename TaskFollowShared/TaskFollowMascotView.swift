import SwiftUI

/// Static artwork: the island always uses the light sphere against its black host.
/// Colors mirror MascotPalette without linking the extension to the Rive runtime.
struct TaskFollowMascotView: View {
    let colorScheme: ColorScheme
    var isMuted = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: isMuted
                        ? [Color.gray, Color.gray]
                        : colorScheme == .dark
                        ? [Color(white: 240.0 / 255), Color(white: 213.0 / 255)]
                        : [Color(white: 16.0 / 255), Color(white: 3.0 / 255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            TaskFollowMascotEyes()
                .fill(colorScheme == .dark && !isMuted ? Color(white: 27.0 / 255) : .white)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Frozen upper-right pose (yaw 0.64, pitch 0.60), radius 184.
/// Uses the existing sphere-eye-projection.py and Idle_GazeUpRight eye parameters;
/// these curves preserve surface wrapping and perspective across the shared sizes.
private struct TaskFollowMascotEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 2.6142, y: -93.5576))
        path.addCurve(to: CGPoint(x: 20.1717, y: -81.1579),
                      control1: CGPoint(x: 11.0735, y: -94.6798), control2: CGPoint(x: 18.9291, y: -89.1769))
        path.addCurve(to: CGPoint(x: 27.5317, y: -26.6802),
                      control1: CGPoint(x: 22.8279, y: -64.0175), control2: CGPoint(x: 25.3213, y: -45.5613))
        path.addCurve(to: CGPoint(x: 14.0625, y: -8.6609),
                      control1: CGPoint(x: 28.5658, y: -17.8467), control2: CGPoint(x: 22.5266, y: -9.8126))
        path.addCurve(to: CGPoint(x: -3.2601, y: -22.5005),
                      control1: CGPoint(x: 5.5984, y: -7.5092), control2: CGPoint(x: -2.1497, y: -13.6707))
        path.addCurve(to: CGPoint(x: -10.6089, y: -77.0466),
                      control1: CGPoint(x: -5.6335, y: -41.3737), control2: CGPoint(x: -8.1232, y: -59.8531))
        path.addCurve(to: CGPoint(x: 2.6142, y: -93.5576),
                      control1: CGPoint(x: -11.7718, y: -85.0906), control2: CGPoint(x: -5.8451, y: -92.4353))
        path.closeSubpath()

        path.move(to: CGPoint(x: 84.5052, y: -94.0675))
        path.addCurve(to: CGPoint(x: 100.3243, y: -83.7690),
                      control1: CGPoint(x: 91.5041, y: -95.1154), control2: CGPoint(x: 98.5214, y: -90.4931))
        path.addCurve(to: CGPoint(x: 109.1778, y: -31.7562),
                      control1: CGPoint(x: 104.7034, y: -67.4372), control2: CGPoint(x: 107.6988, y: -49.8394))
        path.addCurve(to: CGPoint(x: 97.1494, y: -16.1379),
                      control1: CGPoint(x: 109.7867, y: -24.3111), control2: CGPoint(x: 104.4460, y: -17.3664))
        path.addCurve(to: CGPoint(x: 82.8508, y: -27.3589),
                      control1: CGPoint(x: 89.8527, y: -14.9094), control2: CGPoint(x: 83.4118, y: -19.8813))
        path.addCurve(to: CGPoint(x: 74.7202, y: -79.8103),
                      control1: CGPoint(x: 81.4884, y: -45.5208), control2: CGPoint(x: 78.7375, y: -63.2671))
        path.addCurve(to: CGPoint(x: 84.5052, y: -94.0675),
                      control1: CGPoint(x: 73.0662, y: -86.6214), control2: CGPoint(x: 77.5064, y: -93.0197))
        path.closeSubpath()

        let scale = min(rect.width, rect.height) / 368
        return path.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale, tx: rect.midX, ty: rect.midY
        ))
    }
}
