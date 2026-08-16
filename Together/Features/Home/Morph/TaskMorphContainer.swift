import SwiftUI

private enum TaskMorphSurfaceMetrics {
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 16
    static let expandedCornerRadius = AppTheme.radius.xl
    static let compactCornerRadius = AppTheme.radius.lg
    static let expandedContentScale: CGFloat = 1.05
    static let backgroundContentScale: CGFloat = 0.94
    static let backgroundContentOpacity: CGFloat = 0.62
    static let detailForegroundContentScale: CGFloat = 1.03
    static let detailBackgroundContentOpacity: CGFloat = 0.40
    static let reducedMotionDetailBackgroundOpacity: CGFloat = 0.65
}

enum TaskMorphListSpacing {
    /// Persisted details remain part of the continuous list and keep the row's
    /// standard external padding plus a symmetric focus-depth breathing space.
    static let expandedExternalSeparation: CGFloat = 14

    static var fixedExpansionHeightDelta: CGFloat {
        expandedExternalSeparation * 2
    }

    static func expandedInsets(from compactInsets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: compactInsets.top + expandedExternalSeparation,
            leading: compactInsets.leading,
            bottom: compactInsets.bottom + expandedExternalSeparation,
            trailing: compactInsets.trailing
        )
    }
}

enum TaskExpansionMotionTiming {
    static let expansionDuration: TimeInterval = 0.80
    static let identityExpansionDuration: TimeInterval = 0.52
    static let collapseDuration: TimeInterval = 0.36
    static let reducedMotionDuration: TimeInterval = 0.22
    static let layoutDuration: TimeInterval = 0.52
    static let identityTroughDuration: TimeInterval = 0.18
    static let identityRiseDuration: TimeInterval = 0.34
    static let identityCollapseToTroughDuration: TimeInterval = 0.23
    static let identityCollapseToCompactDuration: TimeInterval = 0.13
    /// The expanded row adds 14pt of real top spacing. Ending at -12pt
    /// compensates for that layout shift so the visible down/up wave reads
    /// close to equal amplitude instead of remaining visually low.
    static let identityTroughOffset = CGSize(width: -7, height: 14)
    static let expandedIdentityOffset = CGSize(width: -16, height: -12)
    /// Relative scales account for the foreground container's 1.03 depth scale,
    /// keeping the identity group near 1.08 at the trough and 1.12 at rest.
    static let identityTroughScale: CGFloat = 1.05
    static let expandedIdentityScale: CGFloat = 1.12 / TaskMorphSurfaceMetrics.detailForegroundContentScale
    static let expandedIdentityVisualScale: CGFloat = 1.12
}

enum TaskMorphCascadeTiming {
    /// Detail rows may enter while the identity is moving, but the first row
    /// must not settle before the identity reaches its 520ms endpoint.
    static let expansionDelay: TimeInterval = 0.34
    static let timelineDuration: TimeInterval = 0.46
    static let rowDuration: TimeInterval = 0.20
    static let rowDelay: TimeInterval = 0.055
    static let maximumTotalDelay: TimeInterval = 0.26
    static let collapseRowDuration: TimeInterval = 0.22
    static let collapseRowDelay: TimeInterval = 0.035
    static let maximumCollapseTotalDelay: TimeInterval = 0.14
    static let minimumOpacity: CGFloat = 0
    static let startOffset = CGSize(width: 14, height: 24)
    static let bendOffset = CGSize(width: 5, height: 9)

    static func totalDelay(rowCount: Int) -> TimeInterval {
        guard rowCount > 1 else { return 0 }
        return min(maximumTotalDelay, rowDelay * Double(rowCount - 1))
    }

    static func collapseTotalDelay(rowCount: Int) -> TimeInterval {
        guard rowCount > 1 else { return 0 }
        return min(maximumCollapseTotalDelay, collapseRowDelay * Double(rowCount - 1))
    }
}

enum TaskMorphBackgroundWave {
    static let adjacentRadius: CGFloat = 1.30
    static let radiusStep: CGFloat = 0.75
    static let maximumRadius: CGFloat = 4.8
    static let adjacentScale: CGFloat = 0.92
    static let scaleStep: CGFloat = 0.012
    static let minimumScale: CGFloat = 0.86
    static let adjacentOffset: CGFloat = 4
    static let offsetStep: CGFloat = 2
    static let maximumOffset: CGFloat = 12
    static let rowDelay: TimeInterval = 0.025
    static let maximumDelay: TimeInterval = 0.12
    static let headerBlurRadius: CGFloat = 1.6

    static func radius(forTaskDelta delta: Int?) -> CGFloat {
        guard let distance = delta.map(abs), distance > 0 else { return 0 }
        return min(
            maximumRadius,
            adjacentRadius + CGFloat(distance - 1) * radiusStep
        )
    }

