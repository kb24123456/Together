import Foundation
import Testing
@testable import Together

@MainActor
struct MascotPlaybackOwnershipTests {
    @Test func homeOwnsPlaybackUntilAnEditorStarts() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()

        #expect(ownership.surface == .home)
        #expect(ownership.acceptsInput(from: .home))
        #expect(!ownership.acceptsInput(from: .editor(editorID)))
        #expect(ownership.beginReturn(id: editorID) == false)
        #expect(ownership.finishEditing(id: editorID) == false)

        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.surface == .editor(editorID))
        #expect(ownership.acceptsInput(from: .editor(editorID)))
        #expect(!ownership.acceptsInput(from: .home))
    }

    @Test func returningKeepsTheEditorOwnerAndRejectsInputUntilNativeDismissal() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()
        ownership.beginEditing(id: editorID)

        #expect(ownership.beginReturn(id: editorID) == true)
        #expect(ownership.surface == .editor(editorID))
        #expect(!ownership.acceptsInput(from: .editor(editorID)))
        #expect(!ownership.acceptsInput(from: .home))

        #expect(ownership.finishEditing(id: editorID) == true)
        #expect(ownership.editorID == nil)
        #expect(!ownership.isReturning)
        #expect(ownership.surface == .home)
        #expect(ownership.acceptsInput(from: .home))
        #expect(!ownership.acceptsInput(from: .editor(editorID)))
    }

    @Test func repeatedAppearanceDoesNotUndoACommittedReturn() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()

        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.acceptsInput(from: .editor(editorID)))

        #expect(ownership.beginReturn(id: editorID) == true)
        #expect(ownership.beginReturn(id: editorID) == true)
        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.isReturning)
        #expect(!ownership.acceptsInput(from: .editor(editorID)))
    }

    @Test(arguments: [false, true])
    func anotherEditorCannotTakeOverBeforeTheCurrentOneFinishes(isReturning: Bool) {
        var ownership = MascotPlaybackOwnership()
        let currentID = UUID()
        let nextID = UUID()
        ownership.beginEditing(id: currentID)
        if isReturning { ownership.beginReturn(id: currentID) }

        #expect(ownership.beginEditing(id: nextID) == false)
        #expect(ownership.beginReturn(id: nextID) == false)
        #expect(ownership.finishEditing(id: nextID) == false)
        #expect(ownership.surface == .editor(currentID))
        #expect(ownership.isReturning == isReturning)
        #expect(ownership.acceptsInput(from: .editor(currentID)) == !isReturning)
        #expect(!ownership.acceptsInput(from: .editor(nextID)))
    }

    @Test func delayedCallbacksFromThePreviousEditorCannotInterruptRapidReentry() {
        var ownership = MascotPlaybackOwnership()
        let previousID = UUID()
        let currentID = UUID()
        ownership.beginEditing(id: previousID)
        ownership.beginReturn(id: previousID)
        ownership.finishEditing(id: previousID)

        #expect(ownership.beginEditing(id: currentID) == true)
        #expect(ownership.beginEditing(id: previousID) == false)
        #expect(ownership.beginReturn(id: previousID) == false)
        #expect(ownership.finishEditing(id: previousID) == false)
        #expect(ownership.surface == .editor(currentID))
        #expect(!ownership.isReturning)
        #expect(ownership.acceptsInput(from: .editor(currentID)))
        #expect(!ownership.acceptsInput(from: .home))
    }

    @Test func interactiveDismissalNeedsNoExplicitReturnAndDuplicateCleanupIsIgnored() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()
        ownership.beginEditing(id: editorID)

        // A cancelled interactive gesture has no committed lifecycle event.
        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.acceptsInput(from: .editor(editorID)))

        #expect(ownership.finishEditing(id: editorID) == true)
        #expect(ownership.finishEditing(id: editorID) == false)
        #expect(ownership.beginReturn(id: editorID) == false)
        #expect(ownership.surface == .home)
        #expect(!ownership.isReturning)
        #expect(ownership.acceptsInput(from: .home))
    }

    @Test func editorOwnsInputWhileVisualArrivalIsStillPending() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()
        #expect(!ownership.isEntering)
        #expect(!ownership.hasArrivedAtEditor)

        ownership.beginEditing(id: editorID)
        #expect(ownership.isEntering)
        #expect(!ownership.hasArrivedAtEditor)
        #expect(ownership.surface == .editor(editorID))
        #expect(ownership.acceptsInput(from: .editor(editorID)))

        #expect(ownership.arriveAtEditor(id: editorID) == true)
        #expect(ownership.hasArrivedAtEditor)
        #expect(!ownership.isEntering)
        #expect(ownership.acceptsInput(from: .editor(editorID)))
    }

    @Test func onlyTheCurrentEditorsFirstArrivalOpensTheGate() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()
        #expect(ownership.arriveAtEditor(id: editorID) == false)
        ownership.beginEditing(id: editorID)
        #expect(ownership.arriveAtEditor(id: UUID()) == false)
        #expect(ownership.isEntering)
        #expect(!ownership.hasArrivedAtEditor)

        #expect(ownership.arriveAtEditor(id: editorID) == true)
        #expect(ownership.arriveAtEditor(id: editorID) == false)
        #expect(ownership.hasArrivedAtEditor)
        #expect(!ownership.isEntering)
    }

    @Test func returningBeforeArrivalRejectsTheLateDockingCallback() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()
        ownership.beginEditing(id: editorID)
        ownership.beginReturn(id: editorID)
        #expect(!ownership.isEntering)
        #expect(!ownership.hasArrivedAtEditor)
        #expect(ownership.arriveAtEditor(id: editorID) == false)
        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.isReturning)
        #expect(!ownership.hasArrivedAtEditor)
        #expect(!ownership.acceptsInput(from: .editor(editorID)))

        ownership.finishEditing(id: editorID)
        #expect(!ownership.isEntering)
        #expect(!ownership.hasArrivedAtEditor)
        #expect(ownership.arriveAtEditor(id: editorID) == false)
    }

    @Test func quickReentryRequiresItsOwnArrivalAndIgnoresThePreviousEditor() {
        var ownership = MascotPlaybackOwnership()
        let previousID = UUID()
        let currentID = UUID()
        ownership.beginEditing(id: previousID)
        ownership.arriveAtEditor(id: previousID)
        ownership.finishEditing(id: previousID)
        #expect(!ownership.hasArrivedAtEditor)

        ownership.beginEditing(id: currentID)
        #expect(ownership.isEntering)
        #expect(!ownership.hasArrivedAtEditor)
        #expect(ownership.arriveAtEditor(id: previousID) == false)
        #expect(ownership.isEntering)
        #expect(ownership.arriveAtEditor(id: currentID) == true)
        #expect(ownership.hasArrivedAtEditor)
    }

    @Test func duplicateBeginPreservesArrivalAndACommittedReturn() {
        var ownership = MascotPlaybackOwnership()
        let editorID = UUID()
        ownership.beginEditing(id: editorID)
        ownership.arriveAtEditor(id: editorID)

        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.hasArrivedAtEditor)
        #expect(!ownership.isEntering)
        ownership.beginReturn(id: editorID)
        #expect(ownership.beginEditing(id: editorID) == true)
        #expect(ownership.hasArrivedAtEditor)
        #expect(ownership.isReturning)
        #expect(!ownership.isEntering)
        #expect(ownership.arriveAtEditor(id: editorID) == false)
    }
}
