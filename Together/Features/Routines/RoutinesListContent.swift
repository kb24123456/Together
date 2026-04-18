import SwiftUI

struct RoutinesListContent: View {
    @Bindable var viewModel: RoutinesViewModel
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat

    @Environment(AppContext.self) private var appContext
    @State private var selectedCycle: PeriodicCycle = .weekly

    private var cycleTabs: [PeriodicCycle] {
        [.weekly, .monthly, .quarterly, .yearly]
    }

    private var currentTasks: [PeriodicTask] {
        let all: [PeriodicTask]
        switch selectedCycle {
        case .weekly: all = viewModel.weeklyTasks
        case .monthly: all = viewModel.monthlyTasks
        case .quarterly: all = viewModel.quarterlyTasks
        case .yearly: all = viewModel.yearlyTasks
        }
        return all.sorted { lhs, rhs in
            let lhsCompleted = viewModel.isCompleted(lhs)
            let rhsCompleted = viewModel.isCompleted(rhs)
            if lhsCompleted != rhsCompleted { return !lhsCompleted }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            cycleTabBar
                .padding(.top, contentTopPadding)

            periodInfoBar
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if viewModel.tasks.isEmpty && viewModel.loadState == .loaded && !appContext.sessionStore.isViewingPairSpace {
                ScrollView {
                    routinesEmptyState
                        .padding(.bottom, contentBottomPadding)
                }
                .scrollIndicators(.hidden)
            } else if currentTasks.isEmpty {
                ScrollView {
                    emptyTabState
                        .padding(.bottom, contentBottomPadding)
                }
                .scrollIndicators(.hidden)
            } else {
                taskList
            }
        }
        .background(GradientGridBackground())
        .sheet(isPresented: $viewModel.isEditorPresented) {
            RoutinesEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isDetailPresented) {
            RoutinesDetailSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.load()
        }
        .task(id: appContext.sessionStore.currentSpace?.id) {
            await viewModel.reload()
        }
        .onChange(of: isPresented) { _, newValue in
            guard newValue else { return }
            guard appContext.router.shouldAutoSelectPendingCycle else { return }
            appContext.router.shouldAutoSelectPendingCycle = false

            let pending = viewModel.pendingSummary(referenceDate: viewModel.referenceDate)
            if let firstPending = pending.first {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    selectedCycle = firstPending.0
                }
            }
        }
    }

    // MARK: - Capsule Tab Bar

    private var cycleTabBar: some View {
        HStack(spacing: 10) {
            ForEach(cycleTabs, id: \.self) { cycle in
                Button {
                    HomeInteractionFeedback.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedCycle = cycle
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(cycle.title)
                            .font(AppTheme.typography.sized(18, weight: selectedCycle == cycle ? .bold : .semibold))
                            .foregroundStyle(
                                selectedCycle == cycle
                                    ? AppTheme.colors.title
                                    : AppTheme.colors.textTertiary
                            )

                        let count = viewModel.pendingCount(for: cycle)
                        if count > 0 {
                            Text("\(count)")
                                .font(AppTheme.typography.sized(12, weight: .bold))
                                .foregroundStyle(
                                    selectedCycle == cycle
                                        ? AppTheme.colors.coral
                                        : AppTheme.colors.body.opacity(0.36)
                                )
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.spacing.xl)
    }

    // MARK: - Period Info

    private var periodInfoBar: some View {
        HStack {
            Text(viewModel.sectionSummary(for: selectedCycle))
                .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.68))

            Text("·")
                .foregroundStyle(AppTheme.colors.textTertiary)

            Text("还剩 \(viewModel.daysRemaining(for: selectedCycle)) 天")
                .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                .foregroundStyle(AppTheme.colors.textTertiary)

            Spacer()

            periodProgressPill
        }
    }

    private var periodProgressPill: some View {
        let progress = viewModel.periodProgress(for: selectedCycle)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.colors.outline)

                Capsule()
                    .fill(AppTheme.colors.coral)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(width: 80, height: 4)
    }

    // MARK: - Task List (today style)

    private var taskList: some View {
        List {
            ForEach(currentTasks) { task in
                RoutinesTaskRow(task: task, viewModel: viewModel)
                    .listRowInsets(
                        EdgeInsets(
                            top: 4,
                            leading: AppTheme.spacing.xl,
                            bottom: 4,
                            trailing: AppTheme.spacing.xl
                        )
                    )
                    .listRowBackground(AppTheme.colors.background)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if viewModel.canDeletePeriodicTask(task) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteTask(taskID: task.id)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
            }

            Color.clear
                .frame(height: contentBottomPadding)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(AppTheme.colors.background)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .applyScrollEdgeProtection()
    }

    // MARK: - Empty States

    private var routinesEmptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppTheme.colors.accent.opacity(0.45))
                    .symbolEffect(.breathe.plain, options: .repeating)

                Text("还没有例行事务")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                Text("添加需要定期完成的事务")
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.38))
            }

            Button {
                HomeInteractionFeedback.selection()
                appContext.router.activeComposer = .newPeriodicTask
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))

                    Text("新建例行事务")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyTabState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppTheme.colors.sky.opacity(0.45))
                    .symbolEffect(.breathe.plain, options: .repeating)

                Text("暂无\(selectedCycle.title)事务")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                Text("点击下方按钮添加")
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.38))
            }

            Button {
                HomeInteractionFeedback.selection()
                appContext.router.activeComposer = .newPeriodicTask
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))
                    Text("新建例行事务")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

}