    static func scale(forTaskDelta delta: Int?) -> CGFloat {
        guard let distance = delta.map(abs), distance > 0 else { return 1 }
        return max(
            minimumScale,
            adjacentScale - CGFloat(distance - 1) * scaleStep
        )
    }

    static func offsetY(forTaskDelta delta: Int?) -> CGFloat {
        guard let delta, delta != 0 else { return 0 }
        let magnitude = min(
            maximumOffset,
            adjacentOffset + CGFloat(abs(delta) - 1) * offsetStep
        )
        return delta < 0 ? -magnitude : magnitude
    }

    static func delay(forTaskDelta delta: Int?) -> TimeInterval {
        guard let distance = delta.map(abs), distance > 1 else { return 0 }
        return min(maximumDelay, Double(distance - 1) * rowDelay)
    }
}

struct TaskExpansionMotion: Equatable {
    var layoutProgress: CGFloat
    var compactHeightProgress: CGFloat
    var identityScale: CGFloat
    var identityOffsetX: CGFloat
    var collapsedOpacity: CGFloat
    var identityOffsetY: CGFloat
    var detailElapsed: TimeInterval

    static let compact = TaskExpansionMotion(
        layoutProgress: 0,
        compactHeightProgress: 1,
        identityScale: 1,
        identityOffsetX: 0,
        collapsedOpacity: 1,
        identityOffsetY: 0,
        detailElapsed: 0
    )

    static let expanded = TaskExpansionMotion(
        layoutProgress: 1,
        compactHeightProgress: 0,
        identityScale: TaskExpansionMotionTiming.expandedIdentityScale,
        identityOffsetX: TaskExpansionMotionTiming.expandedIdentityOffset.width,
        collapsedOpacity: 0,
        identityOffsetY: TaskExpansionMotionTiming.expandedIdentityOffset.height,
        detailElapsed: TaskMorphCascadeTiming.timelineDuration
    )

    var isDetailSettled: Bool {
        detailElapsed >= TaskMorphCascadeTiming.timelineDuration - 0.001
    }

    func cascadeElapsed(isCollapsing: Bool) -> TimeInterval {
        guard isCollapsing else { return detailElapsed }
        return TaskMorphCascadeTiming.timelineDuration
            * TimeInterval(min(max(layoutProgress, 0), 1))
    }

}

struct TaskMorphCascadeValues: Equatable {
    let progress: CGFloat
    let offset: CGSize
    let opacity: CGFloat

    static func resolve(
        elapsed: TimeInterval,
        index: Int,
        rowCount: Int,
        reduceMotion: Bool,
        isCollapsing: Bool = false
    ) -> TaskMorphCascadeValues {
        let clampedRowCount = max(rowCount, 1)
        let clampedIndex = min(max(index, 0), clampedRowCount - 1)

        if reduceMotion {
            let reducedProgress = min(
                max(CGFloat(elapsed / TaskMorphCascadeTiming.timelineDuration), 0),
                1
            )
            return TaskMorphCascadeValues(
                progress: reducedProgress,
                offset: .zero,
                opacity: reducedProgress
            )
        }

        let progress: CGFloat
        if isCollapsing {
            let totalDelay = TaskMorphCascadeTiming.collapseTotalDelay(rowCount: clampedRowCount)
            let reverseIndex = clampedRowCount - clampedIndex - 1
            let delay: TimeInterval = if clampedRowCount > 1 {
                totalDelay * Double(reverseIndex) / Double(clampedRowCount - 1)
            } else {
                0
            }
            let normalizedElapsed = min(
                max(elapsed / TaskMorphCascadeTiming.timelineDuration, 0),
                1
            )
            let collapseElapsed = TaskExpansionMotionTiming.collapseDuration * (1 - normalizedElapsed)
            let exitProgress = min(
                max(
                    CGFloat(
                        (collapseElapsed - delay)
                            / TaskMorphCascadeTiming.collapseRowDuration
                    ),
                    0
                ),
                1
            )
            progress = 1 - exitProgress
        } else {
            let totalDelay = TaskMorphCascadeTiming.totalDelay(rowCount: clampedRowCount)
            let delay: TimeInterval = if clampedRowCount > 1 {
                totalDelay * Double(clampedIndex) / Double(clampedRowCount - 1)
            } else {
                0
            }
            progress = min(
                max(
                    CGFloat(
                        (elapsed - delay) / TaskMorphCascadeTiming.rowDuration
                    ),
                    0
                ),
                1
            )
        }

        let offset = waveOffset(progress: progress)
        let opacityProgress = smoothStep(progress)
        return TaskMorphCascadeValues(
            progress: progress,
            offset: offset,
            opacity: TaskMorphCascadeTiming.minimumOpacity
                + (1 - TaskMorphCascadeTiming.minimumOpacity) * opacityProgress
        )
    }

