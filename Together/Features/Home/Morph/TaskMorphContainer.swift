import SwiftUI

private enum TaskMorphSurfaceMetrics {
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 16
    static let backgroundContentScale: CGFloat = 0.94
    static let backgroundContentOpacity: CGFloat = 0.62
    static let detailForegroundContentScale: CGFloat = 1.05
    static let detailFallbackBackgroundOpacity: CGFloat = 0.25
    static let reducedMotionDetailBackgroundOpacity: CGFloat = 0.65
}

enum TaskMorphFocusField {
    static let lightParticleRetention: CGFloat = 0.18
    static let increasedContrastLightParticleRetention: CGFloat = 0.10

    static var lightOverlayOpacity: CGFloat {
        1 - lightParticleRetention
    }

    static var increasedContrastLightOverlayOpacity: CGFloat {
        1 - increasedContrastLightParticleRetention
    }
}

enum TaskMorphListSpacing {
    /// Keep compact rows dense while preserving the row content's own 44pt
    /// interaction target.
    static let compactExternalInset: CGFloat = 4

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
    static let expansionDuration: TimeInterval = 0.70
    static let identityExpansionDuration: TimeInterval = 0.46
    static let collapseDuration: TimeInterval = 0.32
    static let reducedMotionDuration: TimeInterval = 0.22
    static let layoutDuration: TimeInterval = 0.46
    static let identityTroughDuration: TimeInterval = 0.16
    static let identityRiseDuration: TimeInterval = 0.30
    static let identityCollapseToTroughDuration: TimeInterval = 0.20
    static let identityCollapseToCompactDuration: TimeInterval = 0.12
    /// The expanded row adds 14pt of real top spacing. Ending at -12pt
    /// compensates for that layout shift so the visible down/up wave reads
    /// close to equal amplitude instead of remaining visually low.
    static let identityTroughOffset = CGSize(width: -7, height: 14)
    static let expandedIdentityOffset = CGSize(width: -16, height: -12)
    /// Relative scales account for the foreground container's 1.05 depth scale,
    /// keeping the identity group near 1.10 at the trough and 1.12 at rest.
    static let identityTroughScale: CGFloat = 1.05
    static let expandedIdentityScale: CGFloat = 1.12 / TaskMorphSurfaceMetrics.detailForegroundContentScale
    static let expandedIdentityVisualScale: CGFloat = 1.12
}

enum TaskCreationInputTiming {
    /// Gives the title focus and keyboard-safe viewport a brief head start
    /// before the one-shot draft pre-position begins.
    static let prepositionLeadDuration: TimeInterval = 0.14
    /// Moves the compact draft toward its final expanded position while the
    /// disclosure animation starts, avoiding both an idle gap and a second jump.
    static let prepositionDuration: TimeInterval = 0.22
    /// Keeps the saved draft mounted long enough for the add label to converge
    /// into the drawn checkmark before the existing reverse morph begins.
    static let saveAcknowledgementDuration: TimeInterval = 0.44
}

enum TaskCreationMountTiming {
    static let fadeDuration: TimeInterval = 0.16
    static let layoutDuration: TimeInterval = 0.22
    static let reducedMotionFadeDuration: TimeInterval = 0.12
    static let reducedMotionLayoutDuration: TimeInterval = 0.12
    static let removalLayoutDuration = TaskExpansionMotionTiming.collapseDuration
    static let removalFadeDuration: TimeInterval = 0.12
    static let removalFadeDelay: TimeInterval = 0.20
    static let reducedMotionRemovalLayoutDuration = TaskExpansionMotionTiming.reducedMotionDuration
    static let reducedMotionRemovalFadeDuration: TimeInterval = 0.12
    static let reducedMotionRemovalFadeDelay: TimeInterval = 0.10
}

struct TaskCreationExpansionReserve: View {
    let expandedHeightDelta: CGFloat
    let expansionProgress: CGFloat

