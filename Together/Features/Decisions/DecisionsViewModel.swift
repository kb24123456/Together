import Foundation
import Observation

@MainActor
@Observable
final class DecisionsViewModel {
    private let sessionStore: SessionStore
    private let decisionRepository: DecisionRepositoryProtocol
    private let itemRepository: ItemRepositoryProtocol

    var loadState: LoadableState = .idle
    var selectedTemplate: DecisionTemplate = .buy
    var pendingDecisions: [Decision] = []
    var stalledDecisions: [Decision] = []
    var consensusDecisions: [Decision] = []

    init(
        sessionStore: SessionStore,
        decisionRepository: DecisionRepositoryProtocol,
        itemRepository: ItemRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.decisionRepository = decisionRepository
        self.itemRepository = itemRepository
    }

    var currentUserID: UUID? { sessionStore.currentUser?.id }
    var visiblePending: [Decision] { pendingDecisions.filter { $0.template == selectedTemplate } }
    var visibleStalled: [Decision] { stalledDecisions.filter { $0.template == selectedTemplate } }
    var visibleConsensus: [Decision] { consensusDecisions.filter { $0.template == selectedTemplate } }

    func load() async {
        loadState = .loading

        do {
            let relationshipID = sessionStore.currentPairSpace?.id
            let decisions = try await decisionRepository.fetchDecisions(relationshipID: relationshipID)
            pendingDecisions = decisions.filter { $0.status == .pendingResponse }
            stalledDecisions = decisions.filter { $0.status == .noConsensusYet }
            consensusDecisions = decisions.filter { $0.status == .consensusReached }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func submitVote(for decision: Decision, value: DecisionVoteValue) async {
        guard let currentUserID else { return }
        _ = try? await decisionRepository.submitVote(
            decisionID: decision.id,
            voterID: currentUserID,
            value: value
        )
        await load()
    }

    func archive(_ decision: Decision) async {
        _ = try? await decisionRepository.archive(decisionID: decision.id)
        await load()
    }

    func convertToItem(_ decision: Decision) async {
        guard let currentUserID else { return }
        _ = try? await decisionRepository.convertToItem(decisionID: decision.id, actorID: currentUserID)
        await load()
    }
}
