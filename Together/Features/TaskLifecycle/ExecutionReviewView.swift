import SwiftUI

struct ExecutionReviewView: View {
    let loadReview: (ExecutionReviewRange, Date) async throws -> ExecutionReviewSnapshot
    let loadTaskReview: (UUID) async throws -> TaskLifecycleReview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRange: ExecutionReviewRange = .week
    @State private var snapshot: ExecutionReviewSnapshot?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var isMethodologyExpanded = false

    private enum ReviewRoute: Hashable {
        case task(itemID: UUID, title: String)
        case completedTasks
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                reviewHeader
                ExecutionReviewDottedDivider()

                Group {
                    if isLoading {
                        loadingState
                            .transition(.opacity)
                    } else if let snapshot, snapshot.range == selectedRange {
                        reviewContent(snapshot)
                            .id(snapshot.range)
                            .transition(.opacity)
                    } else if didFail {
                        failureState
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .applySoftScrollEdgeTransition()
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                rangeMenu
            }
        }
        .task(id: selectedRange) {
            await reload(for: selectedRange)
        }
        .navigationDestination(for: ReviewRoute.self) { route in
            switch route {
            case let .task(itemID, title):
                TaskLifecycleReviewView(
                    itemID: itemID,
                    fallbackTitle: title,
                    loadReview: loadTaskReview
                )
            case .completedTasks:
                if let snapshot {
                    completedTasks(snapshot)
                }
            }
        }
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
            Text("执行回顾")
                .font(AppTheme.typography.scaled(
                    34,
                    weight: .bold,
                    relativeTo: .largeTitle
                ))
                .foregroundStyle(AppTheme.colors.title)

