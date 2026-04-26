import SwiftUI

struct ImportantDatesManagementView: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit: ImportantDate?
    @State private var showPresetPicker = false
    /// PresetHolidayPickerSheet 内批量保存时如果因配额停止，标记下来；
    /// sheet 关闭动画完成 (.sheet onDismiss) 后再 requestQuotaUpsell，避免多 sheet 冲突
    @State private var presetPickerHitQuota = false
    @State private var showsPinCapAlert = false

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
                    Menu {
                        Button {
                            createBirthday(myself: false)
                        } label: {
                            Label("伴侣生日", systemImage: "gift.fill")
                        }
                        .disabled(existingBirthday(myself: false) != nil)

                        Button {
                            createBirthday(myself: true)
                        } label: {
                            Label("我的生日", systemImage: "person.crop.circle.fill")
                        }
                        .disabled(existingBirthday(myself: true) != nil)

                        Button {
                            createAnniversary()
                        } label: {
                            Label("在一起纪念日", systemImage: "heart.fill")
                        }
                        .disabled(hasAnniversary())

                        Divider()

                        Button {
                            guard quotaCheckPasses() else { return }
                            showPresetPicker = true
                        } label: {
                            Label("添加常见节日", systemImage: "calendar.badge.plus")
                        }

                        Button {
                            createCustom()
                        } label: {
                            Label("自定义", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加纪念日")
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
            .alert("已达 \(ImportantDatesViewModel.pinnedToTodayCap) 个固定上限",
                   isPresented: $showsPinCapAlert) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("Today 最多只能固定 \(ImportantDatesViewModel.pinnedToTodayCap) 个纪念日。请先取消其他纪念日的固定。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: AppTheme.spacing.md) {
            Image("EmptyAnniversary")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 140, height: 140)
                .padding(.top, AppTheme.spacing.lg)
                .padding(.bottom, AppTheme.spacing.sm)
                .accessibilityHidden(true)

            emptyCTA(title: "添加伴侣生日 🎂", isPrimary: true) { createBirthday(myself: false) }
            emptyCTA(title: "添加我的生日 🎁", isPrimary: false) { createBirthday(myself: true) }
            emptyCTA(title: "添加在一起纪念日 💕", isPrimary: false) { createAnniversary() }
            Button("+ 其他纪念日 / 添加常见节日") {
                guard quotaCheckPasses() else { return }
                showPresetPicker = true
            }
                .foregroundStyle(AppTheme.colors.pairAccent)
                .padding(.top, AppTheme.spacing.xs)
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
                .padding(.vertical, AppTheme.spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radius.md)
                        .fill(isPrimary ? AppTheme.colors.coral : AppTheme.colors.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var list: some View {
        // Plain list with default row separators only — the previous design
        // wrapped each row in a surfaceElevated rounded card on top of the
        // separator, which read as visually heavy and redundant. Per
        // user feedback (build-7 partner-side review), drop the card and
        // keep the iOS-native hairline separator as the sole row chrome.
        List {
            ForEach(orderedEvents) { event in
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
                    .onTapGesture { showEdit = event }
            }
        }
        .listStyle(.plain)
    }

    private func row(event: ImportantDate) -> some View {
        HStack(spacing: AppTheme.spacing.md) {
            // Pin toggle (spec §6.1) — leading icon, rose-tinted, single-tap toggle.
            Button {
                togglePin(event: event)
            } label: {
                Image(systemName: event.isPinnedToToday ? "bookmark.fill" : "bookmark")
                    .font(AppTheme.typography.sized(16, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.rose)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.isPinnedToToday ? "取消固定到 Today" : "固定到 Today")

            Image(systemName: event.icon ?? defaultIcon(for: event.kind))
                .font(AppTheme.typography.sized(20))
                .foregroundStyle(AppTheme.colors.rose)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                Text(displayTitle(for: event)).font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                Text(dateLabel(for: event)).font(AppTheme.typography.textStyle(.caption1)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(daysLabel(for: event)).font(AppTheme.typography.textStyle(.subheadline)).foregroundStyle(AppTheme.colors.rose)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayTitle(for: event)))
        .accessibilityValue(Text("\(dateLabel(for: event))，\(daysLabel(for: event))"))
        .accessibilityHint(Text("轻点编辑这个纪念日"))
    }

    private func nextKey(_ event: ImportantDate) -> Date {
        event.nextOccurrence(after: .now) ?? .distantFuture
    }

    /// Pinned items float to the top (spec §6.1). Within each group items
    /// stay sorted by displayAnchorDate so the user's next event is always
    /// visually closest.
    private var orderedEvents: [ImportantDate] {
        viewModel.events.sorted { lhs, rhs in
            if lhs.isPinnedToToday != rhs.isPinnedToToday {
                return lhs.isPinnedToToday
            }
            return lhs.displayAnchorDate() < rhs.displayAnchorDate()
        }
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

    /// Spec §6.1. Caps at 6 simultaneously pinned; pinning a 7th opens an alert.
    private func togglePin(event: ImportantDate) {
        if !event.isPinnedToToday,
           !ImportantDatesViewModel.canPinAnotherToToday(events: viewModel.events) {
            showsPinCapAlert = true
            return
        }
        var updated = event
        updated.isPinnedToToday.toggle()
        updated.updatedAt = .now
        Task { await viewModel.updateExisting(updated) }
        HomeInteractionFeedback.selection()
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
            icon: "gift.fill", presetHolidayID: nil, updatedAt: .now
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
            icon: "heart.fill", presetHolidayID: nil, updatedAt: .now
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
            icon: "star.fill", presetHolidayID: nil, updatedAt: .now
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
