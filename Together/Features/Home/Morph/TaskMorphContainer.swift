import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum TaskMorphSurfaceMetrics {
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 16
    static let detailHorizontalInset: CGFloat = 28
    static let detailTopInset: CGFloat = 18
    static let detailBottomInset: CGFloat = 20
    static let expandedScreenEdgeInset: CGFloat = 6
    static let expandedCornerRadius = AppTheme.radius.xl
    static let detailExpandedCornerRadius: CGFloat = 45
    static let compactCornerRadius = AppTheme.radius.lg
    static let expandedContentScale: CGFloat = 1.05
    static let backgroundContentScale: CGFloat = 0.94
    static let backgroundContentOpacity: CGFloat = 0.62
}

enum TaskMorphBloomMotion {
    static let geometryDuration: TimeInterval = 0.35
    static let reducedMotionDuration: TimeInterval = 0.14
    static let boundaryOvershootDuration: TimeInterval = 0.38
    static let boundaryOvershootDelay: Duration = .milliseconds(380)
    static let boundarySettleDuration: TimeInterval = 0.14
    static let boundaryHorizontalOutset: CGFloat = 4
    static let boundaryBottomOutset: CGFloat = 12
    static let boundaryCornerRadius: CGFloat = 45
    static let boundaryOvershootShadowRadius: CGFloat = 18
    static let boundarySettledShadowRadius: CGFloat = 16
    static let boundaryOvershootShadowOffsetY: CGFloat = 8
    static let boundarySettledShadowOffsetY: CGFloat = 7

    static func geometryAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: reducedMotionDuration)
            : .smooth(duration: geometryDuration, extraBounce: 0)
    }

    static func horizontalProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress / 0.72, 0), 1)
    }

    static func verticalProgress(_ progress: CGFloat) -> CGFloat {
        min(max((progress - 0.06) / 0.94, 0), 1)
    }

    static func interpolate(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * min(max(progress, 0), 1)
    }

    static func boundaryPresentation(
        for phase: TaskMorphBoundaryPhase
    ) -> TaskMorphBoundaryPresentation {
        switch phase {
        case .compact:
            TaskMorphBoundaryPresentation(
                opacity: 0,
                horizontalOutset: 0,
                bottomOutset: 0,
                cornerRadius: boundaryCornerRadius,
                shadowRadius: 0,
                shadowOffsetY: 0
            )
        case .overshot:
            TaskMorphBoundaryPresentation(
                opacity: 1,
                horizontalOutset: boundaryHorizontalOutset,
                bottomOutset: boundaryBottomOutset,
                cornerRadius: boundaryCornerRadius,
                shadowRadius: boundaryOvershootShadowRadius,
                shadowOffsetY: boundaryOvershootShadowOffsetY
            )
        case .settled:
            TaskMorphBoundaryPresentation(
                opacity: 1,
                horizontalOutset: 0,
                bottomOutset: 0,
                cornerRadius: boundaryCornerRadius,
                shadowRadius: boundarySettledShadowRadius,
                shadowOffsetY: boundarySettledShadowOffsetY
            )
        }
    }
}

enum TaskMorphBoundaryPhase: Equatable, Sendable {
    case compact
    case overshot
    case settled
}

struct TaskMorphBoundaryPresentation: Equatable, Sendable {
    let opacity: Double
    let horizontalOutset: CGFloat
    let bottomOutset: CGFloat
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowOffsetY: CGFloat
}

enum TaskMorphListSpacing {
    /// Real empty space added outside the active card boundary. Because this is
    /// list-owned padding, it contributes to LazyVStack row height and reverses
    /// with the same transaction as the disclosure instead of faking movement
    /// with offsets on neighboring rows.
    static let expandedExternalSeparation: CGFloat = 8

    /// Vertical growth outside the disclosure itself: asymmetric internal card
    /// insets plus the two real external separation gaps.
    static var fixedExpansionHeightDelta: CGFloat {
        TaskMorphSurfaceMetrics.detailTopInset
            + TaskMorphSurfaceMetrics.detailBottomInset
            + 2 * expandedExternalSeparation
    }

    static func expandedInsets(from compactInsets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: compactInsets.top + expandedExternalSeparation,
            leading: min(compactInsets.leading, TaskMorphSurfaceMetrics.expandedScreenEdgeInset),
            bottom: compactInsets.bottom + expandedExternalSeparation,
            trailing: min(compactInsets.trailing, TaskMorphSurfaceMetrics.expandedScreenEdgeInset)
        )
    }
}

