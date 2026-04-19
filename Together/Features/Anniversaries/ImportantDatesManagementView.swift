import SwiftUI

struct ImportantDatesManagementView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit: ImportantDate?
    @State private var showCreateSheet = false
    @State private var showPresetPicker = false

    private var viewModel: ImportantDatesViewModel {
        appContext.importantDatesViewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.events.isEmpty {
                    emptyStateView
                } else {
                    list
                }
            }
            .navigationTitle("纪念日")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $showEdit) { event in
                ImportantDateEditSheet(event: event)
            }
            .confirmationDialog("添加纪念日", isPresented: $showCreateSheet) {
                Button("🎂 伴侣生日") { createBirthday(myself: false) }
                    .disabled(existingBirthday(myself: false) != nil)
                Button("🎁 我的生日") { createBirthday(myself: true) }
                    .disabled(existingBirthday(myself: true) != nil)
                Button("💕 在一起纪念日") { createAnniversary() }
                    .disabled(hasAnniversary())
                Button("🎉 添加常见节日") { showPresetPicker = true }
                Button("✏️ 自定义") { createCustom() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showPresetPicker) {
                PresetHolidayPickerSheet()
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            emptyCTA(title: "添加伴侣生日 🎂", isPrimary: true) { createBirthday(myself: false) }
            emptyCTA(title: "添加我的生日 🎁", isPrimary: false) { createBirthday(myself: true) }
            emptyCTA(title: "添加在一起纪念日 💕", isPrimary: false) { createAnniversary() }
            Button("+ 其他纪念日 / 添加常见节日") { showCreateSheet = true }
                .foregroundStyle(AppTheme.colors.coral)
                .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private func emptyCTA(title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.typography.sized(18, weight: .bold))
                .foregroundStyle(isPrimary ? .white : AppTheme.colors.title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isPrimary ? AppTheme.colors.coral : AppTheme.colors.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(viewModel.events.sorted { nextKey($0) < nextKey($1) }) { event in
                row(event: event)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(event.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .onTapGesture { showEdit = event }
            }
        }
        .listStyle(.plain)
    }

    private func row(event: ImportantDate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.icon ?? defaultIcon(for: event.kind))
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.colors.coral)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                Text(dateLabel(for: event)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(daysLabel(for: event)).font(.subheadline).foregroundStyle(AppTheme.colors.coral)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.colors.surfaceElevated))
    }

    private func nextKey(_ event: ImportantDate) -> Date {
        event.nextOccurrence(after: .now) ?? .distantFuture
    }

    private func dateLabel(for event: ImportantDate) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/M/d"
        let base = fmt.string(from: event.dateValue)
        switch event.recurrence {
        case .lunarAnnual:
            return "\(base) · 农历"
        case .solarAnnual:
            return "\(base) · 每年"
        case .none:
            return base
        }
    }

    private func daysLabel(for event: ImportantDate) -> String {
        guard let days = event.daysUntilNext() else { return "-" }
        return days == 0 ? "今天" : "还有 \(days) 天"
    }

    private func defaultIcon(for kind: ImportantDateKind) -> String {
        switch kind {
        case .birthday: return "gift.fill"
        case .anniversary: return "heart.fill"
        case .holiday: return "sparkles"
        case .custom: return "star.fill"
        }
    }

    // MARK: - Existing checks

    private func existingBirthday(myself: Bool) -> ImportantDate? {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let partnerID = appContext.sessionStore.pairSpaceSummary?.partner?.id else { return nil }
        let target = myself ? myID : partnerID
        return viewModel.events.first { event in
            if case .birthday(let m) = event.kind { return m == target }
            return false
        }
    }

    private func hasAnniversary() -> Bool {
        viewModel.events.contains { event in
            if case .anniversary = event.kind { return true }
            return false
        }
    }

    // MARK: - Create actions

    private func createBirthday(myself: Bool) {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let partnerID = appContext.sessionStore.pairSpaceSummary?.partner?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let memberID = myself ? myID : partnerID
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .birthday(memberUserID: memberID),
            title: myself ? "我的生日" : "伴侣生日",
            dateValue: .now,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "gift.fill", presetHolidayID: nil, updatedAt: .now
        )
        showEdit = seed
    }

    private func createAnniversary() {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .anniversary, title: "我们的纪念日",
            dateValue: .now, recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "heart.fill", presetHolidayID: nil, updatedAt: .now
        )
        showEdit = seed
    }

    private func createCustom() {
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .custom, title: "",
            dateValue: .now, recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "star.fill", presetHolidayID: nil, updatedAt: .now
        )
        showEdit = seed
    }
}
