import SwiftUI
import Testing
@testable import Together

@MainActor
@Suite("Home morph session")
struct HomeMorphSessionTests {
    @Test func taskCreationDestinationKeepsStableIdentityAndDomain() {
        let todoID = UUID()
        let periodicID = UUID()

        #expect(TaskCreationDestination.todo(todoID).id == todoID)
        #expect(TaskCreationDestination.todo(todoID).domain == .todo)
        #expect(TaskCreationDestination.periodic(periodicID).id == periodicID)
        #expect(TaskCreationDestination.periodic(periodicID).domain == .periodic)
    }

    @Test func taskDetailRouteKeepsStableIdentityAndUsesSettledPageGeometry() {
        let todoID = UUID()
        let periodicID = UUID()
        let firstPresentationID = UUID()
        let secondPresentationID = UUID()
        let firstPresentation = TaskDetailPresentation(
            id: firstPresentationID,
            route: .todo(todoID)
        )
        let secondPresentation = TaskDetailPresentation(
            id: secondPresentationID,
            route: .todo(todoID)
        )

        #expect(TaskDetailRoute.todo(todoID).id == todoID)
        #expect(TaskDetailRoute.todo(todoID).domain == .todo)
        #expect(TaskDetailRoute.periodic(periodicID).id == periodicID)
        #expect(TaskDetailRoute.periodic(periodicID).domain == .periodic)
        #expect(firstPresentation.route == secondPresentation.route)
        #expect(firstPresentation.id == firstPresentationID)
        #expect(secondPresentation.id == secondPresentationID)
        #expect(firstPresentation.id != secondPresentation.id)
        #expect(firstPresentation.canReleaseSharedDraft(while: nil))
        #expect(firstPresentation.canReleaseSharedDraft(while: firstPresentation))
        #expect(firstPresentation.canReleaseSharedDraft(while: secondPresentation) == false)
        #expect(secondPresentation.canReleaseSharedDraft(while: secondPresentation))
        #expect(TaskExpansionMotion.navigationDetail.layoutProgress == 1)
        #expect(TaskExpansionMotion.navigationDetail.compactHeightProgress == 0)
        #expect(TaskExpansionMotion.navigationDetail.identityScale == 1)
        #expect(TaskExpansionMotion.navigationDetail.identityOffsetX == 0)
        #expect(TaskExpansionMotion.navigationDetail.identityOffsetY == 0)
        #expect(TaskExpansionMotion.navigationDetail.isDetailSettled)
    }

