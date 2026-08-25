import SwiftUI

struct PlanningReviewView: View {
    let loadReview: (PlanningReviewRange, Date) async throws -> PlanningReviewSnapshot
    let loadTaskReview: (UUID) async throws -> TaskLifecycleReview

    @Environment(AppContext.self) private var appContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedRange: PlanningReviewRange = .week
    @State private var snapshot: PlanningReviewSnapshot?
    @State private var isLoading = false
    @State private var didFail = false

    private struct ReviewRoute: Hashable {
        let itemID: UUID
        let title: String
    }

    var body: some View {
        List {
            if let snapshot {
                metricsSection(snapshot)
                if snapshot.trends.isEmpty == false {
                    trendSection(snapshot.trends)
                }
                riskSection(snapshot.riskItems)
                noteworthySection(snapshot.noteworthyItems)
                methodologySection(snapshot)
            } else if didFail {
                ContentUnavailableView(
                    "复盘加载失败",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    description: Text("请稍后重试。")
                )
            } else {
                HStack {
                    Spacer()
                    ProgressView("正在整理计划")
                    Spacer()
                }
            }
        }
        .applySoftScrollEdgeTransition()
        .navigationTitle("计划复盘")
        .navigationSubtitle(selectedRange.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(PlanningReviewRange.allCases, id: \.self) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            if selectedRange == range {
                                Label(range.title, systemImage: "checkmark")
                            } else {
                                Text(range.title)
                            }
                        }
                    }
                } label: {
                    Text(selectedRange.title)
                }
                .accessibilityLabel("复盘范围")
                .accessibilityValue(selectedRange.title)
            }
        }
        .task(id: selectedRange) {
            await reload()
        }
        .navigationDestination(for: ReviewRoute.self) { route in
            TaskLifecycleReviewView(
                itemID: route.itemID,
                fallbackTitle: route.title,
                loadReview: loadTaskReview
            )
        }
    }

    @ViewBuilder
    private func metricsSection(_ snapshot: PlanningReviewSnapshot) -> some View {
        Section("完成结果") {
            if snapshot.completionCount == 0 {
                Text("这个周期还没有已完成待办；当前计划风险仍会继续显示。")
                    .foregroundStyle(.secondary)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach(metrics(for: snapshot)) { metric in
                        metricRow(metric)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(metrics(for: snapshot)) { metric in
                        metricCell(metric)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func metricCell(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            if let rate = metric.rate {
                Gauge(value: rate, in: 0...1) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(AppTheme.colors.sky)
                    .accessibilityLabel(metric.title)
                    .accessibilityValue(metric.value)
            }
            Text(metric.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func metricRow(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(metric.title, value: metric.value)
            if let rate = metric.rate {
                Gauge(value: rate, in: 0...1) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(AppTheme.colors.sky)
            }
            Text(metric.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trendSection(_ trends: [PlanningTrend]) -> some View {
        Section("与上一周期相比") {
            ForEach(trends) { trend in
                Text(trendText(trend))
            }
        }
    }

    @ViewBuilder
    private func riskSection(_ items: [PlanningRiskItem]) -> some View {
        Section("当前计划风险") {
            if items.isEmpty {
                Text("暂未发现需要优先处理的计划风险。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        Task { await appContext.handleDeepLink(.task(item.id)) }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                Text(item.kind.title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let dueAt = item.dueAt {
                                Text(TaskLifecycleFormatting.schedule(
                                    dueAt,
                                    hasExplicitTime: item.hasExplicitTime
                                ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("返回首页并打开任务详情")
                }
            }
        }
    }

    @ViewBuilder
    private func noteworthySection(_ items: [PlanningNoteworthyItem]) -> some View {
        if items.isEmpty == false {
            Section("值得回看的任务") {
                ForEach(items) { item in
                    NavigationLink(value: ReviewRoute(itemID: item.id, title: item.title)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                            Text(noteworthyDetail(item.reason))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func noteworthyDetail(_ reason: PlanningNoteworthyReason) -> String {
        switch reason {
        case let .postponed(count, cumulativeDuration, coverage):
            let prefix = coverage == .complete ? "" : "更新后"
            return "\(prefix)推迟 \(count) 次，累计 \(TaskLifecycleFormatting.duration(cumulativeDuration))"
        case let .reopened(count, coverage):
            let prefix = coverage == .complete ? "" : "更新后"
            return "\(prefix)恢复 \(count) 次后完成"
        case let .completionDuration(duration):
            return "完成耗时 \(TaskLifecycleFormatting.duration(duration))"
        }
    }

    @ViewBuilder
    private func methodologySection(_ snapshot: PlanningReviewSnapshot) -> some View {
        Section {
            Text("按最终完成时间归入周期；恢复为待办的任务暂不计入。首次计划按时率会排除更新前历史不完整的任务。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func metrics(for snapshot: PlanningReviewSnapshot) -> [Metric] {
        [
            Metric(title: "完成任务", value: "\(snapshot.completionCount)", detail: "按最终完成时间", rate: nil),
            Metric(
                title: "中位完成耗时",
                value: snapshot.medianCompletionDuration.map(TaskLifecycleFormatting.duration) ?? "—",
                detail: "\(snapshot.validDurationSampleCount) 个有效样本",
                rate: nil
            ),
            Metric(
                title: "首次计划按时",
                value: percentage(snapshot.firstPlanOnTimeRate),
                detail: "\(snapshot.firstPlanSampleCount) 个有效样本",
                rate: snapshot.firstPlanOnTimeRate
            ),
            Metric(
                title: "最后计划按时",
                value: percentage(snapshot.finalPlanOnTimeRate),
                detail: "\(snapshot.finalPlanSampleCount) 个有效样本",
                rate: snapshot.finalPlanOnTimeRate
            ),
            Metric(
                title: "发生过推迟",
                value: percentage(snapshot.postponedProportion),
                detail: "\(snapshot.postponementSampleCount) 个有效样本",
                rate: snapshot.postponedProportion
            ),
            Metric(
                title: "计划记录缺失",
                value: "\(snapshot.unscheduledCompletionCount)",
                detail: "更新前数据，不计入按时率",
                rate: nil
            ),
        ]
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func trendText(_ trend: PlanningTrend) -> String {
        switch trend.metric {
        case .medianCompletionDuration:
            if abs(trend.delta) < 60 { return "完成耗时中位数与上一周期基本持平" }
            return trend.delta > 0
                ? "完成耗时中位数比上一周期多 \(TaskLifecycleFormatting.duration(trend.delta))"
                : "完成耗时中位数比上一周期少 \(TaskLifecycleFormatting.duration(abs(trend.delta)))"
        case .firstPlanOnTimeRate:
            return rateTrendText(title: "首次计划按时率", delta: trend.delta)
        case .postponedProportion:
            return rateTrendText(title: "推迟任务占比", delta: trend.delta)
        }
    }

    private func rateTrendText(title: String, delta: Double) -> String {
        let points = abs(delta * 100).formatted(.number.precision(.fractionLength(0)))
        if abs(delta) < 0.005 { return "\(title)与上一周期基本持平" }
        return delta > 0
            ? "\(title)比上一周期高 \(points) 个百分点"
            : "\(title)比上一周期低 \(points) 个百分点"
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await loadReview(selectedRange, .now)
            didFail = false
        } catch {
            snapshot = nil
            didFail = true
        }
    }
}

private struct Metric: Identifiable {
    let title: String
    let value: String
    let detail: String
    let rate: Double?
    var id: String { title }
}
