import Foundation
import Observation
import SwiftUI

enum HomeCardSurfaceStyle: Hashable {
    case accent
    case muted
}

struct HomeAvatarToken: Identifiable, Hashable {
    let id: UUID
    let title: String
    let fill: Color
    let foreground: Color
}

struct HomeEditorDraft: Hashable {
    let itemID: UUID
    var title: String
    var notes: String
    var dueAt: Date
    var remindAt: Date?
    var locationText: String
    var executionRole: ItemExecutionRole
    var priority: ItemPriority
    var isPinned: Bool
}

@MainActor
@Observable
final class HomeViewModel {
    private let sessionStore: SessionStore
    private let itemRepository: ItemRepositoryProtocol
    private let anniversaryRepository: AnniversaryRepositoryProtocol
    private let calendar = Calendar.current

    var loadState: LoadableState = .idle
    var selectedDate: Date = MockDataFactory.now
    var items: [Item] = []
    var highlightedAnniversary: Anniversary?
    var expandedEditorItemID: UUID?
    var editorDraft: HomeEditorDraft?
    var isEditorPresented = false
    var isEditorStageVisible = false
    var isBackgroundScrollLocked = false

    init(
        sessionStore: SessionStore,
        itemRepository: ItemRepositoryProtocol,
        anniversaryRepository: AnniversaryRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.itemRepository = itemRepository
        self.anniversaryRepository = anniversaryRepository
    }

    var currentUserID: UUID? { sessionStore.currentUser?.id }

    var partnerUserID: UUID? {
        guard let pairSpace = sessionStore.currentPairSpace else { return nil }
        let currentID = currentUserID
        return [pairSpace.memberA.userID, pairSpace.memberB?.userID]
            .compactMap { $0 }
            .first(where: { $0 != currentID })
    }

    var selectedDateTitle: String {
        let components = calendar.dateComponents([.month, .day], from: selectedDate)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return "\(month)月\(day)日"
    }

    var visibleItems: [Item] {
        items
            .filter { $0.status == .pendingConfirmation || $0.status == .inProgress }
            .filter { calendar.isDate(effectiveDate(for: $0), inSameDayAs: selectedDate) }
            .sorted(by: sortItems)
    }

    var selectedEditorItem: Item? {
        guard let expandedEditorItemID else { return nil }
        return items.first(where: { $0.id == expandedEditorItemID })
    }

    var selectedEditorDueDate: Date {
        editorDraft?.dueAt ?? selectedDate
    }

    var weekDates: [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 86_400 * 7)

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    func load() async {
        loadState = .loading

        do {
            let relationshipID = sessionStore.currentPairSpace?.id
            items = try await itemRepository.fetchItems(relationshipID: relationshipID)
            let anniversaries = try await anniversaryRepository.fetchAnniversaries(relationshipID: relationshipID)
            highlightedAnniversary = anniversaries.first
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
    }

    func presentEditor(for item: Item) {
        expandedEditorItemID = item.id
        editorDraft = HomeEditorDraft(
            itemID: item.id,
            title: item.title,
            notes: item.notes ?? "",
            dueAt: item.dueAt ?? selectedDate,
            remindAt: item.remindAt,
            locationText: item.locationText ?? "",
            executionRole: item.executionRole,
            priority: item.priority,
            isPinned: item.isPinned
        )
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            isBackgroundScrollLocked = true
            isEditorPresented = true
        }
    }

