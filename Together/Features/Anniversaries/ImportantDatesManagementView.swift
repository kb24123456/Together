import SwiftUI

struct ImportantDatesManagementView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit: ImportantDate?
    @State private var showPresetPicker = false
    /// PresetHolidayPickerSheet 内批量保存时如果因配额停止，标记下来；
    /// sheet 关闭动画完成 (.sheet onDismiss) 后再 requestQuotaUpsell，避免多 sheet 冲突
    @State private var presetPickerHitQuota = false

    private var viewModel: ImportantDatesViewModel {
        appContext.importantDatesViewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.events.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("纪念日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    addMenu
                }
            }
            .sheet(item: $showEdit) { event in
                ImportantDateEditSheet(event: event)
            }
            .sheet(isPresented: $showPresetPicker, onDismiss: {
                if presetPickerHitQuota {
                    presetPickerHitQuota = false
                    viewModel.requestQuotaUpsell()
                }
            }) {
                PresetHolidayPickerSheet(onQuotaHit: { presetPickerHitQuota = true })
            }
            .onChange(of: viewModel.pendingUpsellTrigger) { _, new in
                if let trigger = new {
                    appContext.rootPaywallPresentation.requestTrigger(trigger)
                }
            }
            // ImportantDatesManagementView 本身是 HomeView 的 sheet——
            // 必须在此层也挂一份 paywallRootSheet，paywall 才能嵌套在 management sheet 之上 present。
            // 否则 AppRoot 顶层的 .sheet 被 management sheet 占着，iOS 多 sheet 限制会卡住 paywall。
            .paywallRootSheet(appContext)
        }
        .task {
            // postLaunch may have fired before the pair was ready (e.g. right
            // after a fresh re-pair), leaving viewModel.spaceID nil and load()
            // short-circuiting. Re-configure here now that the user has
            // definitely entered a paired context.
            if let pairSpaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id {
                viewModel.configure(spaceID: pairSpaceID)
            }
            await viewModel.load()
        }
    }

    // MARK: - Header & Add Actions

    private var addMenu: some View {
        Menu {
            Button {
                HomeInteractionFeedback.selection()
                createCustom()
            } label: {
                Label("自定义", systemImage: "star")
            }

            Button {
                HomeInteractionFeedback.selection()
                guard quotaCheckPasses() else { return }
                showPresetPicker = true
            } label: {
                Label("添加常见节日", systemImage: "calendar.badge.plus")
            }

            Button {
                HomeInteractionFeedback.selection()
                createAnniversary()
            } label: {
                Label("在一起纪念日", systemImage: "heart.fill")
            }
            .disabled(hasAnniversary())

            Button {
                HomeInteractionFeedback.selection()
                createBirthday(myself: true)
            } label: {
                Label("我的生日", systemImage: "gift.fill")
            }
            .disabled(existingBirthday(myself: true) != nil)

            Button {
                HomeInteractionFeedback.selection()
                createBirthday(myself: false)
            } label: {
                Label("伴侣生日", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(existingBirthday(myself: false) != nil)
        } label: {
            Image(systemName: "plus")
                .font(AppTheme.typography.textStyle(.body, weight: .semibold))
        }
        .accessibilityLabel("添加纪念日")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "还没有纪念日",
            systemImage: "heart.text.square",
            description: Text("点击右上角加号添加重要日期")
        )
    }

    // MARK: - List

    private var list: some View {
        // Plain list with default row separators only — the previous design
        // wrapped each row in a surfaceElevated rounded card on top of the
        // separator, which read as visually heavy and redundant. Per
        // user feedback (build-7 partner-side review), drop the card and
        // keep the iOS-native hairline separator as the sole row chrome.
        List {
            ForEach(viewModel.events.sorted { nextKey($0) < nextKey($1) }) { event in
                row(event: event)
                    .listRowInsets(.init(top: AppTheme.spacing.md, leading: AppTheme.spacing.md, bottom: AppTheme.spacing.md, trailing: AppTheme.spacing.md))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            HomeInteractionFeedback.delete()
                            Task { await viewModel.delete(event.id) }
                        } label: {
                            Label("删除", systemImage: "trash.fill")
                        }
                        .tint(.red)
                    }
            }
        }
        .listStyle(.plain)
    }

    private func row(event: ImportantDate) -> some View {
        Button {
            showEdit = event
        } label: {
            HStack(alignment: .center, spacing: AppTheme.spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(displayTitle(for: event))
                        .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)
                    Text(dateLabel(for: event))
                        .font(AppTheme.typography.textStyle(.caption1))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppTheme.spacing.sm)

                HStack(spacing: AppTheme.spacing.sm) {
                    VStack(alignment: .trailing, spacing: AppTheme.spacing.xxs) {
                        Text(nextDaysLabel(for: event))
                            .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if event.supportsElapsedDaysDisplay && event.showsElapsedDays {
                            Text(elapsedDaysLabel(for: event))
                                .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                                .foregroundStyle(AppTheme.colors.rose.opacity(0.82))
                                .contentTransition(.numericText())
                        }
                    }
                    .multilineTextAlignment(.trailing)

                    if event.supportsElapsedDaysDisplay {
                        Toggle(
                            "同时展示累计天数",
                            isOn: elapsedDaysBinding(for: event)
                        )
                        .labelsHidden()
                        .tint(AppTheme.colors.rose)
                        .fixedSize()
                        .accessibilityLabel("同时展示累计天数")
                        .accessibilityValue(event.showsElapsedDays ? "已开启" : "已关闭")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayTitle(for: event)))
        .accessibilityValue(Text(accessibilityValue(for: event)))
        .accessibilityHint(Text(event.supportsElapsedDaysDisplay ? "轻点编辑，使用开关控制是否显示累计天数" : "轻点编辑这个纪念日"))
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

    private func nextDaysLabel(for event: ImportantDate) -> String {
        guard let days = event.daysUntilNext() else { return "-" }
        return days == 0 ? "今天" : "还有 \(days) 天"
    }

    private func elapsedDaysLabel(for event: ImportantDate) -> String {
        "已经 \(max(0, event.daysSinceStart)) 天"
    }

    /// Birthday rows are viewer-relative — partner A's "伴侣生日" must read as
    /// "我的生日" to partner B (and vice versa). Non-birthday rows pass through
    /// the stored title unchanged.
    /// Compares against `currentSupabaseUserID` (cross-device unique) rather
    /// than the local `currentUser.id` (device-local).
    private func displayTitle(for event: ImportantDate) -> String {
        event.displayTitle(
            viewerSupabaseUserID: appContext.currentSupabaseUserID,
            partnerDisplayName: appContext.sessionStore.pairSpaceSummary?.partner?.displayName
        )
    }

    private func elapsedDaysBinding(for event: ImportantDate) -> Binding<Bool> {
        Binding(
            get: { event.showsElapsedDays },
            set: { newValue in
                updateElapsedDaysPreference(for: event, showsElapsedDays: newValue)
            }
        )
    }

    private func updateElapsedDaysPreference(for event: ImportantDate, showsElapsedDays: Bool) {
        guard event.supportsElapsedDaysDisplay else { return }
        var updated = event
        updated.showsElapsedDays = showsElapsedDays
        updated.updatedAt = .now
        HomeInteractionFeedback.selection()
        Task {
            await viewModel.save(updated)
        }
    }

    private func accessibilityValue(for event: ImportantDate) -> String {
        if event.supportsElapsedDaysDisplay && event.showsElapsedDays {
            return "\(dateLabel(for: event))，\(nextDaysLabel(for: event))，\(elapsedDaysLabel(for: event))"
        }
        return "\(dateLabel(for: event))，\(nextDaysLabel(for: event))"
    }

    // MARK: - Existing checks

    private func existingBirthday(myself: Bool) -> ImportantDate? {
        guard let myID = appContext.currentSupabaseUserID,
              let partnerID = appContext.partnerSupabaseUserID else { return nil }
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
        guard quotaCheckPasses() else { return }
        // Use Supabase auth.uid (cross-device unique) for memberUserID and
        // creatorID so the row reads identically on both partners' devices.
        // Local User.id differs across devices for the same Apple ID after
        // a re-pair / reinstall, which broke "我的生日" detection on the
        // non-creating side (build-6 paired testing showed partner B saw
        // partner A's "伴侣生日" rendered as "{partnerA's name}的生日"
        // because partner A's local ID never matches partner B's local ID).
        guard let mySupabaseID = appContext.currentSupabaseUserID,
              let partnerSupabaseID = appContext.partnerSupabaseUserID,
              let myLocalID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let memberID = myself ? mySupabaseID : partnerSupabaseID
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myLocalID,
            kind: .birthday(memberUserID: memberID),
            title: myself ? "我的生日" : "伴侣生日",
            dateValue: .now,
            recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "gift.fill", presetHolidayID: nil,
            showsElapsedDays: false,
            updatedAt: .now
        )
        showEdit = seed
    }

    private func createAnniversary() {
        guard quotaCheckPasses() else { return }
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .anniversary, title: "我们的纪念日",
            dateValue: .now, recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "heart.fill", presetHolidayID: nil,
            showsElapsedDays: false,
            updatedAt: .now
        )
        showEdit = seed
    }

    private func createCustom() {
        guard quotaCheckPasses() else { return }
        guard let myID = appContext.sessionStore.currentUser?.id,
              let spaceID = appContext.sessionStore.pairSpaceSummary?.sharedSpace.id else { return }
        let seed = ImportantDate(
            id: UUID(), spaceID: spaceID, creatorID: myID,
            kind: .custom, title: "",
            dateValue: .now, recurrence: .solarAnnual,
            notifyDaysBefore: 7, notifyOnDay: true,
            icon: "star.fill", presetHolidayID: nil,
            showsElapsedDays: false,
            updatedAt: .now
        )
        showEdit = seed
    }

    /// 弹 EditSheet 之前的配额预检：超额时直接 requestQuotaUpsell 让 root sheet 弹 paywall，
    /// 不打开 EditSheet——避免 EditSheet 与 paywall sheet 的多 sheet 冲突。
    private func quotaCheckPasses() -> Bool {
        if viewModel.canCreateAnotherForCurrentUser() { return true }
        viewModel.requestQuotaUpsell()
        return false
    }
}