    var body: some View {
        Color.clear
            .frame(height: Self.height(
                expandedHeightDelta: expandedHeightDelta,
                expansionProgress: expansionProgress
            ))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static func height(
        expandedHeightDelta: CGFloat,
        expansionProgress: CGFloat
    ) -> CGFloat {
        max(0, expandedHeightDelta) * (1 - min(max(expansionProgress, 0), 1))
    }
}

enum TaskCreationKeyboardLayout {
    /// Keeps the action row visually separate from the software keyboard while
    /// still reading as one continuous editing surface.
    static let bottomClearance: CGFloat = 10
}

enum TaskMorphCascadeTiming {
    /// Detail rows may enter while the identity is moving, but the first row
    /// must not settle before the identity reaches its 460ms endpoint.
    static let expansionDelay: TimeInterval = 0.30
    static let timelineDuration: TimeInterval = 0.40
    static let rowDuration: TimeInterval = 0.18
    static let rowDelay: TimeInterval = 0.05
    static let maximumTotalDelay: TimeInterval = 0.22
    static let collapseRowDuration: TimeInterval = 0.19
    static let collapseRowDelay: TimeInterval = 0.03
    static let maximumCollapseTotalDelay: TimeInterval = 0.12
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
    /// Keep each row's compositor-only movement shorter than the identity
    /// motion so adjacent delays remain visually legible as an outward wave.
    static let expansionDuration: TimeInterval = 0.36
    static let lightUniformRadius: CGFloat = 0.8
    static let darkUniformRadius: CGFloat = 1.45
    static let adjacentScale: CGFloat = 0.95
    static let scaleStep: CGFloat = 0.03
    static let minimumScale: CGFloat = 0.87
    static let lowerAdjacentScale: CGFloat = 0.95
    static let lowerScaleStep: CGFloat = 0.025
    static let lowerMinimumScale: CGFloat = 0.88
    static let lightUniformOpacity: CGFloat = 0.52
    static let darkUniformOpacity: CGFloat = 0.49
    static let upperAdjacentOffset: CGFloat = 8
    static let upperOffsetStep: CGFloat = 4
    static let upperMaximumOffset: CGFloat = 24
    static let lowerAdjacentOffset: CGFloat = 12
    static let lowerOffsetStep: CGFloat = 6
    static let lowerMaximumOffset: CGFloat = 36
    static let upperInitialDelay: TimeInterval = 0.015
    static let upperRowDelay: TimeInterval = 0.06
    static let upperMaximumDelay: TimeInterval = 0.26
    static let lowerInitialDelay: TimeInterval = 0.02
    static let lowerRowDelay: TimeInterval = 0.075
    static let lowerMaximumDelay: TimeInterval = 0.34
    static let lightHeaderBlurRadius: CGFloat = lightUniformRadius
    static let darkHeaderBlurRadius: CGFloat = 0.5
    static let headerScale: CGFloat = 0.98
    static let headerOpacity: CGFloat = 0.52

    static func radius(forTaskDelta delta: Int?, isDarkAppearance: Bool) -> CGFloat {
        guard let distance = delta.map(abs), distance > 0 else { return 0 }
        return isDarkAppearance ? darkUniformRadius : lightUniformRadius
    }

    static func scale(forTaskDelta delta: Int?) -> CGFloat {
        guard let distance = delta.map(abs), distance > 0 else { return 1 }
        if let delta, delta > 0 {
            return max(
                lowerMinimumScale,
                lowerAdjacentScale - CGFloat(distance - 1) * lowerScaleStep
            )
        }
        return max(
            minimumScale,
            adjacentScale - CGFloat(distance - 1) * scaleStep
        )
    }

    static func opacity(forTaskDelta delta: Int?, isDarkAppearance: Bool) -> CGFloat {
        guard let distance = delta.map(abs), distance > 0 else {
            return isDarkAppearance
                ? TaskMorphSurfaceMetrics.detailFallbackBackgroundOpacity
                : lightUniformOpacity
        }
        return isDarkAppearance ? darkUniformOpacity : lightUniformOpacity
    }

    static func headerBlurRadius(isDarkAppearance: Bool) -> CGFloat {
        isDarkAppearance ? darkHeaderBlurRadius : lightHeaderBlurRadius
    }

    static func offsetY(forTaskDelta delta: Int?) -> CGFloat {
        guard let delta, delta != 0 else { return 0 }
        if delta < 0 {
            let magnitude = min(
                upperMaximumOffset,
                upperAdjacentOffset + CGFloat(abs(delta) - 1) * upperOffsetStep
            )
            return -magnitude
        }
        return min(
            lowerMaximumOffset,
            lowerAdjacentOffset + CGFloat(delta - 1) * lowerOffsetStep
        )
    }

    static func delay(forTaskDelta delta: Int?) -> TimeInterval {
        guard let delta, delta != 0 else { return 0 }
        if delta < 0 {
            return min(
                upperMaximumDelay,
                upperInitialDelay + Double(abs(delta) - 1) * upperRowDelay
            )
        }
        return min(
            lowerMaximumDelay,
            lowerInitialDelay + Double(delta - 1) * lowerRowDelay
        )
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
            return resolve(progress: reducedProgress, reduceMotion: true)
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

        return resolve(progress: progress, reduceMotion: false)
    }