enum TaskMorphExpansionComponent: Hashable {
    case primary
    case footer
}

struct TaskMorphScrollSnapshot: Equatable {
    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    init(_ geometry: ScrollGeometry) {
        contentOffsetY = geometry.contentOffset.y
        contentHeight = geometry.contentSize.height
        containerHeight = geometry.containerSize.height
        topInset = geometry.contentInsets.top
        bottomInset = geometry.contentInsets.bottom
    }
}

enum TaskMorphViewportMotion {
    static let upwardShare: CGFloat = 0.4

    static func maximumUpwardDisplacement(
        heightDelta: CGFloat,
        availableAbove: CGFloat
    ) -> CGFloat {
        min(max(0, heightDelta) * upwardShare, max(0, availableAbove))
    }

    static func screenDisplacements(
        heightDelta: CGFloat,
        upwardDisplacement: CGFloat
    ) -> (above: CGFloat, below: CGFloat) {
        let upward = min(max(0, upwardDisplacement), max(0, heightDelta))
        return (above: upward, below: max(0, heightDelta - upward))
    }
}

/// Keeps the expanded row in the real lazy stack while sharing its height delta
/// between the content above and below through a real ScrollView content offset.
/// Geometry samples live in a non-observable reference: they are read only at
/// state boundaries and must not invalidate the list on every scroll frame.
@MainActor
final class TaskMorphViewportCoordinator {
    private enum MotionDirection {
        case expanding
        case collapsing
    }

    private var scrollSnapshot: TaskMorphScrollSnapshot?
    private var viewportFrame: CGRect = .zero
    private var rowFrames: [UUID: CGRect] = [:]
    private var measuredHeights: [UUID: [TaskMorphExpansionComponent: CGFloat]] = [:]
    private var activeID: UUID?
    private var maximumUpwardDisplacement: CGFloat = 0
    private var currentUpwardDisplacement: CGFloat = 0
    private var openingOffsetY: CGFloat = 0
    private var collapseOffsetY: CGFloat = 0
    private var collapseStartingDisplacement: CGFloat = 0
    private var lastProgress: CGFloat = 0
    private var motionDirection: MotionDirection = .expanding
#if canImport(UIKit)
    private weak var scrollView: UIScrollView?
    private var scrollViewToken: UUID?
#endif

    func recordScrollSnapshot(_ snapshot: TaskMorphScrollSnapshot) {
        scrollSnapshot = snapshot
    }

    func recordViewportFrame(_ frame: CGRect) {
        guard Self.isValid(frame) else { return }
        viewportFrame = frame
    }

    func recordRowFrame(_ frame: CGRect, for id: UUID) {
        guard Self.isValid(frame) else { return }
        rowFrames[id] = frame
    }

    func isFrameVisible(_ frame: CGRect) -> Bool {
        Self.isValid(viewportFrame)
            && Self.isValid(frame)
            && viewportFrame.intersects(frame)
    }

#if canImport(UIKit)
    func installScrollView(_ scrollView: UIScrollView, token: UUID) {
        self.scrollView = scrollView
        scrollViewToken = token
        if let activeID {
            applyExpansionProgress(lastProgress, for: activeID, forcesOffsetWrite: true)
        }
    }

    func removeScrollView(token: UUID) {
        guard scrollViewToken == token else { return }
        scrollView = nil
        scrollViewToken = nil
    }
#endif

    func recordExpansionHeight(
        _ height: CGFloat,
        for id: UUID,
        component: TaskMorphExpansionComponent = .primary
    ) {
        guard height.isFinite, height > 0 else { return }
        measuredHeights[id, default: [:]][component] = height
    }