            Text("\(periodTitle(for: headerInterval)) · 截至今天")
                .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, AppTheme.hierarchy.spacing.component)
        .padding(.bottom, AppTheme.hierarchy.spacing.section)
        .accessibilityElement(children: .combine)
    }

    private var headerInterval: DateInterval {
        if let snapshot, snapshot.range == selectedRange {
            return snapshot.interval
        }
        return selectedRange.interval(through: .now, calendar: .current)
    }

    private var rangeMenu: some View {
        Menu {
            ForEach(ExecutionReviewRange.allCases, id: \.self) { range in
                Button {
                    guard selectedRange != range else { return }
                    HomeInteractionFeedback.selection()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        isLoading = true
                        didFail = false
                        isMethodologyExpanded = false
                        selectedRange = range
                    }
                } label: {
                    if selectedRange == range {
                        Label(range.title, systemImage: "checkmark")
                    } else {
                        Text(range.title)
                    }
                }
            }
        } label: {
            HStack(spacing: AppTheme.hierarchy.spacing.inline) {
                Text(selectedRange.title)
                Image(systemName: "chevron.down")
                    .font(AppTheme.typography.hierarchy(.micro, weight: .bold))
            }
        }
        .accessibilityLabel("执行回顾范围")
        .accessibilityValue(selectedRange.title)
    }

    private var loadingState: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView("正在整理\(selectedRange.title)执行")
                .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
            Spacer(minLength: 0)
        }
        .frame(minHeight: 320)
        .padding(.horizontal, 24)
        .padding(.top, AppTheme.hierarchy.spacing.section)
        .padding(.bottom, AppTheme.hierarchy.spacing.page)
    }

    private var failureState: some View {
        VStack(spacing: AppTheme.hierarchy.spacing.component) {
            ContentUnavailableView(
                "回顾加载失败",
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                description: Text("请稍后重试。")
            )

            Button("重试") {
                Task { await reload(for: selectedRange) }
            }
            .buttonStyle(.bordered)
        }
        .frame(minHeight: 320)
        .padding(.horizontal, 24)
        .padding(.top, AppTheme.hierarchy.spacing.section)
        .padding(.bottom, AppTheme.hierarchy.spacing.page)
    }

    private func reviewContent(_ snapshot: ExecutionReviewSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            periodSummary(snapshot)

            if snapshot.completionCount > 0 {
                ExecutionReviewSection(title: "首次安排") {
                    Text(TaskLifecycleFormatting.firstScheduleSummary(snapshot))
                        .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, AppTheme.hierarchy.spacing.section)

                planChangeSection(snapshot)
                    .padding(.top, AppTheme.hierarchy.spacing.section)

                if snapshot.trends.isEmpty == false {
                    comparisonSection(snapshot)
                        .padding(.top, AppTheme.hierarchy.spacing.section)
                }

                if snapshot.noteworthyItems.isEmpty == false {
                    noteworthySection(snapshot.noteworthyItems)
                        .padding(.top, AppTheme.hierarchy.spacing.section)
                }

                methodologySection(snapshot)
                    .padding(.top, AppTheme.hierarchy.spacing.section)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, AppTheme.hierarchy.spacing.section)
        .padding(.bottom, AppTheme.hierarchy.spacing.page)
    }

    private func periodSummary(_ snapshot: ExecutionReviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
            Text(TaskLifecycleFormatting.executionSummary(snapshot))
                .font(AppTheme.typography.hierarchy(.title, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)

            if snapshot.completionCount > 0 {
                NavigationLink(value: ReviewRoute.completedTasks) {
                    Text("查看这 \(snapshot.completionCount) 项已完成任务")
                        .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func planChangeSection(_ snapshot: ExecutionReviewSnapshot) -> some View {
        ExecutionReviewSection(title: "安排变化") {
            VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
                Text(postponementText(snapshot))
                    .font(AppTheme.typography.hierarchy(.supporting, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)

            }
            .accessibilityElement(children: .combine)
        }
    }

    private func comparisonSection(_ snapshot: ExecutionReviewSnapshot) -> some View {
        ExecutionReviewSection(title: "同期比较") {
            VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
                ForEach(snapshot.trends) { trend in
                    Text(TaskLifecycleFormatting.executionComparison(trend, range: snapshot.range))
                        .font(AppTheme.typography.hierarchy(.supporting))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(comparisonAccessibilityLabel(trend, range: snapshot.range))
                }
            }
        }
    }

    private func comparisonAccessibilityLabel(_ trend: ExecutionReviewTrend, range: ExecutionReviewRange) -> String {
        let title = trend.metric == .firstPlanOnTimeRate ? "按首次安排完成" : "曾向后调整"
        let previous = range == .week ? "上周同期" : "上月同期"
        return "\(title)，\(range.title) \(trend.currentSampleCount) 项中有 \(trend.currentCount) 项，\(previous) \(trend.previousSampleCount) 项中有 \(trend.previousCount) 项"
    }

    private func noteworthySection(_ items: [ExecutionReviewNoteworthyItem]) -> some View {
        ExecutionReviewSection(title: "值得回看") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    if item.id != items.first?.id {
                        Rectangle()
                            .fill(AppTheme.colors.hairline)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }

                    NavigationLink(value: ReviewRoute.task(itemID: item.id, title: item.title)) {
                        ExecutionReviewTaskRow(
                            title: item.title,
                            detail: noteworthyDetail(item.reason)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看任务回顾")
                }
            }
        }
    }

    private func methodologySection(_ snapshot: ExecutionReviewSnapshot) -> some View {
        DisclosureGroup(isExpanded: $isMethodologyExpanded) {
            VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.related) {
                Text("仅回顾已完成的普通待办，不包含定期任务，也不代表全部计划的完成率。完成数量按最终完成时间归入当前自然周期；恢复为待办的任务暂不计入，归档不改变原周期，永久删除后不再计入。")
                Text("首次安排与向后调整只统计履历完整的任务；首次安排还需有有效排期。只有日期时按当天结束判断，设置了时间时按该时刻判断。首次安排可能来自默认日期，日期变化不代表执行好坏。")
                Text("同期比较只在双方对应指标都至少有 5 项有效样本时显示，以数量和各自分母呈现，不推断进步或退步。上月较短时比较截至上月结束。")
                Text(comparisonIntervalText(snapshot))
            }
            .font(AppTheme.typography.hierarchy(.micro))
            .foregroundStyle(AppTheme.colors.textTertiary)
            .padding(.top, AppTheme.hierarchy.spacing.related)
            .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text("统计说明")
                .font(AppTheme.typography.hierarchy(.supporting, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        }
        .tint(AppTheme.colors.body.opacity(0.46))
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    private func comparisonIntervalText(_ snapshot: ExecutionReviewSnapshot) -> String {
        let previous = snapshot.range.previousComparableInterval(
            through: snapshot.interval.end,
            calendar: .current
        )
        return "本次范围：\(TaskLifecycleFormatting.dateTime(snapshot.interval.start))—\(TaskLifecycleFormatting.dateTime(snapshot.interval.end))；对照范围：\(TaskLifecycleFormatting.dateTime(previous.start))—\(TaskLifecycleFormatting.dateTime(previous.end))。"
    }

    private func postponementText(_ snapshot: ExecutionReviewSnapshot) -> String {
        guard snapshot.postponementSampleCount > 0 else {
            return "暂无完整的安排变化记录"
        }
        if snapshot.postponementSampleCount == snapshot.completionCount {
            return "\(snapshot.completionCount) 项完成任务都有完整记录，其中 \(snapshot.postponedCompletionCount) 项曾向后调整"
        }
        return "\(snapshot.postponementSampleCount) 项有完整记录，其中 \(snapshot.postponedCompletionCount) 项曾向后调整"
    }

    private func noteworthyDetail(_ reason: ExecutionReviewNoteworthyReason) -> String {
        switch reason {
        case let .reopened(count, coverage):
            return "重新打开 \(count) 次\(coverageSuffix(coverage))"
        case let .postponed(count, _, coverage):
            return "安排向后调整 \(count) 次\(coverageSuffix(coverage))"
        case let .missedFirstPlan(completedAt, schedule):
            return "比首次安排晚完成 \(TaskLifecycleFormatting.planDelay(completedAt: completedAt, schedule: schedule))"
        }
    }

    private func coverageSuffix(_ coverage: TaskLifecycleHistoryCoverage) -> String {
        coverage.label.map { " · \($0)" } ?? ""
    }

    private func completedTasks(_ snapshot: ExecutionReviewSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("\(periodTitle(for: snapshot.interval)) · \(snapshot.completionCount) 项普通待办")
                    .font(AppTheme.typography.hierarchy(.supporting))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, AppTheme.hierarchy.spacing.component)

                ForEach(snapshot.completedItems) { item in
                    if item.id != snapshot.completedItems.first?.id {
                        Rectangle()
                            .fill(AppTheme.colors.hairline)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }

                    NavigationLink(value: ReviewRoute.task(itemID: item.id, title: item.title)) {
                        ExecutionReviewTaskRow(
                            title: item.title,
                            detail: "完成于 \(TaskLifecycleFormatting.dateTime(item.completedAt))"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看任务回顾")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, AppTheme.hierarchy.spacing.component)
            .padding(.bottom, AppTheme.hierarchy.spacing.page)
        }
        .applySoftScrollEdgeTransition()
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("\(snapshot.range.title)已完成")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func periodTitle(for interval: DateInterval) -> String {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        let startYear = calendar.component(.year, from: startDay)
        let endYear = calendar.component(.year, from: endDay)
        let startMonth = calendar.component(.month, from: startDay)
        let endMonth = calendar.component(.month, from: endDay)

        if calendar.isDate(startDay, inSameDayAs: endDay) {
            return startDay.formatted(.dateTime.month(.wide).day())
        }
        if startYear != endYear {
            return "\(startDay.formatted(.dateTime.year().month(.wide).day()))—\(endDay.formatted(.dateTime.year().month(.wide).day()))"
        }
        if startMonth != endMonth {
            return "\(startDay.formatted(.dateTime.month(.wide).day()))—\(endDay.formatted(.dateTime.month(.wide).day()))"
        }
        return "\(startDay.formatted(.dateTime.month(.wide).day()))—\(endDay.formatted(.dateTime.day()))"
    }

    private func reload(for range: ExecutionReviewRange) async {
        isLoading = true
        didFail = false

        do {
            let loadedSnapshot = try await loadReview(range, .now)
            try Task.checkCancellation()
            guard selectedRange == range else { return }

            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                snapshot = loadedSnapshot
                isLoading = false
            }
        } catch is CancellationError {
            return
        } catch {
            guard selectedRange == range else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                snapshot = nil
                isLoading = false
                didFail = true
            }
        }
    }
}

private struct ExecutionReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.component) {
            Text(title)
                .font(AppTheme.typography.hierarchy(.primary, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
                .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExecutionReviewDottedDivider: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                path,
                with: .color(AppTheme.colors.hairline),
                style: StrokeStyle(lineWidth: 1, dash: [2, 5])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

private struct ExecutionReviewTaskRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.hierarchy.spacing.component) {
            VStack(alignment: .leading, spacing: AppTheme.hierarchy.spacing.inline) {
                Text(title)
                    .font(AppTheme.typography.hierarchy(.primary, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)

                Text(detail)
                    .font(AppTheme.typography.hierarchy(.supporting))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.64))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "chevron.right")
                .font(AppTheme.typography.hierarchy(.micro, weight: .bold))
                .foregroundStyle(AppTheme.colors.body.opacity(0.34))
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppTheme.hierarchy.spacing.related)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
