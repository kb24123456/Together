import Foundation
import Observation
import os

@MainActor
@Observable
final class ImportantDatesViewModel {
    /// 免费用户自己创建的纪念日上限（spec § 产品切分）。
    static let freeAnniversaryQuota = 5

    var events: [ImportantDate] = []
    var isLoading = false
    var onChange: (@MainActor @Sendable () async -> Void)?

    /// ViewModel → View 的付费墙信号。超配额时设 `.anniversaryQuota`，
    /// View 观察后展示升级提示。View 消费完后调 `dismissUpsell()` 清空。
    private(set) var pendingUpsellTrigger: UpsellTrigger?

    private let sessionStore: SessionStore
    private let premiumGate: PremiumGate
    private let repository: ImportantDateRepositoryProtocol
    private var spaceID: UUID?
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "ImportantDatesViewModel")

    init(
        sessionStore: SessionStore,
        premiumGate: PremiumGate,
        repository: ImportantDateRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.premiumGate = premiumGate
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

    /// 兼容入口：View 层只调这一个方法，内部按 "id 是否已存在" 分流到
    /// createNew / updateExisting。保持 `ImportantDateEditSheet.save()` 的简洁。
    func save(_ event: ImportantDate) async {
        let isNew = !events.contains { $0.id == event.id }
        if isNew {
            await createNew(event)
        } else {
            await updateExisting(event)
        }
    }

    /// 新建路径——走配额门禁。超额时不写 repo，设 upsell trigger 由 View 拦截。
    func createNew(_ event: ImportantDate) async {
        if let currentUserID = sessionStore.currentUser?.id,
           !premiumGate.isPremium {
            let ownCount = events.filter { $0.creatorID == currentUserID }.count
            if ownCount >= Self.freeAnniversaryQuota {
                pendingUpsellTrigger = .anniversaryQuota
                return
            }
        }
        await persist(event)
    }

    /// 编辑已存在的纪念日——**不走**配额门禁（过期用户仍能维护历史数据）。
    func updateExisting(_ event: ImportantDate) async {
        await persist(event)
    }

    func dismissUpsell() {
        pendingUpsellTrigger = nil
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

    private func persist(_ event: ImportantDate) async {
        do {
            try await repository.save(event)
        } catch {
            logger.error("save failed: \(error.localizedDescription)")
        }
        await load()
        await onChange?()
    }
}