    /// Freezes compact geometry before the shared SwiftUI transaction starts.
    /// Subsequent viewport writes are derived from the explicit presentation
    /// progress rather than inferred from post-layout geometry callbacks.
    func beginExpansion(
        for id: UUID,
        estimatedHeightDelta: CGFloat,
        protectedTopInset: CGFloat = 52
    ) {
        activeID = id
        currentUpwardDisplacement = 0
        lastProgress = 0
        motionDirection = .expanding

        guard let scrollSnapshot,
              let rowFrame = rowFrames[id],
              Self.isValid(viewportFrame)
        else {
            maximumUpwardDisplacement = 0
            return
        }

        let measuredHeight = measuredHeights[id]?.values.reduce(0, +) ?? 0
        let disclosureHeightDelta = max(estimatedHeightDelta, measuredHeight)
        let heightDelta = disclosureHeightDelta + TaskMorphListSpacing.fixedExpansionHeightDelta
        guard heightDelta > 1 else {
            maximumUpwardDisplacement = 0
            return
        }

        // Keep the selected row below the stable top chrome zone. Within
        // that constraint, assign roughly two fifths of the new height upward.
        let protectedTop = viewportFrame.minY + max(0, protectedTopInset)
        let availableAbove = max(0, rowFrame.minY - protectedTop)
        maximumUpwardDisplacement = TaskMorphViewportMotion.maximumUpwardDisplacement(
            heightDelta: heightDelta,
            availableAbove: availableAbove
        )
        openingOffsetY = liveContentOffsetY ?? scrollSnapshot.contentOffsetY
    }

    /// Freezes the user's current offset before the row starts shrinking. The
    /// following per-frame corrections therefore remove only Morph-owned travel.
    func beginCollapse(for id: UUID) {
        guard activeID == id else { return }
        guard motionDirection != .collapsing else { return }
        motionDirection = .collapsing
        collapseOffsetY = liveContentOffsetY ?? scrollSnapshot?.contentOffsetY ?? openingOffsetY
        collapseStartingDisplacement = currentUpwardDisplacement
    }

    /// Retargets an in-flight collapse back toward expansion while preserving
    /// the current on-screen offset as the new presentation baseline. This also
    /// lets a later collapse re-freeze any scrolling performed after reversal.
    func resumeExpansion(for id: UUID) {
        guard activeID == id else { return }
        let liveOffset = liveContentOffsetY ?? openingOffsetY + currentUpwardDisplacement
        openingOffsetY = liveOffset - currentUpwardDisplacement
        motionDirection = .expanding
    }

    /// Receives the active row's explicit presentation progress. The same SwiftUI
    /// transaction drives the real row height while this method writes the
    /// underlying UIScrollView offset directly, avoiding a second declarative
    /// scroll animation or a list-wide observable progress broadcast.
    func applyExpansionProgress(_ progress: CGFloat, for id: UUID) {
        applyExpansionProgress(progress, for: id, forcesOffsetWrite: false)
    }

    private func applyExpansionProgress(
        _ progress: CGFloat,
        for id: UUID,
        forcesOffsetWrite: Bool
    ) {
        let progress = min(max(progress, 0), 1)
        guard activeID == id,
              let scrollSnapshot,
              maximumUpwardDisplacement > 0.5
        else { return }

        lastProgress = progress

        let desiredDisplacement = maximumUpwardDisplacement * progress
        guard forcesOffsetWrite || abs(desiredDisplacement - currentUpwardDisplacement) > 0.2 else {
            return
        }

        let unboundedTarget: CGFloat
        switch motionDirection {
        case .expanding:
            unboundedTarget = openingOffsetY + desiredDisplacement
        case .collapsing:
            unboundedTarget = collapseOffsetY
                + desiredDisplacement
                - collapseStartingDisplacement
        }

        let minimumOffset = -scrollSnapshot.topInset
        let targetOffset = max(unboundedTarget, minimumOffset)
        guard applyScrollOffset(targetOffset) else { return }

        switch motionDirection {
        case .expanding:
            currentUpwardDisplacement = max(0, targetOffset - openingOffsetY)
        case .collapsing:
            currentUpwardDisplacement = min(
                maximumUpwardDisplacement,
                max(0, collapseStartingDisplacement + targetOffset - collapseOffsetY)
            )
        }
    }

    func cancelExpansion(for id: UUID) {
        guard activeID == id else { return }
        reset()
    }

    func reset() {
        activeID = nil
        maximumUpwardDisplacement = 0
        currentUpwardDisplacement = 0
        openingOffsetY = 0
        collapseOffsetY = 0
        collapseStartingDisplacement = 0
        lastProgress = 0
        motionDirection = .expanding
    }