    private static func waveOffset(progress: CGFloat) -> CGSize {
        let t = min(max(progress, 0), 1)
        let oneMinusT = 1 - t
        let start = TaskMorphCascadeTiming.startOffset
        let firstControl = CGSize(width: 10, height: 13)
        let secondControl = TaskMorphCascadeTiming.bendOffset

        return CGSize(
            width: oneMinusT * oneMinusT * oneMinusT * start.width
                + 3 * oneMinusT * oneMinusT * t * firstControl.width
                + 3 * oneMinusT * t * t * secondControl.width,
            height: oneMinusT * oneMinusT * oneMinusT * start.height
                + 3 * oneMinusT * oneMinusT * t * firstControl.height
                + 3 * oneMinusT * t * t * secondControl.height
        )
    }

    private static func smoothStep(_ progress: CGFloat) -> CGFloat {
        progress * progress * (3 - 2 * progress)
    }
}

private struct TaskMorphCascadeModifier: ViewModifier {
    let elapsed: TimeInterval
    let index: Int
    let rowCount: Int
    let isCollapsing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let values = TaskMorphCascadeValues.resolve(
            elapsed: elapsed,
            index: index,
            rowCount: rowCount,
            reduceMotion: reduceMotion,
            isCollapsing: isCollapsing
        )

        content
            .offset(x: values.offset.width, y: values.offset.height)
            .opacity(values.opacity)
            .allowsHitTesting(isCollapsing == false && values.progress >= 0.999)
            .accessibilityHidden(isCollapsing || values.progress < 0.999)
    }
}

extension View {
    func taskMorphCascade(
        elapsed: TimeInterval,
        index: Int,
        rowCount: Int,
        isCollapsing: Bool = false
    ) -> some View {
        modifier(
            TaskMorphCascadeModifier(
                elapsed: elapsed,
                index: index,
                rowCount: rowCount,
                isCollapsing: isCollapsing
            )
        )
    }
}

private struct TaskExpansionMotionTarget: Equatable {
    let isExpanded: Bool
    let reduceMotion: Bool
}

