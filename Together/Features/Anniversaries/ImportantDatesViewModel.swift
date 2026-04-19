import Foundation
import Observation
import os

@MainActor
@Observable
final class ImportantDatesViewModel {
    var events: [ImportantDate] = []
    var isLoading = false
    var onChange: (@MainActor @Sendable () async -> Void)?

    private let repository: ImportantDateRepositoryProtocol
    private var spaceID: UUID?
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "ImportantDatesViewModel")

    init(repository: ImportantDateRepositoryProtocol) {
        self.repository = repository
    }

    func configure(spaceID: UUID) {
        self.spaceID = spaceID
    }

    func load() async {
        guard let spaceID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await repository.fetchAll(spaceID: spaceID)
        } catch {
            logger.error("load failed: \(error.localizedDescription)")
        }
    }

    func save(_ event: ImportantDate) async {
        do {
            try await repository.save(event)
        } catch {
            logger.error("save failed: \(error.localizedDescription)")
        }
        await load()
        await onChange?()
    }

    func delete(_ id: UUID) async {
        do {
            try await repository.delete(id: id)
        } catch {
            logger.error("delete failed: \(error.localizedDescription)")
        }
        await load()
        await onChange?()
    }
}