    private func applyScrollOffset(_ targetOffset: CGFloat) -> Bool {
#if canImport(UIKit)
        guard let scrollView else { return false }
        let point = CGPoint(x: scrollView.contentOffset.x, y: targetOffset)
        guard abs(point.y - scrollView.contentOffset.y) > 0.2 else { return true }
        UIView.performWithoutAnimation {
            scrollView.setContentOffset(point, animated: false)
        }
        return true
#else
        return false
#endif
    }

    private var liveContentOffsetY: CGFloat? {
#if canImport(UIKit)
        scrollView?.contentOffset.y
#else
        nil
#endif
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}

private struct TaskMorphScrollViewportModifier: ViewModifier {
    let coordinator: TaskMorphViewportCoordinator

    func body(content: Content) -> some View {
        content
            .background {
#if canImport(UIKit)
                TaskMorphScrollViewResolver(coordinator: coordinator)
                    .frame(width: 0, height: 0)
#endif
            }
    }
}

#if canImport(UIKit)
private struct TaskMorphScrollViewResolver: UIViewRepresentable {
    let coordinator: TaskMorphViewportCoordinator

    func makeUIView(context: Context) -> ResolverView {
        ResolverView(coordinator: coordinator)
    }

    func updateUIView(_ view: ResolverView, context: Context) {
        view.coordinator = coordinator
        view.resolveScrollViewIfNeeded()
    }

    static func dismantleUIView(_ view: ResolverView, coordinator: ()) {
        view.disconnect()
    }

    @MainActor
    final class ResolverView: UIView {
        weak var coordinator: TaskMorphViewportCoordinator?
        private let token = UUID()
        private weak var resolvedScrollView: UIScrollView?

        init(coordinator: TaskMorphViewportCoordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            resolveScrollViewIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolveScrollViewIfNeeded()
        }

        func resolveScrollViewIfNeeded() {
            guard resolvedScrollView == nil else { return }
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? UIScrollView {
                    resolvedScrollView = scrollView
                    coordinator?.installScrollView(scrollView, token: token)
                    return
                }
                candidate = view.superview
            }
        }

        func disconnect() {
            coordinator?.removeScrollView(token: token)
            resolvedScrollView = nil
        }
    }
}
#endif

@MainActor
private struct TaskMorphViewportProgressModifier: AnimatableModifier {
    var progress: CGFloat
    let id: UUID
    let coordinator: TaskMorphViewportCoordinator

    var animatableData: CGFloat {
        get { progress }
        set {
            progress = newValue
            coordinator.applyExpansionProgress(
                TaskMorphBloomMotion.verticalProgress(newValue),
                for: id
            )
        }
    }

    func body(content: Content) -> some View {
        content
    }
}

struct TaskMorphContainer<Content: View>: View {
    let state: TaskMorphVisualState
    let isActive: Bool
    let hidesRealSurfaceForHero: Bool
    var isBackgroundDeemphasized = false
    var isBackgroundDimmed = false
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .modifier(
            TaskMorphBloomSurfaceModifier(
                progress: usesExpandedGeometry ? 1 : 0,
                isExpandedTarget: usesExpandedGeometry,
                reduceMotion: reduceMotion
            )
        )
        .scaleEffect(backgroundContentScale)
        .brightness(backgroundBrightness)
        .opacity(hidesRealSurfaceForHero ? 0 : backgroundContentOpacity * backgroundDimOpacity)
        .accessibilityElement(children: .contain)
    }

    private var usesExpandedGeometry: Bool {
        isActive && state != .compact
    }

    private var backgroundContentScale: CGFloat {
        guard reduceMotion == false, isBackgroundDeemphasized else { return 1 }
        return TaskMorphSurfaceMetrics.backgroundContentScale
    }

    private var backgroundContentOpacity: CGFloat {
        isBackgroundDeemphasized
            ? TaskMorphSurfaceMetrics.backgroundContentOpacity
            : 1
    }

    private var backgroundBrightness: Double {
        guard isBackgroundDeemphasized || isBackgroundDimmed else { return 0 }
        return colorScheme == .dark ? -0.06 : -0.10
    }

    private var backgroundDimOpacity: CGFloat {
        isBackgroundDimmed ? 0.78 : 1
    }

}