    static func resolve(
        progress rawProgress: CGFloat,
        reduceMotion: Bool
    ) -> TaskMorphCascadeValues {
        let progress = min(max(rawProgress, 0), 1)
        let offset = reduceMotion ? CGSize.zero : waveOffset(progress: progress)
        let opacityProgress = reduceMotion ? progress : smoothStep(progress)
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

enum TaskMorphFocusFieldStyle {
    case adaptivePrimary
    case subtleLight
}

struct TaskMorphContainer<Content: View>: View {
    let state: TaskMorphVisualState
    let isActive: Bool
    var isBackgroundDeemphasized = false
    var backgroundFocusDelta: Int? = nil
    var focusFieldStyle: TaskMorphFocusFieldStyle = .adaptivePrimary
    var onBackgroundTap: (() -> Void)? = nil
    @ViewBuilder let content: (TaskExpansionMotion) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        KeyframeAnimator(
            initialValue: TaskExpansionMotion.compact,
            trigger: motionTarget
        ) { motion in
            VStack(alignment: .leading, spacing: 0) {
                content(motion)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                LinearGradient(
                    colors: [
                        .clear,
                        focusFieldColor,
                        focusFieldColor,
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.horizontal, -28)
                .padding(.vertical, -52)
                .opacity(isFocusFieldVisible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .overlay {
                if isBackgroundDeemphasized, let onBackgroundTap {
                    Button(action: onBackgroundTap) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收起任务详情")
                    .accessibilityHint("结束当前输入或收起任务详情")
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
                    CubicKeyframe(0, duration: 0.18)
                } else {
                    LinearKeyframe(0, duration: 0.12)
                    CubicKeyframe(1, duration: 0.20)
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
                    CubicKeyframe(0, duration: 0.18)
                } else {
                    LinearKeyframe(0, duration: 0.12)
                    CubicKeyframe(1, duration: 0.20)
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
        .animation(focusFieldAnimation, value: isFocusFieldVisible)
        .animation(detailBackgroundDepthAnimation, value: backgroundWaveTarget)
    }

    private var motionTarget: TaskExpansionMotionTarget {
        TaskExpansionMotionTarget(
            isExpanded: isActive && state == .expanded,
            reduceMotion: reduceMotion
        )
    }

    private var isForegroundElevated: Bool {
        reduceMotion == false && motionTarget.isExpanded
    }

    private var isFocusFieldVisible: Bool {
        motionTarget.isExpanded
    }

    private var detailBackgroundDepthOpacity: CGFloat {
        guard isBackgroundDeemphasized else { return 1 }
        if colorSchemeContrast == .increased {
            return reduceMotion ? 0.75 : 0.65
        }
        return reduceMotion
            ? TaskMorphSurfaceMetrics.reducedMotionDetailBackgroundOpacity
            : TaskMorphBackgroundWave.opacity(
                forTaskDelta: backgroundFocusDelta,
                isDarkAppearance: colorScheme == .dark
            )
    }

    private var focusFieldColor: Color {
        switch focusFieldStyle {
        case .adaptivePrimary:
            if colorScheme == .dark {
                Color.primary.opacity(0.025)
            } else {
                Color.white.opacity(lightFocusOverlayOpacity)
            }
        case .subtleLight:
            Color.white.opacity(colorScheme == .dark ? 0.025 : lightFocusOverlayOpacity)
        }
    }

    private var lightFocusOverlayOpacity: CGFloat {
        colorSchemeContrast == .increased
            ? TaskMorphFocusField.increasedContrastLightOverlayOpacity
            : TaskMorphFocusField.lightOverlayOpacity
    }

    private var detailBackgroundBlurRadius: CGFloat {
        guard isBackgroundDeemphasized, reduceMotion == false else { return 0 }
        return TaskMorphBackgroundWave.radius(
            forTaskDelta: backgroundFocusDelta,
            isDarkAppearance: colorScheme == .dark
        )
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
                ? TaskMorphBackgroundWave.expansionDuration
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

    private var focusFieldAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: TaskExpansionMotionTiming.reducedMotionDuration)
        }
        return .timingCurve(
            0.20,
            0,
            0.16,
            1,
            duration: isFocusFieldVisible
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let usesDetailHeaderDepth = isDeemphasized
            && appliesVisualDepth == false
            && detailBlurRadius > 0
            && reduceMotion == false

        content
            .allowsHitTesting(isDeemphasized == false)
            .accessibilityHidden(isDeemphasized)
            .scaleEffect(
                usesDetailHeaderDepth
                    ? TaskMorphBackgroundWave.headerScale
                    : reduceMotion || isDeemphasized == false || scalesContent == false || appliesVisualDepth == false
                        ? 1
                        : TaskMorphSurfaceMetrics.backgroundContentScale,
                anchor: anchor
            )
            .opacity(
                isDeemphasized && appliesVisualDepth
                    ? TaskMorphSurfaceMetrics.backgroundContentOpacity
                    : usesDetailHeaderDepth
                        ? colorSchemeContrast == .increased
                            ? 0.65
                            : TaskMorphBackgroundWave.headerOpacity
                        : 1
            )
            .brightness(
                isDeemphasized && appliesVisualDepth
                    ? (colorScheme == .dark ? -0.06 : 0)
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
                    .accessibilityHint("结束当前输入或收起任务详情")
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

    func taskCreationMountTransition(
        isCreationDraft: Bool,
        isDiscarding: Bool
    ) -> some View {
        modifier(
            TaskCreationMountTransitionModifier(
                isCreationDraft: isCreationDraft,
                isDiscarding: isDiscarding
            )
        )
    }
}

private struct TaskCreationMountTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isCreationDraft: Bool
    let isDiscarding: Bool

    @State private var naturalHeight: CGFloat = 0
    @State private var layoutProgress: CGFloat = 0
    @State private var opacityProgress: Double = 0
    @State private var isLayoutSettled = false
    @State private var hasStarted = false
    @State private var hasStartedDiscard = false
    @State private var mountTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCreationDraft {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    guard naturalHeight == 0,
                          height.isFinite,
                          height > 0
                    else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        naturalHeight = height
                    }
                    startIfReady()
                    startDiscardIfReady()
                }
                .frame(
                    height: isLayoutSettled ? nil : naturalHeight * layoutProgress,
                    alignment: .top
                )
                .modifier(
                    TaskMorphConditionalClipModifier(
                        progress: isLayoutSettled ? 1 : layoutProgress
                    )
                )
                .opacity(opacityProgress)
                .onAppear {
                    startIfReady()
                    startDiscardIfReady()
                }
                .onChange(of: isDiscarding) { _, isDiscarding in
                    guard isDiscarding else { return }
                    startDiscardIfReady()
                }
                .onDisappear {
                    mountTask?.cancel()
                    mountTask = nil
                }
        } else {
            content
        }
    }

    private var layoutAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: TaskCreationMountTiming.reducedMotionLayoutDuration)
            : .smooth(duration: TaskCreationMountTiming.layoutDuration, extraBounce: 0)
    }

    private var fadeAnimation: Animation {
        .easeOut(
            duration: reduceMotion
                ? TaskCreationMountTiming.reducedMotionFadeDuration
                : TaskCreationMountTiming.fadeDuration
        )
    }

    private var removalLayoutAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: TaskCreationMountTiming.reducedMotionRemovalLayoutDuration)
            : .smooth(duration: TaskCreationMountTiming.removalLayoutDuration, extraBounce: 0)
    }

