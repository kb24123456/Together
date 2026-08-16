import SwiftUI

nonisolated enum TaskEdgeFlowEdge: Equatable, Sendable {
    case none
    case top
    case bottom
}

nonisolated struct TaskEdgeFlowMetrics: Equatable, Sendable {
    let offsetY: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let opacity: Double
    let blurRadius: CGFloat
    let edge: TaskEdgeFlowEdge
    let isDeeplyOccluded: Bool

    static let identity = TaskEdgeFlowMetrics(
        offsetY: 0,
        scaleX: 1,
        scaleY: 1,
        opacity: 1,
        blurRadius: 0,
        edge: .none,
        isDeeplyOccluded: false
    )
}

nonisolated enum TaskEdgeFlowPolicy {
    private static let topZoneEnd: CGFloat = 88
    private static let topTravel: CGFloat = 112
    private static let bottomZoneDepth: CGFloat = 128
    private static let bottomSinkExtension: CGFloat = 8
    private static let deepOcclusionThreshold: CGFloat = 0.86

    static func metrics(
        rowFrame: CGRect,
        viewportHeight: CGFloat,
        intensity: CGFloat,
        reduceMotion: Bool
    ) -> TaskEdgeFlowMetrics {
        let clampedIntensity = clamped(intensity)
        guard clampedIntensity > 0,
              viewportHeight > 0,
              rowFrame.isNull == false,
              rowFrame.isInfinite == false
        else {
            return .identity
        }

        let centerY = rowFrame.midY
        let topProgress = clamped((topZoneEnd - centerY) / topTravel)
        let bottomStart = viewportHeight - bottomZoneDepth
        let bottomSink = viewportHeight + bottomSinkExtension
        let bottomProgress = clamped((centerY - bottomStart) / (bottomSink - bottomStart))

        guard max(topProgress, bottomProgress) > 0 else {
            return .identity
        }

        if bottomProgress > topProgress {
            return bottomMetrics(
                progress: bottomProgress,
                centerY: centerY,
                sinkY: bottomSink,
                reduceMotion: reduceMotion
            )
            .scaled(by: clampedIntensity)
        }

        return topMetrics(progress: topProgress, reduceMotion: reduceMotion)
            .scaled(by: clampedIntensity)
    }

    private static func topMetrics(
        progress: CGFloat,
        reduceMotion: Bool
    ) -> TaskEdgeFlowMetrics {
        let eased = smoothstep(progress)
        if reduceMotion {
            return clarityOnlyMetrics(progress: progress, eased: eased, edge: .top)
        }

        return TaskEdgeFlowMetrics(
            offsetY: -10 * eased,
            scaleX: 1 - 0.004 * eased,
            scaleY: 1 - 0.024 * eased,
            opacity: 1 - 0.82 * Double(eased),
            blurRadius: 1.2 * eased,
            edge: .top,
            isDeeplyOccluded: progress >= deepOcclusionThreshold
        )
    }

    private static func bottomMetrics(
        progress: CGFloat,
        centerY: CGFloat,
        sinkY: CGFloat,
        reduceMotion: Bool
    ) -> TaskEdgeFlowMetrics {
        let eased = smoothstep(progress)
        if reduceMotion {
            return clarityOnlyMetrics(progress: progress, eased: eased, edge: .bottom)
        }

        // Pull rows toward a point just below the viewport. The non-linear
        // convergence compresses spacing visually without changing row layout.
        let convergenceOffset = max(0, sinkY - centerY) * 0.48 * eased
        return TaskEdgeFlowMetrics(
            offsetY: convergenceOffset,
            scaleX: 1 - 0.008 * eased,
            scaleY: 1 - 0.05 * eased,
            opacity: 1 - 0.9 * Double(eased),
            blurRadius: 0,
            edge: .bottom,
            isDeeplyOccluded: progress >= deepOcclusionThreshold
        )
    }

    private static func clarityOnlyMetrics(
        progress: CGFloat,
        eased: CGFloat,
        edge: TaskEdgeFlowEdge
    ) -> TaskEdgeFlowMetrics {
        TaskEdgeFlowMetrics(
            offsetY: 0,
            scaleX: 1,
            scaleY: 1,
            opacity: 1 - 0.88 * Double(eased),
            blurRadius: edge == .top ? 0.4 * eased : 0,
            edge: edge,
            isDeeplyOccluded: progress >= deepOcclusionThreshold
        )
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }
}

private struct TaskEdgeFlowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let intensity: CGFloat
    let isBaseHidden: Bool

    @State private var isDeeplyOccluded = false

    func body(content: Content) -> some View {
        let targetIntensity = intensity
        let usesReducedMotion = reduceMotion

        content
            .visualEffect { effect, proxy in
                let metrics = Self.metrics(
                    proxy: proxy,
                    intensity: targetIntensity,
                    reduceMotion: usesReducedMotion
                )
                return effect
                    .offset(y: metrics.offsetY)
                    .scaleEffect(
                        x: metrics.scaleX,
                        y: metrics.scaleY,
                        anchor: metrics.edge == .top ? .top : .bottom
                    )
                    .blur(radius: metrics.blurRadius)
                    .opacity(metrics.opacity)
            }
            .onGeometryChange(for: Bool.self) { proxy in
                Self.metrics(
                    proxy: proxy,
                    intensity: targetIntensity,
                    reduceMotion: usesReducedMotion
                ).isDeeplyOccluded
            } action: { isDeeplyOccluded in
                self.isDeeplyOccluded = isDeeplyOccluded
            }
            .allowsHitTesting(isBaseHidden == false && isDeeplyOccluded == false)
            .accessibilityHidden(isBaseHidden || isDeeplyOccluded)
    }

    nonisolated private static func metrics(
        proxy: GeometryProxy,
        intensity: CGFloat,
        reduceMotion: Bool
    ) -> TaskEdgeFlowMetrics {
        TaskEdgeFlowPolicy.metrics(
            rowFrame: proxy.frame(in: .scrollView(axis: .vertical)),
            viewportHeight: proxy.bounds(of: .scrollView(axis: .vertical))?.height ?? 0,
            intensity: intensity,
            reduceMotion: reduceMotion
        )
    }
}

extension View {
    func taskEdgeFlow(
        intensity: CGFloat,
        isBaseHidden: Bool
    ) -> some View {
        modifier(
            TaskEdgeFlowModifier(
                intensity: intensity,
                isBaseHidden: isBaseHidden
            )
        )
    }
}

nonisolated private extension TaskEdgeFlowMetrics {
    func scaled(by intensity: CGFloat) -> TaskEdgeFlowMetrics {
        let clampedIntensity = min(max(intensity, 0), 1)
        guard clampedIntensity > 0 else { return .identity }

        return TaskEdgeFlowMetrics(
            offsetY: offsetY * clampedIntensity,
            scaleX: 1 + (scaleX - 1) * clampedIntensity,
            scaleY: 1 + (scaleY - 1) * clampedIntensity,
            opacity: 1 + (opacity - 1) * Double(clampedIntensity),
            blurRadius: blurRadius * clampedIntensity,
            edge: edge,
            isDeeplyOccluded: isDeeplyOccluded && clampedIntensity == 1
        )
    }
}