private struct TaskMorphBloomSurfaceModifier: AnimatableModifier {
    var progress: CGFloat
    let isExpandedTarget: Bool
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        TaskMorphBloomSurfaceBody(
            content: content,
            progress: progress,
            isExpandedTarget: isExpandedTarget,
            reduceMotion: reduceMotion
        )
    }
}

private struct TaskMorphBloomSurfaceBody<Content: View>: View {
    let content: Content
    let progress: CGFloat
    let isExpandedTarget: Bool
    let reduceMotion: Bool

    @State private var boundaryPhase: TaskMorphBoundaryPhase
    @State private var settleTask: Task<Void, Never>?

    init(
        content: Content,
        progress: CGFloat,
        isExpandedTarget: Bool,
        reduceMotion: Bool
    ) {
        self.content = content
        self.progress = progress
        self.isExpandedTarget = isExpandedTarget
        self.reduceMotion = reduceMotion
        _boundaryPhase = State(initialValue: isExpandedTarget ? .settled : .compact)
    }

    var body: some View {
        let horizontalProgress = TaskMorphBloomMotion.horizontalProgress(progress)
        let verticalProgress = TaskMorphBloomMotion.verticalProgress(progress)
        let boundary = TaskMorphBloomMotion.boundaryPresentation(for: boundaryPhase)
        let contentScale = reduceMotion
            ? 1
            : TaskMorphBloomMotion.interpolate(
                1,
                TaskMorphSurfaceMetrics.expandedContentScale,
                progress: verticalProgress
            )

        content
            .scaleEffect(x: contentScale, y: contentScale, anchor: .top)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(
                .horizontal,
                TaskMorphSurfaceMetrics.detailHorizontalInset * horizontalProgress
            )
            .padding(
                EdgeInsets(
                    top: TaskMorphSurfaceMetrics.detailTopInset * verticalProgress,
                    leading: 0,
                    bottom: TaskMorphSurfaceMetrics.detailBottomInset * verticalProgress,
                    trailing: 0
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: progress > 0 ? TaskMorphBloomMotion.boundaryCornerRadius : 0,
                    style: .continuous
                )
            )
            .background(alignment: .top) {
                TaskMorphBloomBoundaryLayer(
                    presentation: boundary
                )
                .padding(.horizontal, -boundary.horizontalOutset)
                .padding(.bottom, -boundary.bottomOutset)
            }
            .onChange(of: animationTarget) { _, target in
                updateBoundary(for: target)
            }
            .onDisappear {
                settleTask?.cancel()
                settleTask = nil
            }
    }

    private var animationTarget: TaskMorphBoundaryTarget {
        TaskMorphBoundaryTarget(
            isExpanded: isExpandedTarget,
            reduceMotion: reduceMotion
        )
    }

    private func updateBoundary(for target: TaskMorphBoundaryTarget) {
        settleTask?.cancel()
        settleTask = nil

        guard target.isExpanded else {
            withAnimation(
                target.reduceMotion
                    ? .easeInOut(duration: TaskMorphBloomMotion.reducedMotionDuration)
                    : .smooth(duration: TaskMorphBloomMotion.geometryDuration, extraBounce: 0)
            ) {
                boundaryPhase = .compact
            }
            return
        }

        guard target.reduceMotion == false else {
            withAnimation(
                .easeInOut(duration: TaskMorphBloomMotion.reducedMotionDuration)
            ) {
                boundaryPhase = .settled
            }
            return
        }

        withAnimation(
            .smooth(
                duration: TaskMorphBloomMotion.boundaryOvershootDuration,
                extraBounce: 0
            )
        ) {
            boundaryPhase = .overshot
        }

        settleTask = Task { @MainActor in
            try? await Task.sleep(for: TaskMorphBloomMotion.boundaryOvershootDelay)
            guard Task.isCancelled == false else { return }
            withAnimation(
                .spring(
                    duration: TaskMorphBloomMotion.boundarySettleDuration,
                    bounce: 0
                )
            ) {
                boundaryPhase = .settled
            }
        }
    }
}

private struct TaskMorphBloomBoundaryLayer: View {
    let presentation: TaskMorphBoundaryPresentation

    var body: some View {
        RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous)
            .fill(AppTheme.colors.surface)
            .overlay {
                RoundedRectangle(cornerRadius: presentation.cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.colors.body.opacity(0.06), lineWidth: 0.5)
            }
            .opacity(presentation.opacity)
            .shadow(
                color: presentation.opacity > 0 ? Color.black.opacity(0.14) : .clear,
                radius: presentation.shadowRadius,
                y: presentation.shadowOffsetY
            )
    }
}