struct TaskMorphContainer<Content: View>: View {
    let state: TaskMorphVisualState
    let isActive: Bool
    let hidesRealSurfaceForHero: Bool
    var isBackgroundDeemphasized = false
    var backgroundFocusDelta: Int? = nil
    var isBackgroundDimmed = false
    var onBackgroundTap: (() -> Void)? = nil
    @ViewBuilder let content: (TaskExpansionMotion) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        KeyframeAnimator(
            initialValue: TaskExpansionMotion.compact,
            trigger: motionTarget
        ) { motion in
            VStack(alignment: .leading, spacing: 0) {
                content(motion)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(hidesRealSurfaceForHero ? 0 : backgroundContentOpacity * backgroundDimOpacity)
            .brightness(backgroundBrightness)
            .overlay {
                if isBackgroundDeemphasized, let onBackgroundTap {
                    Button(action: onBackgroundTap) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起任务详情")
                    .accessibilityHint("保存更改并收起当前任务")
                }
            }
            .accessibilityElement(children: .contain)
        } keyframes: { initialValue in
            KeyframeTrack(\.layoutProgress) {
                if reduceMotion {
                    LinearKeyframe(
                        motionTarget.isExpanded ? 1 : 0,
                        duration: TaskExpansionMotionTiming.reducedMotionDuration
                    )
                } else if motionTarget.isExpanded {
                    CubicKeyframe(
                        1,
                        duration: TaskExpansionMotionTiming.layoutDuration
                    )
                } else {
                    CubicKeyframe(
                        0,
                        duration: TaskExpansionMotionTiming.collapseDuration
                    )
                }
            }

            KeyframeTrack(\.compactHeightProgress) {
                if reduceMotion {
                    LinearKeyframe(
                        motionTarget.isExpanded ? 0 : 1,
                        duration: TaskExpansionMotionTiming.reducedMotionDuration
                    )
                } else if motionTarget.isExpanded {
                    CubicKeyframe(0, duration: 0.20)
                } else {
                    LinearKeyframe(0, duration: 0.14)
                    CubicKeyframe(1, duration: 0.22)
                }
            }

            KeyframeTrack(\.identityScale) {
                if reduceMotion {
                    LinearKeyframe(1, duration: TaskExpansionMotionTiming.reducedMotionDuration)
                } else if motionTarget.isExpanded {
                    CubicKeyframe(
                        TaskExpansionMotionTiming.identityTroughScale,
                        duration: TaskExpansionMotionTiming.identityTroughDuration
                    )
                    CubicKeyframe(
                        TaskExpansionMotionTiming.expandedIdentityScale,
                        duration: TaskExpansionMotionTiming.identityRiseDuration,
                        endVelocity: 0
                    )
                } else {
                    CubicKeyframe(
                        TaskExpansionMotionTiming.identityTroughScale,
                        duration: TaskExpansionMotionTiming.identityCollapseToTroughDuration
                    )
                    CubicKeyframe(
                        1,
                        duration: TaskExpansionMotionTiming.identityCollapseToCompactDuration,
                        endVelocity: 0
                    )
                }
            }

            KeyframeTrack(\.identityOffsetX) {
                if reduceMotion {
                    LinearKeyframe(0, duration: TaskExpansionMotionTiming.reducedMotionDuration)
                } else if motionTarget.isExpanded {
                    CubicKeyframe(
                        TaskExpansionMotionTiming.identityTroughOffset.width,
                        duration: TaskExpansionMotionTiming.identityTroughDuration
                    )
                    CubicKeyframe(
                        TaskExpansionMotionTiming.expandedIdentityOffset.width,
                        duration: TaskExpansionMotionTiming.identityRiseDuration,
                        endVelocity: 0
                    )
                } else {
                    CubicKeyframe(
                        TaskExpansionMotionTiming.identityTroughOffset.width,
                        duration: TaskExpansionMotionTiming.identityCollapseToTroughDuration
                    )
                    CubicKeyframe(
                        0,
                        duration: TaskExpansionMotionTiming.identityCollapseToCompactDuration,
                        endVelocity: 0
                    )
                }
            }

            KeyframeTrack(\.collapsedOpacity) {
                if reduceMotion {
                    LinearKeyframe(motionTarget.isExpanded ? 0 : 1, duration: 0.20)
                } else if motionTarget.isExpanded {
                    CubicKeyframe(0, duration: 0.22)
                } else {
                    LinearKeyframe(0, duration: 0.14)
                    CubicKeyframe(1, duration: 0.22)
                }
            }

            KeyframeTrack(\.identityOffsetY) {
                if reduceMotion {
                    LinearKeyframe(0, duration: TaskExpansionMotionTiming.reducedMotionDuration)
                } else if motionTarget.isExpanded {
                    CubicKeyframe(
                        TaskExpansionMotionTiming.identityTroughOffset.height,
                        duration: TaskExpansionMotionTiming.identityTroughDuration
                    )
                    CubicKeyframe(
                        TaskExpansionMotionTiming.expandedIdentityOffset.height,
                        duration: TaskExpansionMotionTiming.identityRiseDuration,
                        endVelocity: 0
                    )
                } else {
                    CubicKeyframe(
                        TaskExpansionMotionTiming.identityTroughOffset.height,
                        duration: TaskExpansionMotionTiming.identityCollapseToTroughDuration
                    )
                    CubicKeyframe(
                        0,
                        duration: TaskExpansionMotionTiming.identityCollapseToCompactDuration,
                        endVelocity: 0
                    )
                }
            }

            KeyframeTrack(\.detailElapsed) {
                if reduceMotion {
                    LinearKeyframe(
                        motionTarget.isExpanded ? TaskMorphCascadeTiming.timelineDuration : 0,
                        duration: TaskExpansionMotionTiming.reducedMotionDuration
                    )
                } else if motionTarget.isExpanded {
                    LinearKeyframe(
                        initialValue.detailElapsed,
                        duration: initialValue.detailElapsed <= 0.001
                            ? TaskMorphCascadeTiming.expansionDelay
                            : 0.001
                    )
                    LinearKeyframe(
                        TaskMorphCascadeTiming.timelineDuration,
                        duration: TaskMorphCascadeTiming.timelineDuration
                    )
                } else {
                    LinearKeyframe(
                        0,
                        duration: TaskExpansionMotionTiming.collapseDuration
                    )
                }
            }
        }
        .scaleEffect(
            isForegroundElevated
                ? TaskMorphSurfaceMetrics.detailForegroundContentScale
                : 1,
            anchor: .topLeading
        )
        .scaleEffect(
            isBackgroundDeemphasized && reduceMotion == false
                ? TaskMorphBackgroundWave.scale(forTaskDelta: backgroundFocusDelta)
                : 1,
            anchor: .center
        )
        .offset(y: detailBackgroundOffsetY)
        .opacity(detailBackgroundDepthOpacity)
        .blur(radius: detailBackgroundBlurRadius)
        .animation(foregroundDepthAnimation, value: isForegroundElevated)
        .animation(detailBackgroundDepthAnimation, value: backgroundWaveTarget)
    }

    private var motionTarget: TaskExpansionMotionTarget {
        TaskExpansionMotionTarget(
            isExpanded: isActive && state == .expanded,
            reduceMotion: reduceMotion
        )
    }

    private var backgroundContentOpacity: CGFloat {
        1
    }