    private var removalFadeAnimation: Animation {
        let duration = reduceMotion
            ? TaskCreationMountTiming.reducedMotionRemovalFadeDuration
            : TaskCreationMountTiming.removalFadeDuration
        let delay = reduceMotion
            ? TaskCreationMountTiming.reducedMotionRemovalFadeDelay
            : TaskCreationMountTiming.removalFadeDelay
        return .easeIn(duration: duration).delay(delay)
    }

    private func startIfReady() {
        guard isCreationDraft,
              isDiscarding == false,
              naturalHeight > 0,
              hasStarted == false
        else { return }

        hasStarted = true
        mountTask?.cancel()
        mountTask = Task { @MainActor in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            withAnimation(fadeAnimation) {
                opacityProgress = 1
            }
            withAnimation(
                layoutAnimation,
                completionCriteria: .logicallyComplete
            ) {
                layoutProgress = 1
            } completion: {
                guard Task.isCancelled == false else { return }
                isLayoutSettled = true
                mountTask = nil
            }
        }
    }

    private func startDiscardIfReady() {
        guard isCreationDraft,
              isDiscarding,
              naturalHeight > 0,
              hasStartedDiscard == false
        else { return }

        hasStartedDiscard = true
        mountTask?.cancel()
        mountTask = nil

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isLayoutSettled = false
        }

        withAnimation(removalLayoutAnimation) {
            layoutProgress = 0
        }
        withAnimation(removalFadeAnimation) {
            opacityProgress = 0
        }
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