private struct TaskMorphBoundaryTarget: Equatable {
    let isExpanded: Bool
    let reduceMotion: Bool
}

private struct TaskMorphBackgroundDepthModifier: ViewModifier {
    let isDeemphasized: Bool
    let anchor: UnitPoint
    let scalesContent: Bool
    let actsAsDismissTarget: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isDeemphasized == false)
            .accessibilityHidden(isDeemphasized)
            .scaleEffect(
                reduceMotion || isDeemphasized == false || scalesContent == false
                    ? 1
                    : TaskMorphSurfaceMetrics.backgroundContentScale,
                anchor: anchor
            )
            .opacity(
                isDeemphasized
                    ? TaskMorphSurfaceMetrics.backgroundContentOpacity
                    : 1
            )
            .brightness(
                isDeemphasized
                    ? (colorScheme == .dark ? -0.06 : -0.10)
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
    }
}

extension View {
    /// Applies the same compositor-only depth treatment as inactive task rows
    /// and temporarily converts the visible surface into a dismissal target.
    func taskMorphBackgroundDepth(
        isDeemphasized: Bool,
        anchor: UnitPoint = .center,
        scalesContent: Bool = true,
        actsAsDismissTarget: Bool = true,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(
            TaskMorphBackgroundDepthModifier(
                isDeemphasized: isDeemphasized,
                anchor: anchor,
                scalesContent: scalesContent,
                actsAsDismissTarget: actsAsDismissTarget,
                onDismiss: onDismiss
            )
        )
    }
}

struct TaskMorphDisclosure<Content: View>: View {
    let isExpanded: Bool
    let estimatedHeight: CGFloat
    let onMeasuredHeight: ((CGFloat) -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var measuredHeight: CGFloat = 0

    init(
        isExpanded: Bool,
        estimatedHeight: CGFloat = 0,
        onMeasuredHeight: ((CGFloat) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isExpanded = isExpanded
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
                    progress: isExpanded ? 1 : 0,
                    expandedHeight: resolvedExpandedHeight
                )
            )
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(isExpanded == false)
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
                height: expandedHeight * TaskMorphBloomMotion.verticalProgress(progress),
                alignment: .top
            )
            .clipped()
    }
}

private struct TaskMorphListPlacementModifier: AnimatableModifier {
    var progress: CGFloat
    let compactInsets: EdgeInsets

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .padding(adjustedInsets)
    }

    private var adjustedInsets: EdgeInsets {
        let expanded = TaskMorphListSpacing.expandedInsets(from: compactInsets)
        let horizontalProgress = TaskMorphBloomMotion.horizontalProgress(progress)
        let verticalProgress = TaskMorphBloomMotion.verticalProgress(progress)
        return EdgeInsets(
            top: TaskMorphBloomMotion.interpolate(
                compactInsets.top,
                expanded.top,
                progress: verticalProgress
            ),
            leading: TaskMorphBloomMotion.interpolate(
                compactInsets.leading,
                expanded.leading,
                progress: horizontalProgress
            ),
            bottom: TaskMorphBloomMotion.interpolate(
                compactInsets.bottom,
                expanded.bottom,
                progress: verticalProgress
            ),
            trailing: TaskMorphBloomMotion.interpolate(
                compactInsets.trailing,
                expanded.trailing,
                progress: horizontalProgress
            )
        )
    }
}

extension View {
    func taskMorphScrollViewport(
        coordinator: TaskMorphViewportCoordinator
    ) -> some View {
        modifier(TaskMorphScrollViewportModifier(coordinator: coordinator))
    }

    func taskMorphViewportProgress(
        _ progress: CGFloat,
        id: UUID,
        coordinator: TaskMorphViewportCoordinator
    ) -> some View {
        modifier(
            TaskMorphViewportProgressModifier(
                progress: progress,
                id: id,
                coordinator: coordinator
            )
        )
    }

    func taskMorphListPlacement(
        state: TaskMorphVisualState,
        isActive: Bool,
        compactInsets: EdgeInsets
    ) -> some View {
        modifier(
            TaskMorphListPlacementModifier(
                progress: isActive && state != .compact ? 1 : 0,
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
