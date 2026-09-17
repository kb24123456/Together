import SwiftUI

/// A shallow convex lens around the selection pointer. Scale and projected
/// spacing ease back to the flat ruler with no seam at the lens boundary.
nonisolated enum TaskTimeRulerLens {
    static let maximumScale: CGFloat = 1.24
    static let highlightStrength = 0.18

    static func magnification(distance: CGFloat, pitch: CGFloat) -> CGFloat {
        let radius = max(1, pitch * 5)
        let distance = abs(distance)
        guard distance < radius else { return 1 }
        return 1 + (maximumScale - 1) * (1 + cos(.pi * distance / radius)) / 2
    }
}

/// One mark owns its light history, so the afterglow travels with that mark.
/// Geometry publishes only three regions, never a continuously changing offset.
nonisolated struct TaskTimeRulerLightState {
    enum Position: Equatable {
        case leading, center, trailing

        init(distance: CGFloat, pitch: CGFloat) {
            if distance < -pitch / 2 { self = .leading }
            else if distance < pitch / 2 { self = .center }
            else { self = .trailing }
        }
    }

    private(set) var position: Position?
    private(set) var isTouching = false
    private(set) var pulse = 0

    mutating func setContact(_ touching: Bool) {
        guard isTouching != touching else { return }
        isTouching = touching
        if touching, position == .center { pulse &+= 1 }
    }

    mutating func move(to next: Position) {
        guard position != next else { return }
        let crossedCenter = (position == .leading && next == .trailing)
            || (position == .trailing && next == .leading)
        position = next
        // A fast drag may cross the entire center region between display frames.
        if isTouching, next == .center || crossedCenter { pulse &+= 1 }
    }
}

struct TaskTimeRulerMark: View {
    let ink: Color
    let viewport: Namespace.ID
    let viewportWidth: CGFloat
    let pitch: CGFloat
    let isTouching: Bool
    let resetID: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var light = TaskTimeRulerLightState()

    private var permitsLight: Bool { !reduceMotion && contrast != .increased }

    var body: some View {
        let minimumOpacity = contrast == .increased ? 0.55 : 0.34
        let maximumOpacity = contrast == .increased ? 1.0 : 0.86
        let viewportSpace = viewport
        let width = viewportWidth
        let markPitch = pitch
        let edgeBlur = reduceTransparency || contrast == .increased ? 0.0 : 3.5
        let lightEnabled = permitsLight
        let lightStroke = TaskTimeRulerLightStroke()
        let lensEngaged = isTouching && !reduceMotion

        Capsule()
            .fill(ink)
            .frame(width: 3, height: 34)
            .visualEffect { content, geometry in
                let distance = abs(geometry.frame(in: .named(viewportSpace)).midX - width / 2)
                let proximity = max(0, 1 - distance / max(1, width * 0.42))
                return content.opacity(minimumOpacity + (maximumOpacity - minimumOpacity) * proximity)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: light.pulse) { content, brightness in
                // Magnification carries selection feedback. Keep the ink solid
                // beneath the restrained reflection so the shape stays readable.
                content
                    .overlay {
                        if lightEnabled {
                            lightStroke.opacity(min(1, max(0, brightness)) * TaskTimeRulerLens.highlightStrength)
                        }
                    }
            } keyframes: { _ in
                // Keep the quick onset; extend the crest and the softer afterglow.
                CubicKeyframe(1.0, duration: 0.10)
                CubicKeyframe(0.82, duration: 0.16)
                CubicKeyframe(0.0, duration: 0.44)
            }
            .id(resetID)
            .visualEffect { content, geometry in
                let distance = geometry.frame(in: .named(viewportSpace)).midX - width / 2
                let edge = min(1, max(0, (abs(distance) - width * 0.32) / max(1, width * 0.18)))
                let scale = lensEngaged ? TaskTimeRulerLens.magnification(distance: distance, pitch: markPitch) : 1
                return content
                    .blur(radius: edge * edge * edgeBlur)
                    .scaleEffect(scale)
                    // Project each center through the same local lens. Expanding
                    // the spacing as well as the strokes makes the band feel convex.
                    .offset(x: distance * (scale - 1))
            }
            // Animate contact changes only. Scrolling itself maps straight to the
            // continuous curve, without publishing offsets or animating target layout.
            .animation(reduceMotion ? nil : .easeInOut(duration: lensEngaged ? 0.16 : 0.24), value: lensEngaged)
            .onGeometryChange(for: TaskTimeRulerLightState.Position.self) { geometry in
                TaskTimeRulerLightState.Position(
                    distance: geometry.frame(in: .named(viewportSpace)).midX - width / 2,
                    pitch: markPitch
                )
            } action: { position in
                light.move(to: position)
            }
            .onChange(of: isTouching && permitsLight, initial: true) { _, touching in
                light.setContact(touching)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A restrained, full-width reflection over the solid mark; no rim or glow layer.
struct TaskTimeRulerLightStroke: View {
    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 3, height: 34)
    }
}