    private var isForegroundElevated: Bool {
        reduceMotion == false && motionTarget.isExpanded
    }

    private var backgroundBrightness: Double {
        guard isBackgroundDimmed else { return 0 }
        return colorScheme == .dark ? -0.06 : -0.10
    }

    private var backgroundDimOpacity: CGFloat {
        isBackgroundDimmed ? 0.78 : 1
    }

    private var detailBackgroundDepthOpacity: CGFloat {
        guard isBackgroundDeemphasized else { return 1 }
        return reduceMotion
            ? TaskMorphSurfaceMetrics.reducedMotionDetailBackgroundOpacity
            : TaskMorphSurfaceMetrics.detailBackgroundContentOpacity
    }

    private var detailBackgroundBlurRadius: CGFloat {
        guard isBackgroundDeemphasized, reduceMotion == false else { return 0 }
        return TaskMorphBackgroundWave.radius(forTaskDelta: backgroundFocusDelta)
    }

    private var detailBackgroundOffsetY: CGFloat {
        guard isBackgroundDeemphasized, reduceMotion == false else { return 0 }
        return TaskMorphBackgroundWave.offsetY(forTaskDelta: backgroundFocusDelta)
    }

    private var backgroundWaveTarget: TaskMorphBackgroundWaveTarget {
        TaskMorphBackgroundWaveTarget(
            isDeemphasized: isBackgroundDeemphasized,
            taskDelta: backgroundFocusDelta,
            reduceMotion: reduceMotion
        )
    }

    private var detailBackgroundDepthAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: TaskExpansionMotionTiming.reducedMotionDuration)
        }
        let animation = Animation.timingCurve(
            0.20,
            0,
            0.16,
            1,
            duration: isBackgroundDeemphasized
                ? TaskExpansionMotionTiming.identityExpansionDuration
                : TaskExpansionMotionTiming.collapseDuration
        )
        guard isBackgroundDeemphasized else { return animation }
        return animation.delay(
            TaskMorphBackgroundWave.delay(forTaskDelta: backgroundFocusDelta)
        )
    }

    private var foregroundDepthAnimation: Animation {
        .timingCurve(
            0.20,
            0,
            0.16,
            1,
            duration: isForegroundElevated
                ? TaskExpansionMotionTiming.identityExpansionDuration
                : TaskExpansionMotionTiming.collapseDuration
        )
    }

}

private struct TaskMorphBackgroundWaveTarget: Equatable {
    let isDeemphasized: Bool
    let taskDelta: Int?
    let reduceMotion: Bool
}

private struct TaskMorphBackgroundDepthModifier: ViewModifier {
    let isDeemphasized: Bool
    let anchor: UnitPoint
    let scalesContent: Bool
    let appliesVisualDepth: Bool
    let detailBlurRadius: CGFloat
    let actsAsDismissTarget: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isDeemphasized == false)
            .accessibilityHidden(isDeemphasized)
            .scaleEffect(
                reduceMotion || isDeemphasized == false || scalesContent == false || appliesVisualDepth == false
                    ? 1
                    : TaskMorphSurfaceMetrics.backgroundContentScale,
                anchor: anchor
            )
            .opacity(
                isDeemphasized && appliesVisualDepth
                    ? TaskMorphSurfaceMetrics.backgroundContentOpacity
                    : 1
            )
            .brightness(
                isDeemphasized && appliesVisualDepth
                    ? (colorScheme == .dark ? -0.06 : -0.10)
                    : 0
            )
            .blur(
                radius: isDeemphasized && appliesVisualDepth == false && reduceMotion == false
                    ? detailBlurRadius
                    : 0
            )
            .overlay {
                if isDeemphasized, actsAsDismissTarget {
                    Button(action: onDismiss) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起任务详情")
                    .accessibilityHint("保存更改并收起当前任务")
                }
            }
            .animation(backgroundDepthAnimation, value: isDeemphasized)
    }

    private var backgroundDepthAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: TaskExpansionMotionTiming.reducedMotionDuration)
            : .smooth(
                duration: isDeemphasized
                    ? TaskExpansionMotionTiming.identityExpansionDuration
                    : TaskExpansionMotionTiming.collapseDuration,
                extraBounce: 0
            )
    }
}

extension View {
    /// Applies the same compositor-only depth treatment as inactive task rows
    /// and temporarily converts the visible surface into a dismissal target.
    func taskMorphBackgroundDepth(
        isDeemphasized: Bool,
        anchor: UnitPoint = .center,
        scalesContent: Bool = true,
        appliesVisualDepth: Bool = true,
        detailBlurRadius: CGFloat = 0,
        actsAsDismissTarget: Bool = true,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            TaskMorphBackgroundDepthModifier(
                isDeemphasized: isDeemphasized,
                anchor: anchor,
                scalesContent: scalesContent,
                appliesVisualDepth: appliesVisualDepth,
                detailBlurRadius: detailBlurRadius,
                actsAsDismissTarget: actsAsDismissTarget,
                onDismiss: onDismiss
            )
        )
    }
}

