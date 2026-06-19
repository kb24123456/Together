import SwiftUI

struct RoutinesListContent: View {
    @Bindable var viewModel: RoutinesViewModel
    let isPresented: Bool
    let contentTopPadding: CGFloat
    let contentBottomPadding: CGFloat

    @Environment(AppContext.self) private var appContext
    @State private var selectedCycle: PeriodicCycle = .weekly
    @State private var isTaskReorderingActive = false

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
                .padding(.top, AppTheme.spacing.xs)
                .padding(.bottom, AppTheme.spacing.xs)

            if viewModel.tasks.isEmpty && viewModel.loadState == .loaded {
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
            RoutinesEditorSheet(viewModel: viewModel, initialCycle: viewModel.editorDefaultCycle)
        }
        .sheet(isPresented: $viewModel.isDetailPresented) {
            RoutinesDetailSheet(viewModel: viewModel)
        }
        .task(id: appContext.sessionStore.currentSpace?.id) {
            appContext.router.pendingPeriodicCycle = selectedCycle
            await viewModel.loadIfNeeded()
        }
        .onChange(of: selectedCycle) { _, cycle in
            appContext.router.pendingPeriodicCycle = cycle
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
        HStack(spacing: AppTheme.spacing.sm) {
            ForEach(cycleTabs, id: \.self) { cycle in
                Button {
                    HomeInteractionFeedback.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedCycle = cycle
                    }
                } label: {
                    HStack(spacing: AppTheme.spacing.xs) {
                        Text(cycle.title)
                            .font(AppTheme.typography.sized(18, weight: selectedCycle == cycle ? .bold : .semibold))
                            .foregroundStyle(
                                selectedCycle == cycle
                                    ? AppTheme.colors.title
                                    : AppTheme.colors.textTertiary
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

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
                    .padding(.horizontal, AppTheme.spacing.md)
                    .padding(.vertical, AppTheme.spacing.sm)
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
            if isTaskReorderingActive {
                routinesReorderingControl
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(
                        EdgeInsets(
                            top: AppTheme.spacing.xxs,
                            leading: AppTheme.spacing.xl,
                            bottom: AppTheme.spacing.sm,
                            trailing: AppTheme.spacing.xl
                        )
                    )
                    .listRowBackground(AppTheme.colors.background)
                    .listRowSeparator(.hidden)
            }

            ForEach(currentTasks) { task in
                RoutinesTaskRow(task: task, viewModel: viewModel)
                    .listRowInsets(
                        EdgeInsets(
                            top: AppTheme.spacing.xxs,
                            leading: AppTheme.spacing.xl,
                            bottom: AppTheme.spacing.xxs,
                            trailing: AppTheme.spacing.xl
                        )
                    )
                    .listRowBackground(AppTheme.colors.background)
                    .listRowSeparator(.hidden)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            guard isTaskReorderingActive == false else { return }
                            HomeInteractionFeedback.selection()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                isTaskReorderingActive = true
                            }
                        }
                    )
                    .modifier(
                        RoutinesSwipeActionsModifier(
                            isEnabled: isTaskReorderingActive == false,
                            canDelete: viewModel.canDeletePeriodicTask(task),
                            onDelete: {
                                HomeInteractionFeedback.delete()
                                Task {
                                    await viewModel.deleteTask(taskID: task.id)
                                }
                            }
                        )
                    )
            }
            .onMove { fromOffsets, toOffset in
                Task {
                    await viewModel.reorderTasks(currentTasks, fromOffsets: fromOffsets, toOffset: toOffset)
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
        .environment(\.editMode, .constant(isTaskReorderingActive ? EditMode.active : EditMode.inactive))
        .applyScrollEdgeProtection()
    }

    private var routinesReorderingControl: some View {
        Button {
            HomeInteractionFeedback.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                isTaskReorderingActive = false
            }
        } label: {
            HStack(spacing: AppTheme.spacing.xs) {
                Image(systemName: "line.3.horizontal")
                    .font(AppTheme.typography.sized(12, weight: .bold))
                Text("完成排序")
                    .font(AppTheme.typography.sized(13, weight: .semibold))
            }
            .foregroundStyle(AppTheme.colors.sky)
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.colors.sky.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("退出例行事务排序模式")
    }

    // MARK: - Empty States

    private var routinesEmptyState: some View {
        VStack(spacing: AppTheme.spacing.xl) {
            VStack(spacing: AppTheme.spacing.md) {
                Image("EmptyRoutines")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)

                Text("还没有例行事务")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                Text("添加需要定期完成的事务")
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.38))
            }

            Button {
                HomeInteractionFeedback.selection()
                appContext.router.pendingPeriodicCycle = selectedCycle
                appContext.router.activeComposer = .newPeriodicTask
            } label: {
                HStack(spacing: AppTheme.spacing.xs) {
                    Image(systemName: "plus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))

                    Text("新建例行事务")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.vertical, AppTheme.spacing.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacing.xl)
    }

    private var emptyTabState: some View {
        VStack(spacing: AppTheme.spacing.xl) {
            VStack(spacing: AppTheme.spacing.md) {
                Image("EmptyRoutines")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)

                Text("暂无\(selectedCycle.title)事务")
                    .font(AppTheme.typography.sized(17, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.6))

                Text("点击下方按钮添加")
                    .font(AppTheme.typography.sized(14, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.38))
            }

            Button {
                HomeInteractionFeedback.selection()
                appContext.router.pendingPeriodicCycle = selectedCycle
                appContext.router.activeComposer = .newPeriodicTask
            } label: {
                HStack(spacing: AppTheme.spacing.xs) {
                    Image(systemName: "plus")
                        .font(AppTheme.typography.sized(14, weight: .semibold))
                    Text("新建例行事务")
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, AppTheme.spacing.lg)
                .padding(.vertical, AppTheme.spacing.sm)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppTheme.colors.surfaceElevated)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacing.xl)
    }

}

private struct RoutinesSwipeActionsModifier: ViewModifier {
    let isEnabled: Bool
    let canDelete: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if canDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
        } else {
            content
        }
    }
}
