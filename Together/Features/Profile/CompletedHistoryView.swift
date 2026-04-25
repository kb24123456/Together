import SwiftUI

struct CompletedHistoryView: View {
    @Bindable var viewModel: CompletedHistoryViewModel
    @Environment(AppContext.self) private var appContext
    @State private var selectedItem: Item?

    var body: some View {
        List {
            // Grace period 横幅置顶（高于 hero）—— 硬时间窗通知优先级最高。
            // 用 effectiveStatus 含 DEBUG override，让 picker 切到 grace 也能验证横幅渲染。
            if case .gracePeriod(_, let logbookFullUntil) = appContext.container.premiumGate.effectiveStatus {
                GracePeriodBanner(
                    logbookFullUntil: logbookFullUntil,
                    onTap: { daysRemaining in
                        appContext.rootPaywallPresentation.requestTrigger(
                            .graceExpiring(daysRemaining: daysRemaining)
                        )
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if viewModel.isPairMode, let summary = viewModel.pairSummary {
                LogbookPairSummaryHero(summary: summary)
                    .listRowBackground(AppTheme.colors.background)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            if viewModel.sections.isEmpty {
                if viewModel.isPairMode == false {
                    emptySection
                }
            } else {
                ForEach(viewModel.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                historyRow(for: item)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.colors.surface)
                            .listRowSeparator(.hidden)
                            .task {
                                await viewModel.loadMoreIfNeeded(currentItem: item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if viewModel.isArchived(item) {
                                    Button("移回当前列表", systemImage: "arrow.uturn.backward.circle") {
                                        Task {
                                            await viewModel.restore(item)
                                        }
                                    }
                                    .tint(AppTheme.colors.selectionTint)
                                }

                                Button("删除", systemImage: "trash") {
                                    Task {
                                        await viewModel.delete(item)
                                    }
                                }
                                .tint(AppTheme.colors.danger)
                            }
                        }
                    }
                }

                if viewModel.isLoading {
                    loadingRow
                }
            }
        }
        .listStyle(.insetGrouped)
        .applyScrollEdgeProtection()
        .scrollContentBackground(.hidden)
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("日志")
        .searchable(text: $viewModel.searchText, prompt: "搜索已完成任务")
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                detailView(for: item)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: viewModel.searchText) {
            await viewModel.reload()
        }
    }

    private var emptySection: some View {
        EmptyStateCard(
            title: "还没有历史任务",
            message: "已完成任务会在这里沉淀，Today 只保留当前仍需处理的任务。",
            illustration: "EmptyHistory"
        )
        .listRowInsets(EdgeInsets(top: AppTheme.spacing.lg, leading: AppTheme.spacing.lg, bottom: AppTheme.spacing.lg, trailing: AppTheme.spacing.lg))
        .listRowBackground(AppTheme.colors.background)
        .listRowSeparator(.hidden)
    }

    private var loadingRow: some View {
        HStack(spacing: AppTheme.spacing.md) {
            ProgressView()
            Text("正在加载更多历史任务")
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(AppTheme.colors.background)
        .listRowSeparator(.hidden)
    }

    private func historyRow(for item: Item) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing.md) {
            if viewModel.isPairMode {
                completionAvatar(for: item)
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text(item.title)
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)

                Text(viewModel.subtitle(for: item))
                    .font(AppTheme.typography.textStyle(.subheadline))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.72))

                VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                    Text(viewModel.completedDateText(for: item))
                    if viewModel.isArchived(item) {
                        Text(viewModel.archivedDateText(for: item))
                    }
                }
                .font(AppTheme.typography.textStyle(.caption1))
                .foregroundStyle(AppTheme.colors.body.opacity(0.64))
            }
        }
        .padding(.vertical, AppTheme.spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pairModeAccessibilityLabel(for: item))
    }

    @ViewBuilder
    private func completionAvatar(for item: Item) -> some View {
        // Prefer the authoritative completedByUserID; fall back to
        // lastActionByUserID for pre-migration rows that haven't been
        // touched by a post-upgrade completion action yet.
        let completerID = item.completedByUserID ?? item.lastActionByUserID
        let asset = viewModel.avatarAsset(forUserID: completerID)
        let displayName = viewModel.displayName(forUserID: completerID)
        UserAvatarView(
            avatarAsset: asset,
            displayName: displayName,
            size: 20,
            fillColor: AppTheme.colors.avatarWarm,
            symbolColor: AppTheme.colors.title.opacity(0.82),
            symbolFont: AppTheme.typography.sized(10, weight: .semibold),
            overrideImage: nil
        )
        .padding(.top, 2)
    }

    private func pairModeAccessibilityLabel(for item: Item) -> String {
        let completerID = item.completedByUserID ?? item.lastActionByUserID
        let completer = viewModel.displayName(forUserID: completerID)
        let completedDate = viewModel.completedDateText(for: item)
        if viewModel.isPairMode {
            return "\(completer) 完成 · \(item.title) · \(completedDate)"
        }
        return "\(item.title) · \(completedDate)"
    }

    private func detailView(for item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                CardSection(title: item.title, subtitle: viewModel.subtitle(for: item)) {
                    VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                        Text(viewModel.completedDateText(for: item))
                            .foregroundStyle(AppTheme.colors.body)
                        if viewModel.isArchived(item) {
                            Text(viewModel.archivedDateText(for: item))
                                .foregroundStyle(AppTheme.colors.body)
                        }

                        if let notes = item.notes, notes.isEmpty == false {
                            Divider()
                            Text(notes)
                                .foregroundStyle(AppTheme.colors.body)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
                    if viewModel.isArchived(item) {
                        Button("移回当前列表", systemImage: "arrow.uturn.backward.circle") {
                            Task {
                                await viewModel.restore(item)
                                selectedItem = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.colors.accent)
                    }

                    Button("删除任务", systemImage: "trash") {
                        Task {
                            await viewModel.delete(item)
                            selectedItem = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.colors.danger)
                }
            }
            .padding(AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("任务详情")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") {
                    selectedItem = nil
                }
            }
        }
    }
}

#Preview("Completed History") {
    NavigationStack {
        CompletedHistoryView(
            viewModel: CompletedHistoryViewModel(
                sessionStore: {
                    let store = SessionStore()
                    store.seedMock(
                        currentUser: MockDataFactory.makeCurrentUser(),
                        singleSpace: MockDataFactory.makeSingleSpace(),
                        pairSummary: nil
                    )
                    return store
                }(),
                itemRepository: MockItemRepository(),
                taskApplicationService: DefaultTaskApplicationService(
                    itemRepository: MockItemRepository(),
                    taskMessageRepository: MockTaskMessageRepository(),
                    syncCoordinator: NoOpSyncCoordinator(),
                    reminderScheduler: MockReminderScheduler()
                ),
                taskListRepository: MockTaskListRepository(),
                projectRepository: MockProjectRepository(reminderScheduler: MockReminderScheduler()),
                premiumGate: {
                    // Preview 里 inert PremiumGate + DEBUG 覆盖为 Pro，这样预览 UI
                    // 看到完整历史（不被 30 天 floor 裁剪）。
                    let date = SystemDateProvider()
                    let gate = PremiumGate(
                        rcClient: RevenueCatClient(),
                        grantsLoader: SupabaseGrantsLoader(client: SupabaseClientProvider.shared),
                        cache: PremiumStatusCache(defaults: .standard, dateProvider: date),
                        dateProvider: date
                    )
                    #if DEBUG
                    gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
                    #endif
                    return gate
                }()
            )
        )
    }
    .environment(AppContext.makeBootstrappedContext())
}