struct TaskMorphDisclosure<Content: View>: View {
    let progress: CGFloat
    let isInteractive: Bool
    let estimatedHeight: CGFloat
    let onMeasuredHeight: ((CGFloat) -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    init(
        progress: CGFloat,
        isInteractive: Bool,
        estimatedHeight: CGFloat = 0,
        onMeasuredHeight: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.isInteractive = isInteractive
        self.estimatedHeight = estimatedHeight
        self.onMeasuredHeight = onMeasuredHeight
        self.content = content
    }

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                updateMeasuredHeight(height)
            }
            .modifier(
                TaskMorphDisclosureModifier(
                    progress: progress,
                    expandedHeight: resolvedExpandedHeight
                )
            )
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(isInteractive == false)
    }

    private var resolvedExpandedHeight: CGFloat {
        measuredHeight > 0 ? measuredHeight : estimatedHeight
    }

    private func updateMeasuredHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        onMeasuredHeight?(height)
        guard abs(height - measuredHeight) > 0.5 else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            measuredHeight = height
        }
    }
}

struct TaskMorphMeasuredRegion<Content: View>: View {
    let progress: CGFloat
    let isInteractive: Bool
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                guard height.isFinite, height > 0, abs(height - measuredHeight) > 0.5 else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    measuredHeight = height
                }
            }
            .frame(height: measuredHeight * min(max(progress, 0), 1), alignment: .top)
            .modifier(TaskMorphConditionalClipModifier(progress: progress))
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(isInteractive == false)
    }
}

struct TaskMorphInterpolatedHeightRegion<Compact: View, Expanded: View, Visible: View>: View {
    let progress: CGFloat
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let expanded: () -> Expanded
    @ViewBuilder let visible: () -> Visible

    @State private var compactHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            compact()
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    update(height, target: $compactHeight)
                }

            expanded()
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    update(height, target: $expandedHeight)
                }

            visible()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: resolvedHeight, alignment: .top)
        .modifier(TaskMorphConditionalClipModifier(progress: progress))
    }

    private var resolvedHeight: CGFloat? {
        guard compactHeight > 0, expandedHeight > 0 else { return nil }
        let progress = min(max(progress, 0), 1)
        return compactHeight + (expandedHeight - compactHeight) * progress
    }

    private func update(_ height: CGFloat, target: Binding<CGFloat>) {
        guard height.isFinite, height > 0, abs(height - target.wrappedValue) > 0.5 else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            target.wrappedValue = height
        }
    }
}

private struct TaskMorphDisclosureModifier: AnimatableModifier {
    var progress: CGFloat
    let expandedHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(
                height: expandedHeight * min(max(progress, 0), 1),
                alignment: .top
            )
            .modifier(TaskMorphConditionalClipModifier(progress: progress))
    }
}

private struct TaskMorphConditionalClipModifier: ViewModifier {
    let progress: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if progress < 0.999 {
            content.clipped()
        } else {
            content
        }
    }
}

extension View {
    func taskMorphListPlacement(
        state: TaskMorphVisualState,
        isActive: Bool,
        compactInsets: EdgeInsets
    ) -> some View {
        modifier(
            TaskMorphListPlacementModifier(
                isExpanded: isActive && state == .expanded,
                compactInsets: compactInsets
            )
        )
    }

    func taskCreationListReveal(
        isTarget: Bool,
        isEnabled: Bool,
        onCompleted: @escaping () -> Void
    ) -> some View {
        modifier(
            TaskCreationListRevealModifier(
                isTarget: isTarget,
                isEnabled: isEnabled,
                onCompleted: onCompleted
            )
        )
    }
}

private struct TaskMorphListPlacementModifier: ViewModifier {
    let isExpanded: Bool
    let compactInsets: EdgeInsets

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let usesExpandedSpacing = isExpanded && reduceMotion == false

        content
            .padding(
                usesExpandedSpacing
                    ? TaskMorphListSpacing.expandedInsets(from: compactInsets)
                    : compactInsets
            )
            .animation(placementAnimation, value: usesExpandedSpacing)
    }

    private var placementAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: TaskExpansionMotionTiming.reducedMotionDuration)
        }
        return .smooth(
            duration: isExpanded
                ? TaskExpansionMotionTiming.identityExpansionDuration
                : TaskExpansionMotionTiming.collapseDuration,
            extraBounce: 0
        )
    }
}

