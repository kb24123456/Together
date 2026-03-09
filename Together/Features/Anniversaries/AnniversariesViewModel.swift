import Foundation
import Observation

@MainActor
@Observable
final class AnniversariesViewModel {
    private let sessionStore: SessionStore
    private let anniversaryRepository: AnniversaryRepositoryProtocol

    var loadState: LoadableState = .idle
    var anniversaries: [Anniversary] = []

    init(sessionStore: SessionStore, anniversaryRepository: AnniversaryRepositoryProtocol) {
        self.sessionStore = sessionStore
        self.anniversaryRepository = anniversaryRepository
    }

    var summaryText: String {
        guard let first = anniversaries.first else { return "还没有纪念日" }
        let days = Calendar.current.dateComponents([.day], from: MockDataFactory.now, to: first.eventDate).day ?? 0
        if days >= 0 {
            return "距离\(first.name)还有 \(days) 天"
        } else {
            return "\(first.name)已经过去 \(abs(days)) 天"
        }
    }

    func load() async {
        loadState = .loading

        do {
            anniversaries = try await anniversaryRepository.fetchAnniversaries(
                relationshipID: sessionStore.currentPairSpace?.id
            )
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
