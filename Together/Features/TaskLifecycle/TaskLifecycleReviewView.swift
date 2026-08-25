import SwiftUI

struct TaskLifecycleReviewView: View {
    let itemID: UUID
    let fallbackTitle: String
    let loadReview: (UUID) async throws -> TaskLifecycleReview

    @State private var review: TaskLifecycleReview?
    @State private var didFail = false

    var body: some View {
        List {
            if let review {
                resultSection(review)
                planSection(review)
                timelineSection(review)
            } else if didFail {
                ContentUnavailableView(
                    "回顾加载失败",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    description: Text("请稍后重试。")
                )
            } else {
                HStack {
                    Spacer()
                    ProgressView("正在整理任务履历")
                    Spacer()
                }
            }
        }
        .applySoftScrollEdgeTransition()
        .navigationTitle("任务回顾")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: itemID) {
            do {
                review = try await loadReview(itemID)
                didFail = false
            } catch {
                didFail = true
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ review: TaskLifecycleReview) -> some View {
        Section("结果") {
            LabeledContent("任务", value: review.title)
            LabeledContent(
                "最终完成耗时",
                value: review.completionDuration.map(TaskLifecycleFormatting.duration) ?? "尚未完成"
            )
            LabeledContent("正式创建", value: TaskLifecycleFormatting.dateTime(review.createdAt))
            if let firstCompletedAt = review.firstCompletedAt {
                LabeledContent(
                    review.historyCoverage == .complete ? "首次完成" : "更新后首次完成",
                    value: TaskLifecycleFormatting.dateTime(firstCompletedAt)
                )
            }
            if let completedAt = review.completedAt {
                LabeledContent("最终完成", value: TaskLifecycleFormatting.dateTime(completedAt))
            }
            LabeledContent("推迟", value: countText(review.postponeCount, coverage: review.historyCoverage))
            LabeledContent("恢复", value: countText(review.reopenCount, coverage: review.historyCoverage))
            if let coverage = review.historyCoverage.label {
                Label(coverage, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planSection(_ review: TaskLifecycleReview) -> some View {
        Section("计划") {
            LabeledContent(
                "首次计划",
                value: review.firstSchedule.map {
                    TaskLifecycleFormatting.schedule($0.dueAt, hasExplicitTime: $0.hasExplicitTime)
                } ?? "更新前未记录"
            )
            LabeledContent(
                "最后计划",
                value: review.finalSchedule.map {
                    TaskLifecycleFormatting.schedule($0.dueAt, hasExplicitTime: $0.hasExplicitTime)
                } ?? "更新前未记录"
            )
            LabeledContent(
                "累计推迟",
                value: review.historyCoverage == .complete
                    ? TaskLifecycleFormatting.duration(review.cumulativePostponement)
                    : "更新后 \(TaskLifecycleFormatting.duration(review.cumulativePostponement))"
            )
            if let drift = review.finalPlanDrift {
                LabeledContent("最终计划偏差", value: signedDuration(drift))
            }
        }
    }

    @ViewBuilder
    private func timelineSection(_ review: TaskLifecycleReview) -> some View {
        Section("时间线") {
            if review.events.isEmpty {
                Text("更新前的计划变化未记录。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(review.events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.kind.title)
                            Spacer()
                            Text(TaskLifecycleFormatting.dateTime(event.occurredAt))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let detail = TaskLifecycleFormatting.eventDetail(event) {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func countText(_ count: Int, coverage: TaskLifecycleHistoryCoverage) -> String {
        coverage == .complete ? "\(count) 次" : "更新后 \(count) 次"
    }

    private func signedDuration(_ interval: TimeInterval) -> String {
        if interval == 0 { return "无偏差" }
        return interval > 0
            ? "晚 \(TaskLifecycleFormatting.duration(interval))"
            : "早 \(TaskLifecycleFormatting.duration(abs(interval)))"
    }
}