private struct TaskCreationListRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isTarget: Bool
    let isEnabled: Bool
    let onCompleted: () -> Void

    @State private var naturalHeight: CGFloat = 0
    @State private var revealProgress: CGFloat = 0
    @State private var hasStarted = false
    @State private var revealTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isTarget {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard height.isFinite, height > 0 else { return }
                    naturalHeight = max(naturalHeight, height)
                    startRevealIfReady()
                }
                .frame(height: naturalHeight * revealProgress, alignment: .top)
                .clipped()
                .opacity(revealProgress)
                .scaleEffect(0.985 + 0.015 * revealProgress, anchor: .top)
                .onChange(of: isEnabled) { _, _ in
                    startRevealIfReady()
                }
                .onDisappear {
                    revealTask?.cancel()
                    revealTask = nil
                    if hasStarted {
                        onCompleted()
                    }
                }
        } else {
            content
        }
    }

    private var revealAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .smooth(duration: 0.3, extraBounce: 0)
    }

    private func startRevealIfReady() {
        guard isTarget,
              isEnabled,
              naturalHeight > 0,
              hasStarted == false
        else { return }

        hasStarted = true
        revealProgress = 0
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            withAnimation(
                revealAnimation,
                completionCriteria: .logicallyComplete
            ) {
                revealProgress = 1
            } completion: {
                guard Task.isCancelled == false else { return }
                onCompleted()
            }
        }
    }
}

struct HomeCreationMorphOverlayLayer: View {
    @Bindable var session: HomeMorphSession

    @Environment(AppContext.self) private var appContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var measuredTodoEditorContentHeight: CGFloat = 0
    @State private var measuredTodoEditorSubjectID: UUID?

