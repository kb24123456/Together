import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum TaskMorphSurfaceMetrics {
    static let horizontalInset: CGFloat = 20
    static let verticalInset: CGFloat = 16
    static let detailHorizontalInset: CGFloat = 28
    static let detailVerticalInset: CGFloat = 28
    static let expandedScreenEdgeInset: CGFloat = 6
    static let expandedCornerRadius = AppTheme.radius.xl
    static let detailExpandedCornerRadius: CGFloat = 45
    static let compactCornerRadius = AppTheme.radius.lg
    static let expandedContentScale: CGFloat = 1.05
    static let backgroundContentScale: CGFloat = 0.94
    static let backgroundContentOpacity: CGFloat = 0.62
}

enum TaskMorphListSpacing {
    /// Real empty space added outside the active card boundary. Because this is
    /// list-owned padding, it contributes to LazyVStack row height and reverses
    /// with the same transaction as the disclosure instead of faking movement
    /// with offsets on neighboring rows.
    static let expandedExternalSeparation: CGFloat = 10

    /// Vertical growth outside the disclosure itself: two internal card insets
    /// plus the two real external separation gaps.
    static var fixedExpansionHeightDelta: CGFloat {
        2 * (TaskMorphSurfaceMetrics.detailVerticalInset + expandedExternalSeparation)
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

        // Keep the selected row below the pinned section-header zone. Within
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

        if progress < lastProgress - 0.001, motionDirection == .expanding {
            beginCollapse(for: id)
        }
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
            coordinator.applyExpansionProgress(newValue, for: id)
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
        .scaleEffect(
            x: activeContentScale,
            y: activeContentScale,
            anchor: .top
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, usesExpandedGeometry ? TaskMorphSurfaceMetrics.detailHorizontalInset : 0)
        .padding(.vertical, usesExpandedGeometry ? TaskMorphSurfaceMetrics.detailVerticalInset : 0)
        .background {
            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .fill(AppTheme.colors.surface)
                .opacity(usesExpandedGeometry ? 1 : 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                .strokeBorder(AppTheme.colors.body.opacity(0.06), lineWidth: 0.5)
                .opacity(usesExpandedGeometry ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: clippingCornerRadius, style: .continuous))
        .shadow(
            color: usesExpandedGeometry ? Color.black.opacity(0.14) : .clear,
            radius: usesExpandedGeometry ? 16 : 0,
            y: usesExpandedGeometry ? 7 : 0
        )
        .scaleEffect(backgroundContentScale)
        .brightness(backgroundBrightness)
        .opacity(hidesRealSurfaceForHero ? 0 : backgroundContentOpacity * backgroundDimOpacity)
        .accessibilityElement(children: .contain)
    }

    private var usesExpandedGeometry: Bool {
        isActive && state != .compact
    }

    private var surfaceCornerRadius: CGFloat {
        usesExpandedGeometry
            ? TaskMorphSurfaceMetrics.detailExpandedCornerRadius
            : TaskMorphSurfaceMetrics.compactCornerRadius
    }

    private var clippingCornerRadius: CGFloat {
        usesExpandedGeometry ? surfaceCornerRadius : 0
    }

    private var activeContentScale: CGFloat {
        guard reduceMotion == false, usesExpandedGeometry else { return 1 }
        return TaskMorphSurfaceMetrics.expandedContentScale
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
            .frame(height: isExpanded ? resolvedExpandedHeight : 0, alignment: .top)
            .clipped()
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

private struct TaskMorphListPlacementModifier: ViewModifier {
    let state: TaskMorphVisualState
    let isActive: Bool
    let compactInsets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .padding(adjustedInsets)
    }

    private var usesExpandedGeometry: Bool {
        isActive && state != .compact
    }

    private var adjustedInsets: EdgeInsets {
        guard usesExpandedGeometry else { return compactInsets }
        return TaskMorphListSpacing.expandedInsets(from: compactInsets)
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
                state: state,
                isActive: isActive,
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