    func beginEditorDismissal() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isEditorPresented = false
            isEditorStageVisible = false
            isBackgroundScrollLocked = false
        }
    }

    func finalizeEditorDismissal() {
        expandedEditorItemID = nil
        editorDraft = nil
    }

    func dismissEditor() {
        beginEditorDismissal()
        finalizeEditorDismissal()
    }

    func togglePin(for item: Item) async {
        var updated = item
        updated.isPinned.toggle()

        if updated.isPinned {
            items = items.map { existing in
                var copy = existing
                if existing.relationshipID == updated.relationshipID {
                    copy.isPinned = existing.id == updated.id
                }
                return copy
            }
        } else {
            items = items.map { existing in
                var copy = existing
                if existing.id == updated.id {
                    copy.isPinned = false
                }
                return copy
            }
        }

        do {
            _ = try await itemRepository.saveItem(updated)
            await load()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func updateDraftTitle(_ value: String) {
        editorDraft?.title = value
    }

    func updateDraftNotes(_ value: String) {
        editorDraft?.notes = value
    }

    func updateDraftDueAt(_ value: Date) {
        editorDraft?.dueAt = value
    }

    func updateDraftLocation(_ value: String) {
        editorDraft?.locationText = value
    }

    func updateDraftExecutionRole(_ value: ItemExecutionRole) {
        editorDraft?.executionRole = value
    }

    func updateDraftPriority(_ value: ItemPriority) {
        editorDraft?.priority = value
    }

    func updateDraftPinned(_ value: Bool) {
        editorDraft?.isPinned = value
    }

    func applyDraft() async -> Bool {
        guard let draft = editorDraft, let itemIndex = items.firstIndex(where: { $0.id == draft.itemID }) else {
            return false
        }

        var updated = items[itemIndex]
        updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? updated.title : draft.title
        updated.notes = draft.notes.isEmpty ? nil : draft.notes
        updated.dueAt = draft.dueAt
        updated.remindAt = draft.remindAt
        updated.locationText = draft.locationText.isEmpty ? nil : draft.locationText
        updated.executionRole = draft.executionRole
        updated.priority = draft.priority
        updated.isPinned = draft.isPinned
        updated.updatedAt = MockDataFactory.now

        if updated.isPinned {
            items = items.map { existing in
                var copy = existing
                if existing.relationshipID == updated.relationshipID {
                    copy.isPinned = existing.id == updated.id
                }
                return copy
            }
        }

        items[itemIndex] = updated

        do {
            _ = try await itemRepository.saveItem(updated)
            await load()
            return true
        } catch {
            loadState = .failed(error.localizedDescription)
            return false
        }
    }

    func cardSurfaceStyle(for item: Item) -> HomeCardSurfaceStyle {
        item.isPinned || item.priority != .normal ? .accent : .muted
    }

    func ownershipTokens(for item: Item) -> [HomeAvatarToken] {
        guard let currentUserID else { return [] }

        switch item.executionRole {
        case .initiator:
            return [
                HomeAvatarToken(
                    id: item.creatorID,
                    title: item.creatorID == currentUserID ? "我" : "TA",
                    fill: item.creatorID == currentUserID ? .pink.opacity(0.22) : .blue.opacity(0.16),
                    foreground: item.creatorID == currentUserID ? .pink : .blue
                )
            ]
        case .recipient:
            let assigneeID = item.creatorID == currentUserID ? partnerUserID ?? item.creatorID : currentUserID
            return [
                HomeAvatarToken(
                    id: assigneeID,
                    title: assigneeID == currentUserID ? "我" : "TA",
                    fill: assigneeID == currentUserID ? .pink.opacity(0.22) : .blue.opacity(0.16),
                    foreground: assigneeID == currentUserID ? .pink : .blue
                )
            ]
        case .both:
            return [
                HomeAvatarToken(
                    id: currentUserID,
                    title: "我",
                    fill: .pink.opacity(0.22),
                    foreground: .pink
                ),
                HomeAvatarToken(
                    id: partnerUserID ?? UUID(),
                    title: "TA",
                    fill: .blue.opacity(0.16),
                    foreground: .blue
                )
            ]
        }
    }

    func roleLabel(for item: Item) -> String {
        guard let currentUserID else { return "一起做" }
        return item.executionRole.label(for: currentUserID, creatorID: item.creatorID)
    }

    func isDateInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
    }

    func isSelectedDate(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func weekdayLabel(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return ""
        }
    }

    func effectiveDate(for item: Item) -> Date {
        item.dueAt ?? item.createdAt
    }

    private func sortItems(lhs: Item, rhs: Item) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        let leftEffectiveDate = effectiveDate(for: lhs)
        let rightEffectiveDate = effectiveDate(for: rhs)
        if leftEffectiveDate != rightEffectiveDate {
            return leftEffectiveDate < rightEffectiveDate
        }

        switch (lhs.dueAt, rhs.dueAt) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        let leftRank = priorityRank(lhs.priority)
        let rightRank = priorityRank(rhs.priority)
        if leftRank != rightRank {
            return leftRank > rightRank
        }

        return lhs.createdAt > rhs.createdAt
    }

    private func priorityRank(_ priority: ItemPriority) -> Int {
        switch priority {
        case .normal:
            return 0
        case .important:
            return 1
        case .critical:
            return 2
        }
    }
}