    var body: some View {
        GeometryReader { proxy in
            if let subject = session.subject, session.isCreationOverlayVisible {
                let rootFrame = proxy.frame(in: .global)
                let editorFrame = editorFrame(in: proxy)
                let dissolvedFrame = dissolvedFrame(from: editorFrame)
                let frame = currentFrame(
                    rootFrame: rootFrame,
                    editorFrame: editorFrame,
                    dissolvedFrame: dissolvedFrame
                )

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }

                Color.black
                    .opacity(creationScrimOpacity * backgroundScrimProgress)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                RoundedRectangle(
                    cornerRadius: surfaceCornerRadius(frame: frame),
                    style: .continuous
                )
                .fill(AppTheme.colors.surface)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: surfaceCornerRadius(frame: frame),
                        style: .continuous
                    )
                    .strokeBorder(AppTheme.colors.body.opacity(0.06), lineWidth: 0.5)
                }
                .opacity(surfaceChromeOpacity)
                .shadow(
                    color: .black.opacity(0.2 * surfaceChromeOpacity),
                    radius: 20 * surfaceChromeOpacity,
                    y: 9 * surfaceChromeOpacity
                )
                .overlay {
                    editorContent(for: subject)
                        .padding(.horizontal, TaskMorphSurfaceMetrics.horizontalInset)
                        .padding(.vertical, TaskMorphSurfaceMetrics.verticalInset)
                        .scaleEffect(editorContentScale, anchor: .top)
                        .opacity(editorContentOpacity)
                        .allowsHitTesting(session.isInteractive)
                }
                .overlay {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.colors.title)
                        .opacity(heroSourceGlyphOpacity)
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: surfaceCornerRadius(frame: frame),
                        style: .continuous
                    )
                )
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .accessibilityElement(children: .contain)
                .accessibilityAction(.escape) {
                    session.requestDismissal()
                }
                .task(id: globalFrame(editorFrame, in: rootFrame)) {
                    session.recordHeroTargetFrame(globalFrame(editorFrame, in: rootFrame))
                    runHeroIfCurrent()
                }
            }
        }
        .ignoresSafeArea(.container, edges: .all)
    }

    @ViewBuilder
    private func editorContent(for subject: TaskMorphSubject) -> some View {
        ScrollView {
            Group {
                switch subject.domain {
                case .todo:
                    if let creation = appContext.homeViewModel.taskCreationSession,
                       creation.id == subject.id {
                        HomeTaskCreationCard(
                            viewModel: appContext.homeViewModel,
                            session: creation,
                            isExpanded: true,
                            isInteractive: session.isInteractive,
                            onDiscard: { session.requestDismissal() },
                            onCommit: { session.requestCommit() }
                        )
                        .id(creation.id)
                    }
                case .periodic:
                    if let creation = appContext.routinesViewModel.creationSession,
                       creation.id == subject.id {
                        PeriodicTaskCreationCard(
                            viewModel: appContext.routinesViewModel,
                            session: creation,
                            isInteractive: session.isInteractive,
                            onDiscard: { session.requestDismissal() },
                            onCommit: { session.requestCommit() }
                        )
                        .id(creation.id)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                guard subject.domain == .todo, height.isFinite, height > 0 else { return }
                measuredTodoEditorSubjectID = subject.id
                measuredTodoEditorContentHeight = height
            }
        }
        .scrollIndicators(.hidden)
    }

    private func runHeroIfCurrent() {
        guard let token = session.currentToken(), session.phase == .heroEntering else { return }
        withAnimation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92),
            completionCriteria: .logicallyComplete
        ) {
            session.setHeroProgress(1, using: token)
        } completion: {
            guard session.isCurrent(token) else { return }
            session.finishHero(using: token)
        }
    }

    private var creationScrimOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.18
    }

    private func editorFrame(in proxy: GeometryProxy) -> CGRect {
        let horizontalInset: CGFloat = 12
        let verticalInset: CGFloat = 14
        let availableHeight = max(120, proxy.size.height - verticalInset * 2)
        let isTodo = session.subject?.domain == .todo
        let preferredHeight: CGFloat = if isTodo {
            if measuredTodoEditorSubjectID == session.subject?.id {
                max(206, measuredTodoEditorContentHeight + 2 * TaskMorphSurfaceMetrics.verticalInset)
            } else {
                206
            }
        } else {
            560
        }
        let height = min(preferredHeight, availableHeight)
        let y: CGFloat = if isTodo {
            max(verticalInset, proxy.size.height - height - 10)
        } else {
            max(verticalInset, (proxy.size.height - height) / 2)
        }
        return CGRect(
            x: horizontalInset,
            y: y,
            width: max(120, proxy.size.width - horizontalInset * 2),
            height: height
        )
    }

    private func dissolvedFrame(from editorFrame: CGRect) -> CGRect {
        CGRect(
            x: editorFrame.minX + editorFrame.width * 0.09,
            y: editorFrame.midY - 0.5,
            width: editorFrame.width * 0.82,
            height: 1
        )
    }

    private func currentFrame(
        rootFrame: CGRect,
        editorFrame: CGRect,
        dissolvedFrame: CGRect
    ) -> CGRect {
        switch session.phase {
        case .heroEntering:
            guard let source = session.heroSourceFrame else { return editorFrame }
            return interpolatedFrame(
                from: localFrame(source, in: rootFrame),
                to: editorFrame,
                progress: session.heroProgress
            )
        case .active, .saving:
            return editorFrame
        case .collapsing:
            return dissolvedFrame
        case .relocating, .idle:
            return dissolvedFrame
        }
    }

    private func interpolatedFrame(from source: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: source.minX + (target.minX - source.minX) * progress,
            y: source.minY + (target.minY - source.minY) * progress,
            width: source.width + (target.width - source.width) * progress,
            height: source.height + (target.height - source.height) * progress
        )
    }

    private func localFrame(_ globalFrame: CGRect, in rootFrame: CGRect) -> CGRect {
        globalFrame.offsetBy(dx: -rootFrame.minX, dy: -rootFrame.minY)
    }

    private func globalFrame(_ localFrame: CGRect, in rootFrame: CGRect) -> CGRect {
        localFrame.offsetBy(dx: rootFrame.minX, dy: rootFrame.minY)
    }

    private func surfaceCornerRadius(frame: CGRect) -> CGFloat {
        if session.phase == .heroEntering {
            let source = session.heroSourceFrame ?? frame
            let start = min(source.width, source.height) / 2
            return start + (TaskMorphSurfaceMetrics.expandedCornerRadius - start) * session.heroProgress
        }
        return session.phase == .collapsing
            ? TaskMorphSurfaceMetrics.compactCornerRadius
            : TaskMorphSurfaceMetrics.expandedCornerRadius
    }

    private var surfaceChromeOpacity: CGFloat {
        switch session.phase {
        case .heroEntering:
            1
        case .collapsing, .relocating, .idle:
            0
        case .active, .saving:
            1
        }
    }

    private var backgroundScrimProgress: CGFloat {
        switch session.phase {
        case .heroEntering:
            session.heroProgress
        case .active, .saving:
            1
        case .collapsing, .relocating, .idle:
            0
        }
    }

    private var editorContentOpacity: CGFloat {
        switch session.phase {
        case .heroEntering:
            min(max((session.heroProgress - 0.18) / 0.82, 0), 1)
        case .active, .saving:
            1
        case .collapsing, .idle, .relocating:
            0
        }
    }

    private var editorContentScale: CGFloat {
        guard reduceMotion == false else { return 1 }
        return switch session.phase {
        case .heroEntering:
            1 + (TaskMorphSurfaceMetrics.expandedContentScale - 1) * session.heroProgress
        case .active, .saving:
            TaskMorphSurfaceMetrics.expandedContentScale
        case .collapsing:
            0.985
        case .relocating, .idle:
            1
        }
    }

    private var heroSourceGlyphOpacity: CGFloat {
        session.phase == .heroEntering ? 1 - session.heroProgress : 0
    }
}
