import SwiftUI
import Testing
@testable import Together

@MainActor
@Suite("Home morph session")
struct HomeMorphSessionTests {
    @Test func inlineExpansionUsesIndependentPhysicalTracks() {
        #expect(TaskExpansionMotionTiming.expansionDuration == 0.80)
        #expect(TaskExpansionMotionTiming.identityExpansionDuration == 0.52)
        #expect(TaskExpansionMotionTiming.collapseDuration == 0.36)
        #expect(TaskExpansionMotionTiming.reducedMotionDuration == 0.22)
        #expect(TaskExpansionMotionTiming.layoutDuration == 0.52)
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
                TaskExpansionMotion.expanded.identityScale * 1.03
                    - TaskExpansionMotionTiming.expandedIdentityVisualScale
            ) < 0.000_001
        )
        #expect(TaskExpansionMotion.expanded.identityOffsetX == -16)
        #expect(TaskExpansionMotion.expanded.identityOffsetY == -12)
        #expect(TaskExpansionMotion.expanded.detailElapsed == 0.46)
        #expect(TaskExpansionMotion.expanded.isDetailSettled)
        #expect(TaskExpansionMotion.compact.collapsedOpacity == 1)
    }

    @Test func detailCascadeUsesBoundedDiagonalWave() {
        #expect(TaskMorphCascadeTiming.expansionDelay == 0.34)
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
        #expect(abs(TaskMorphCascadeTiming.totalDelay(rowCount: 7) - 0.26) < 0.000_001)
        #expect(abs(TaskMorphCascadeTiming.totalDelay(rowCount: 20) - 0.26) < 0.000_001)
        #expect(abs(TaskMorphCascadeTiming.collapseTotalDelay(rowCount: 5) - 0.14) < 0.000_001)
        #expect(abs(TaskMorphCascadeTiming.collapseTotalDelay(rowCount: 20) - 0.14) < 0.000_001)

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
    }

    @Test func backgroundWaveCascadesOutwardAndStaysBounded() {
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: nil) == 0)
        #expect(TaskMorphBackgroundWave.radius(forTaskDelta: 0) == 0)
        #expect(
            abs(TaskMorphBackgroundWave.radius(forTaskDelta: 1) - 1.30)
                < 0.000_001
        )
        #expect(
            abs(TaskMorphBackgroundWave.radius(forTaskDelta: -2) - 2.05)
                < 0.000_001
        )
        #expect(
            TaskMorphBackgroundWave.radius(forTaskDelta: 20)
                == TaskMorphBackgroundWave.maximumRadius
        )
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: 1) == 0.92)
        #expect(TaskMorphBackgroundWave.scale(forTaskDelta: 20) == 0.86)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: -1) == -4)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: 1) == 4)
        #expect(TaskMorphBackgroundWave.offsetY(forTaskDelta: 20) == 12)
        #expect(TaskMorphBackgroundWave.delay(forTaskDelta: 2) == 0.025)
        #expect(TaskMorphBackgroundWave.delay(forTaskDelta: 20) == 0.12)
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

    @Test func directCreationUsesFinalIdentityAndStartsEditing() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let placement = todoPlacement(id: id)

        let token = try #require(
            model.beginCreation(domain: .todo, id: id, placement: placement, heroSourceFrame: nil)
        )

        #expect(model.subject == .draft(domain: .todo, id: id))
        #expect(model.visualState == .editing)
        #expect(model.phase == .active)
        #expect(model.placement == placement)
        #expect(model.isCreationFlow)
        #expect(model.isCreationOverlayVisible)
        #expect(model.isCurrent(token))
    }

    @Test func dockCreationWaitsForExplicitHeroTargetBeforeEditing() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let source = CGRect(x: 320, y: 740, width: 52, height: 52)
        let target = CGRect(x: 20, y: 240, width: 350, height: 68)
        let token = try #require(
            model.beginCreation(
                domain: .todo,
                id: id,
                placement: todoPlacement(id: id),
                heroSourceFrame: source
            )
        )

        #expect(model.phase == .heroEntering)
        #expect(model.visualState == .compact)
        #expect(model.isHeroVisible == false)

        model.recordHeroTargetFrame(target)
        #expect(model.isHeroVisible)
        model.setHeroProgress(1, using: token)
        model.finishHero(using: token)

        #expect(model.phase == .active)
        #expect(model.visualState == .editing)
        #expect(model.subject?.id == id)
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

    @Test func creationDissolvesBeforeListRevealAndKeepsUUID() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let provisional = todoPlacement(id: id)
        let final = TaskMorphPlacement(
            provisionalSection: provisional.provisionalSection,
            finalSection: .todo(dayStart: Date(timeIntervalSince1970: 86_400), isUnscheduled: false),
            index: 3,
            presentationID: id.uuidString
        )
        _ = try #require(
            model.beginCreation(domain: .todo, id: id, placement: provisional, heroSourceFrame: nil)
        )
        let saving = try #require(model.beginSaving())
        let collapse = try #require(
            model.beginCollapseAfterSave(
                using: saving,
                persistedSubject: .persisted(domain: .todo, id: id),
                finalPlacement: final
            )
        )

        #expect(model.phase == .collapsing)
        #expect(model.visualState == .compact)
        #expect(model.subject == .persisted(domain: .todo, id: id))
        #expect(model.placement?.provisionalSection == provisional.provisionalSection)
        #expect(model.placement?.finalSection == final.finalSection)

        let relocating = try #require(model.beginRelocating(using: collapse))
        #expect(model.phase == .relocating)
        #expect(model.isCreationListRevealTarget(.todo, id: id))
        #expect(model.isCreationOverlayVisible == false)
        #expect(model.isCreationListRevealEnabled == false)
        model.enableCreationListReveal(using: relocating)
        #expect(model.isCreationListRevealEnabled)
        #expect(model.isFocusDepthActive == false)
        model.finishRelocating(using: relocating)
        #expect(model.phase == .idle)
        #expect(model.isCreationFlow == false)
    }

    @Test func creationRevealCompletionRequiresEnabledCurrentPhase() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let subject = TaskMorphSubject.persisted(domain: .todo, id: id)
        var completedSubject: TaskMorphSubject?
        model.onCreationRevealCompletionIntent = { subject, _ in
            completedSubject = subject
        }

        _ = try #require(
            model.beginCreation(domain: .todo, id: id, placement: todoPlacement(id: id), heroSourceFrame: nil)
        )
        let saving = try #require(model.beginSaving())
        let collapse = try #require(
            model.beginCollapseAfterSave(
                using: saving,
                persistedSubject: subject,
                finalPlacement: todoPlacement(id: id)
            )
        )
        let relocating = try #require(model.beginRelocating(using: collapse))

        model.requestCreationRevealCompletion(subject, using: relocating)
        #expect(completedSubject == nil)

        model.enableCreationListReveal(using: relocating)
        model.requestCreationRevealCompletion(subject, using: relocating)
        #expect(completedSubject == subject)
    }

    @Test func staleAnimationCallbackCannotFinishNewerPhase() throws {
        let model = HomeMorphSession()
        let id = UUID()
        let hero = try #require(
            model.beginCreation(
                domain: .todo,
                id: id,
                placement: todoPlacement(id: id),
                heroSourceFrame: CGRect(x: 0, y: 0, width: 52, height: 52)
            )
        )
        model.recordHeroTargetFrame(CGRect(x: 20, y: 100, width: 350, height: 68))
        model.finishHero(using: hero)
        let saving = try #require(model.beginSaving())

        model.finishHero(using: hero)

        #expect(model.phase == .saving)
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

        #expect(model.activatePreparedExpansion(using: token))
        #expect(model.visualState == .expanded)
        #expect(model.isFocusDepthActive)
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
        let compact = EdgeInsets(top: 8, leading: 28, bottom: 8, trailing: 28)
        let expanded = TaskMorphListSpacing.expandedInsets(from: compact)

        #expect(expanded.top == 22)
        #expect(expanded.bottom == 22)
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
        #expect(HomeInlineTaskLayoutMetrics.expandedAttributeLeadingInset == 0)
        #expect(RoutineInlineLayoutMetrics.actionSlotWidth == HomeInlineTaskLayoutMetrics.checkboxSize)
        #expect(RoutineInlineLayoutMetrics.titleLeadingInset == 38)
        #expect(RoutineInlineLayoutMetrics.titleLeadingInset == HomeInlineTaskLayoutMetrics.taskTitleLeadingInset)
        #expect(RoutineInlineLayoutMetrics.attributeLeadingInset == 0)
        #expect(RoutineInlineLayoutMetrics.attributeMinHeight == HomeInlineTaskLayoutMetrics.attributeMinHeight)
        #expect(TaskAttributeToolbarMetrics.horizontalSpacing == 2)
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