    @Test func inlineExpansionUsesIndependentPhysicalTracks() {
        #expect(TaskExpansionMotionTiming.expansionDuration == 0.70)
        #expect(TaskExpansionMotionTiming.identityExpansionDuration == 0.46)
        #expect(TaskExpansionMotionTiming.collapseDuration == 0.32)
        #expect(TaskExpansionMotionTiming.reducedMotionDuration == 0.22)
        #expect(TaskExpansionMotionTiming.layoutDuration == 0.46)
        #expect(
            abs(
                TaskExpansionMotionTiming.identityTroughDuration
                    + TaskExpansionMotionTiming.identityRiseDuration
                    - TaskExpansionMotionTiming.identityExpansionDuration
            ) < 0.000_001
        )
        #expect(
            abs(
                TaskExpansionMotionTiming.identityCollapseToTroughDuration
                    + TaskExpansionMotionTiming.identityCollapseToCompactDuration
                    - TaskExpansionMotionTiming.collapseDuration
            ) < 0.000_001
        )
        #expect(TaskExpansionMotionTiming.identityTroughOffset == CGSize(width: -7, height: 14))
        #expect(TaskExpansionMotionTiming.expandedIdentityOffset == CGSize(width: -16, height: -12))
        #expect(TaskExpansionMotionTiming.identityTroughScale == 1.05)
        #expect(
            abs(
                TaskExpansionMotion.expanded.identityScale * 1.05
                    - TaskExpansionMotionTiming.expandedIdentityVisualScale
            ) < 0.000_001
        )
        #expect(TaskExpansionMotion.expanded.identityOffsetX == -16)
        #expect(TaskExpansionMotion.expanded.identityOffsetY == -12)
        #expect(TaskExpansionMotion.expanded.detailElapsed == 0.40)
        #expect(TaskExpansionMotion.expanded.isDetailSettled)
        #expect(TaskExpansionMotion.compact.collapsedOpacity == 1)
    }

    @Test func detailCascadeUsesBoundedDiagonalWave() {
        #expect(TaskMorphCascadeTiming.expansionDelay == 0.30)
        #expect(
            TaskMorphCascadeTiming.expansionDelay + TaskMorphCascadeTiming.rowDuration
                > TaskExpansionMotionTiming.identityExpansionDuration
        )
        #expect(
            abs(
                TaskMorphCascadeTiming.expansionDelay
                    + TaskMorphCascadeTiming.timelineDuration
                    - TaskExpansionMotionTiming.expansionDuration
            ) < 0.000_001
        )
        #expect(TaskMorphCascadeTiming.totalDelay(rowCount: 1) == 0)
        #expect(abs(TaskMorphCascadeTiming.totalDelay(rowCount: 7) - 0.22) < 0.000_001)
        #expect(abs(TaskMorphCascadeTiming.totalDelay(rowCount: 20) - 0.22) < 0.000_001)
        #expect(abs(TaskMorphCascadeTiming.collapseTotalDelay(rowCount: 5) - 0.12) < 0.000_001)
        #expect(abs(TaskMorphCascadeTiming.collapseTotalDelay(rowCount: 20) - 0.12) < 0.000_001)

        let start = TaskMorphCascadeValues.resolve(
            elapsed: 0,
            index: 0,
            rowCount: 10,
            reduceMotion: false
        )
        #expect(start.progress == 0)
        #expect(start.offset == CGSize(width: 14, height: 24))
        #expect(start.opacity == 0)

        let final = TaskMorphCascadeValues.resolve(
            elapsed: TaskMorphCascadeTiming.timelineDuration,
            index: 9,
            rowCount: 10,
            reduceMotion: false
        )
        #expect(final.progress == 1)
        #expect(final.offset == .zero)
        #expect(final.opacity == 1)

        let midpoint = TaskMorphCascadeValues.resolve(
            progress: 0.5,
            reduceMotion: false
        )
        #expect(midpoint.offset.width > 7)
        #expect(midpoint.offset.height > 12)
        #expect(midpoint.opacity == 0.5)
    }

    @Test func backgroundWaveUsesUniformVisualDepthAndKeepsSpatialCascade() {
        #expect(abs(TaskMorphBackgroundWave.expansionDuration - 0.36) < 0.000_001)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: nil, isDarkAppearance: false) == 0)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: 0, isDarkAppearance: true) == 0)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: 1, isDarkAppearance: false) == 1.4)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: -1, isDarkAppearance: false) == 1.4)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: -2, isDarkAppearance: false) == 1.4)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: 4, isDarkAppearance: true) == 2.0)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: 8, isDarkAppearance: true) == 2.0)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: 20, isDarkAppearance: true) == 2.0)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: nil) == 1)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: 0) == 1)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: -1) == 0.84)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: -20) == 0.84)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: 1) == 0.84)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: 20) == 0.84)
        #expect(TaskMorphBackgroundWave.opacity(forTaskDelta: 1, isDarkAppearance: false) == 0.68)
        #expect(TaskMorphBackgroundWave.opacity(forTaskDelta: -2, isDarkAppearance: false) == 0.68)
        #expect(TaskMorphBackgroundWave.lightUniformTextOpacity == 0.42)
        #expect(TaskMorphBackgroundWave.opacity(forTaskDelta: 4, isDarkAppearance: true) == 0.40)
        #expect(TaskMorphBackgroundWave.opacity(forTaskDelta: 8, isDarkAppearance: true) == 0.40)
        #expect(TaskMorphBackgroundWave.opacity(forTaskDelta: 20, isDarkAppearance: true) == 0.40)
        #expect(TaskMorphBackgroundWave.headerBlurRadius(isDarkAppearance: false) == 0.8)
        #expect(TaskMorphBackgroundWave.headerBlurRadius(isDarkAppearance: true) == 0.5)
        #expect(TaskMorphBackgroundWave.headerOpacity(isDarkAppearance: false) == 0.34)
        #expect(TaskMorphBackgroundWave.headerOpacity(isDarkAppearance: true) == 0.52)
        #expect(TaskMorphBackgroundWave.dateHeaderScale == 0.84)
        #expect(TaskMorphBackgroundWave.dateHeaderBlurRadius(isDarkAppearance: false) == 1.4)
        #expect(TaskMorphBackgroundWave.dateHeaderBlurRadius(isDarkAppearance: true) == 2.0)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: -1) == -8)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: -20) == -24)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: 1) == 12)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: 20) == 36)
        #expect(abs(TaskMorphBackgroundWave.delay(forTaskDelta: -1) - 0.015) < 0.000_001)
        #expect(abs(TaskMorphBackgroundWave.delay(forTaskDelta: -2) - 0.075) < 0.000_001)
        #expect(abs(TaskMorphBackgroundWave.delay(forTaskDelta: -20) - 0.26) < 0.000_001)
        #expect(abs(TaskMorphBackgroundWave.delay(forTaskDelta: 1) - 0.02) < 0.000_001)
        #expect(abs(TaskMorphBackgroundWave.delay(forTaskDelta: 2) - 0.095) < 0.000_001)
        #expect(abs(TaskMorphBackgroundWave.delay(forTaskDelta: 20) - 0.34) < 0.000_001)
        #expect(
            abs(
                TaskMorphBackgroundWave.expansionDuration
                    + TaskMorphBackgroundWave.lowerMaximumDelay
                    - TaskExpansionMotionTiming.expansionDuration
            ) < 0.000_001
        )
    }

    @Test func lightFocusFieldRetainsOnlyAQuietParticleTrace() {
        #expect(TaskMorphFocusField.lightParticleRetention == 0.18)
        #expect(TaskMorphFocusField.lightOverlayOpacity == 0.82)
        #expect(TaskMorphFocusField.increasedContrastLightParticleRetention == 0.10)
        #expect(TaskMorphFocusField.increasedContrastLightOverlayOpacity == 0.90)
        #expect(TaskMorphFocusField.lightVerticalExpansion == 28)
        #expect(TaskMorphFocusField.darkVerticalExpansion == 52)
        #expect(TaskMorphFocusField.verticalExpansion(isDarkAppearance: false) == 28)
        #expect(TaskMorphFocusField.verticalExpansion(isDarkAppearance: true) == 52)
    }

    @Test func detailCollapseSharesTheContinuousLayoutClock() {
        let motion = TaskExpansionMotion(
            layoutProgress: 0.5,
            compactHeightProgress: 0.5,
            identityScale: 1,
            identityOffsetX: 0,
            collapsedOpacity: 0.5,
            identityOffsetY: 0,
            detailElapsed: 0
        )

        #expect(motion.cascadeElapsed(isCollapsing: false) == 0)
        #expect(
            motion.cascadeElapsed(isCollapsing: true)
                == TaskMorphCascadeTiming.timelineDuration / 2
        )
    }

    @Test func detailCollapseExitsFromBottomToTop() {
        let collapseElapsed: TimeInterval = 0.05
        let elapsed = TaskMorphCascadeTiming.timelineDuration
            * (1 - collapseElapsed / TaskExpansionMotionTiming.collapseDuration)

        let first = TaskMorphCascadeValues.resolve(
            elapsed: elapsed,
            index: 0,
            rowCount: 5,
            reduceMotion: false,
            isCollapsing: true
        )
        let last = TaskMorphCascadeValues.resolve(
            elapsed: elapsed,
            index: 4,
            rowCount: 5,
            reduceMotion: false,
            isCollapsing: true
        )

        #expect(first.progress == 1)
        #expect(last.progress < first.progress)
        #expect(last.opacity < first.opacity)
    }

    @Test func reduceMotionCascadeUsesOnlyCrossfade() {
        let midpoint = TaskMorphCascadeValues.resolve(
            elapsed: TaskMorphCascadeTiming.timelineDuration / 2,
            index: 5,
            rowCount: 10,
            reduceMotion: true
        )

        #expect(midpoint.progress == 0.5)
        #expect(midpoint.offset == .zero)
        #expect(midpoint.opacity == 0.5)
    }

    @Test func dateBarSelectionAdvancesOnlyWhenASectionCrossesItsBoundary() {
        let sectionIDs = ["today", "tomorrow", "later"]
        var selection = HomeTimelineDateBarSelection()

        selection.reconcile(sectionIDs: sectionIDs)
        #expect(selection.activeSectionID == "today")

        selection.setCrossed(true, sectionID: "tomorrow", sectionIDs: sectionIDs)
        #expect(selection.activeSectionID == "tomorrow")

        selection.setCrossed(true, sectionID: "later", sectionIDs: sectionIDs)
        #expect(selection.activeSectionID == "later")

        selection.setCrossed(false, sectionID: "later", sectionIDs: sectionIDs)
        #expect(selection.activeSectionID == "tomorrow")

        selection.setCrossed(false, sectionID: "tomorrow", sectionIDs: sectionIDs)
        #expect(selection.activeSectionID == "today")
    }

    @Test func dateBarSelectionDropsRemovedSectionsDuringReconciliation() {
        var selection = HomeTimelineDateBarSelection()
        selection.setCrossed(
            true,
            sectionID: "tomorrow",
            sectionIDs: ["today", "tomorrow"]
        )
        #expect(selection.activeSectionID == "tomorrow")

        selection.reconcile(sectionIDs: ["today", "later"])

        #expect(selection.activeSectionID == "today")
        #expect(selection.crossedSectionIDs.isEmpty)
    }

    @Test func onlyOneMorphSubjectCanBeActive() throws {
        let model = HomeMorphSession()
        let firstID = UUID()
        _ = try #require(
            model.prepareExpansion(domain: .todo, id: firstID, placement: todoPlacement(id: firstID))
        )

        let competingID = UUID()
        let result = model.prepareExpansion(
            domain: .periodic,
            id: competingID,
            placement: periodicPlacement(id: competingID)
        )

        #expect(result == nil)
        #expect(model.subject == .persisted(domain: .todo, id: firstID))
    }

    @Test func failedSavePreservesSubjectPlacementAndExpandedState() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let placement = todoPlacement(id: id)
        let expansion = try #require(model.prepareExpansion(domain: .todo, id: id, placement: placement))
        #expect(model.visualState == .compact)
        #expect(model.activatePreparedExpansion(using: expansion))
        let saving = try #require(model.beginSaving())

        model.failSaving(using: saving, message: "保存失败")

        #expect(model.phase == .active)
        #expect(model.visualState == .expanded)
        #expect(model.subject == .persisted(domain: .todo, id: id))
        #expect(model.placement == placement)
        #expect(model.errorMessage == "保存失败")
    }

    @Test func stalePhaseTokenCannotChangeNewerPhase() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let expansion = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: todoPlacement(id: id))
        )
        #expect(model.activatePreparedExpansion(using: expansion))
        let saving = try #require(model.beginSaving())

        model.failSaving(using: expansion, message: "过期回调")

        #expect(model.phase == .saving)
        #expect(model.errorMessage == nil)
        #expect(model.isCurrent(saving))
    }

    @Test func savingLocksDuplicateCommitDismissAndCompletionIntents() throws {
        let model = HomeMorphSession()
        let id = UUID()
        var dismissalCount = 0
        var completionCount = 0
        model.onDismissIntent = { _ in dismissalCount += 1 }
        model.onCompletionIntent = { _ in completionCount += 1 }
        let expansion = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: todoPlacement(id: id))
        )
        #expect(model.activatePreparedExpansion(using: expansion))
        _ = try #require(model.beginSaving())

        #expect(model.beginSaving() == nil)
        model.requestDismissal()
        model.requestCompletion()

        #expect(dismissalCount == 0)
        #expect(completionCount == 0)
        #expect(model.phase == .saving)
        #expect(model.detailPresentationIntent == .compact)
    }

    @Test func currentRowTapDuringSaveKeepsExpandedPresentation() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let placement = todoPlacement(id: id)
        let expansion = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: placement)
        )
        #expect(model.activatePreparedExpansion(using: expansion))
        model.requestDismissal()
        let saving = try #require(model.beginSaving())

        #expect(model.requestExpansionRetention(domain: .todo, id: id))
        let active = try #require(
            model.finishSavingKeepingDetail(using: saving, finalPlacement: placement)
        )

        #expect(model.phase == .active)
        #expect(model.visualState == .expanded)
        #expect(model.detailPresentationIntent == .expanded)
        #expect(model.isCurrent(active))
    }

    @Test func collapseCompletionRejectsStaleTokenAfterReversal() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let placement = todoPlacement(id: id)
        var completionCount = 0
        model.onDetailCollapseCompletionIntent = { _, _ in completionCount += 1 }
        let expansion = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: placement)
        )
        #expect(model.activatePreparedExpansion(using: expansion))
        model.requestDismissal()
        let saving = try #require(model.beginSaving())
        let collapse = try #require(
            model.beginDetailCollapseAfterSave(using: saving, finalPlacement: placement)
        )
        _ = try #require(model.reverseDetailCollapse(domain: .todo, id: id))

        model.requestDetailCollapseCompletion(
            .persisted(domain: .todo, id: id),
            using: collapse
        )

        #expect(completionCount == 0)
        #expect(model.phase == .active)
        #expect(model.visualState == .expanded)
    }

    @Test func currentCollapseCompletionEmitsExactlyOncePerRequest() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let placement = todoPlacement(id: id)
        var received: (TaskMorphSubject, HomeMorphSessionToken)?
        model.onDetailCollapseCompletionIntent = { received = ($0, $1) }
        let expansion = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: placement)
        )
        #expect(model.activatePreparedExpansion(using: expansion))
        model.requestDismissal()
        let saving = try #require(model.beginSaving())
        let collapse = try #require(
            model.beginDetailCollapseAfterSave(using: saving, finalPlacement: placement)
        )

        model.requestDetailCollapseCompletion(
            .persisted(domain: .todo, id: id),
            using: collapse
        )

        #expect(received?.0 == .persisted(domain: .todo, id: id))
        #expect(received?.1 == collapse)
    }

    @Test func tappingAnotherSubjectRequestsDismissalWithoutOpeningIt() throws {
        let model = HomeMorphSession()
        let firstID = UUID()
        var dismissed: TaskMorphSubject?
        model.onDismissIntent = { dismissed = $0 }
        _ = try #require(
            model.prepareExpansion(domain: .todo, id: firstID, placement: todoPlacement(id: firstID))
        )

        model.requestDismissal()

        #expect(dismissed == .persisted(domain: .todo, id: firstID))
        #expect(model.subject?.id == firstID)
        #expect(model.phase == .active)
    }

    @Test func preparedExpansionKeepsCompactOwnershipUntilExplicitActivation() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let token = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: todoPlacement(id: id))
        )

        #expect(model.subject == .persisted(domain: .todo, id: id))
        #expect(model.phase == .active)
        #expect(model.visualState == .compact)
        #expect(model.isFocusDepthActive == false)
        #expect(model.isDetailFocusDepthActive == false)

        #expect(model.activatePreparedExpansion(using: token))
        #expect(model.visualState == .expanded)
        #expect(model.isFocusDepthActive)
        #expect(model.isDetailFocusDepthActive)
        #expect(model.activatePreparedExpansion(using: token) == false)
    }

    @Test func focusDepthDeactivatesDuringAnimatedCollapseBeforeSessionCleanup() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let placement = todoPlacement(id: id)
        let expansion = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: placement)
        )
        #expect(model.isFocusDepthActive == false)
        #expect(model.activatePreparedExpansion(using: expansion))
        #expect(model.isFocusDepthActive)

        let saving = try #require(model.beginSaving())
        let collapse = try #require(
            model.beginDetailCollapseAfterSave(using: saving, finalPlacement: placement)
        )

        #expect(model.phase == .collapsing)
        #expect(model.visualState == .compact)
        #expect(model.isFocusDepthActive == false)
        #expect(model.isDetailFocusDepthActive == false)

        model.finishCollapse(using: collapse)
        #expect(model.phase == .idle)
        #expect(model.isFocusDepthActive == false)
    }

    @Test func tappingActiveRowDuringCollapseReversesFromCurrentSession() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let source = todoPlacement(id: id)
        let destination = TaskMorphPlacement(
            provisionalSection: source.provisionalSection,
            finalSection: .todo(
                dayStart: Date(timeIntervalSince1970: 86_400),
                isUnscheduled: false
            ),
            index: 2,
            presentationID: "destination-\(id.uuidString)"
        )
        let prepared = try #require(
            model.prepareExpansion(domain: .todo, id: id, placement: source)
        )
        #expect(model.activatePreparedExpansion(using: prepared))
        let saving = try #require(model.beginSaving())
        let collapse = try #require(
            model.beginDetailCollapseAfterSave(
                using: saving,
                finalPlacement: destination
            )
        )

        let reversed = try #require(model.reverseDetailCollapse(domain: .todo, id: id))

        #expect(model.phase == .active)
        #expect(model.visualState == .expanded)
        #expect(model.placement == source)
        #expect(model.isCurrent(reversed))
        #expect(model.isCurrent(collapse) == false)
    }

    @Test func inlineDetailKeepsStandardListRowSpacing() {
        let compact = EdgeInsets(
            top: TaskMorphListSpacing.compactExternalInset,
            leading: 28,
            bottom: TaskMorphListSpacing.compactExternalInset,
            trailing: 28
        )
        let expanded = TaskMorphListSpacing.expandedInsets(from: compact)

        #expect(TaskMorphListSpacing.compactExternalInset == 4)
        #expect(expanded.top == 18)
        #expect(expanded.bottom == 18)
        #expect(expanded.leading == compact.leading)
        #expect(expanded.trailing == compact.trailing)
        #expect(TaskMorphListSpacing.fixedExpansionHeightDelta == 28)
    }

    @Test func inlineDetailContentSharesTheParentTitleAxis() {
        #expect(HomeInlineTaskLayoutMetrics.taskTitleLeadingInset == 38)
        #expect(
            HomeInlineTaskLayoutMetrics.attributeLeadingInset
                == HomeInlineTaskLayoutMetrics.taskTitleLeadingInset
        )
        #expect(HomeInlineTaskLayoutMetrics.expandedAttributeLeadingInset == 4)
        #expect(HomeInlineTaskLayoutMetrics.subtaskSpacing == 3)
        #expect(RoutineInlineLayoutMetrics.actionSlotWidth == HomeInlineTaskLayoutMetrics.checkboxSize)
        #expect(RoutineInlineLayoutMetrics.titleLeadingInset == 38)
        #expect(RoutineInlineLayoutMetrics.titleLeadingInset == HomeInlineTaskLayoutMetrics.taskTitleLeadingInset)
        #expect(RoutineInlineLayoutMetrics.attributeLeadingInset == 4)
        #expect(RoutineInlineLayoutMetrics.attributeMinHeight == HomeInlineTaskLayoutMetrics.attributeMinHeight)
        #expect(HomeInlineTaskLayoutMetrics.detailTitleOverlap == 20)
        #expect(HomeInlineTaskLayoutMetrics.detailTopPadding == 0)
        #expect(HomeInlineTaskLayoutMetrics.attributeTopOverlap == 6)
        #expect(RoutineInlineLayoutMetrics.detailTitleOverlap == HomeInlineTaskLayoutMetrics.detailTitleOverlap)
        #expect(RoutineInlineLayoutMetrics.detailTopPadding == HomeInlineTaskLayoutMetrics.detailTopPadding)
        #expect(RoutineInlineLayoutMetrics.attributeTopOverlap == HomeInlineTaskLayoutMetrics.attributeTopOverlap)
        #expect(TaskAttributeToolbarMetrics.horizontalSpacing == 2)
        #expect(
            HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 2)
                - HomeInlineTaskLayoutMetrics.estimatedDetailHeight(subtaskCount: 1)
                == HomeInlineTaskLayoutMetrics.rowMinHeight
                    + HomeInlineTaskLayoutMetrics.subtaskSpacing
        )
    }

    private func todoPlacement(id: UUID) -> TaskMorphPlacement {
        TaskMorphPlacement(
            provisionalSection: .todo(dayStart: Date(timeIntervalSince1970: 0), isUnscheduled: false),
            index: 0,
            presentationID: id.uuidString
        )
    }

    private func periodicPlacement(id: UUID) -> TaskMorphPlacement {
        TaskMorphPlacement(
            provisionalSection: .periodic(cycle: .daily),
            index: 0,
            presentationID: id.uuidString
        )
    }
}
