import SwiftUI
import Testing
@testable import Together

@MainActor
@Suite("Home list-owned morph session")
struct HomeMorphSessionTests {
    @Test func viewportMotionSplitsRealHeightAcrossBothSides() {
        let heightDelta: CGFloat = 300
        let upward = TaskMorphViewportMotion.maximumUpwardDisplacement(
            heightDelta: heightDelta,
            availableAbove: 500
        )
        let displacement = TaskMorphViewportMotion.screenDisplacements(
            heightDelta: heightDelta,
            upwardDisplacement: upward
        )

        #expect(upward == 120)
        #expect(displacement.above == 120)
        #expect(displacement.below == 180)
        #expect(displacement.above + displacement.below == heightDelta)
    }

    @Test func viewportMotionRespectsProtectedTopSpace() {
        let upward = TaskMorphViewportMotion.maximumUpwardDisplacement(
            heightDelta: 300,
            availableAbove: 46
        )
        let displacement = TaskMorphViewportMotion.screenDisplacements(
            heightDelta: 300,
            upwardDisplacement: upward
        )

        #expect(upward == 46)
        #expect(displacement.above == 46)
        #expect(displacement.below == 254)
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

    @Test func creationCollapsesBeforeRelocationAndKeepsUUID() throws {
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
        model.finishRelocating(using: relocating)
        #expect(model.phase == .idle)
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

        #expect(model.activatePreparedExpansion(using: token))
        #expect(model.visualState == .expanded)
        #expect(model.activatePreparedExpansion(using: token) == false)
    }

    @Test func expandedListSpacingAddsRealSeparationAroundActiveCard() {
        let compact = EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        let expanded = TaskMorphListSpacing.expandedInsets(from: compact)

        #expect(expanded.top == 24)
        #expect(expanded.bottom == 24)
        #expect(expanded.leading == 12)
        #expect(expanded.trailing == 12)
        #expect(TaskMorphListSpacing.fixedExpansionHeightDelta == 40)
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
