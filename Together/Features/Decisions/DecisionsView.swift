import SwiftUI

struct DecisionsView: View {
    @Bindable var viewModel: DecisionsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                templatePicker
                decisionSection(title: "待表态", decisions: viewModel.visiblePending, supportsArchive: false, supportsConvert: false)
                decisionSection(title: "暂未达成一致", decisions: viewModel.visibleStalled, supportsArchive: true, supportsConvert: false)
                decisionSection(title: "已达成一致", decisions: viewModel.visibleConsensus, supportsArchive: false, supportsConvert: true)
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.md)
            .padding(.bottom, AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("决策")
        .task {
            if viewModel.loadState == .idle {
                await viewModel.load()
            }
        }
    }

    private var templatePicker: some View {
        CardSection(title: "模板分类", subtitle: "先聚焦三种高频轻决策模板") {
            HStack(spacing: AppTheme.spacing.sm) {
                ForEach(DecisionTemplate.allCases, id: \.self) { template in
                    Button(template.title) {
                        viewModel.selectedTemplate = template
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.selectedTemplate == template ? AppTheme.colors.accent : AppTheme.colors.secondaryAccent)
                }
            }
        }
    }

    private func decisionSection(
        title: String,
        decisions: [Decision],
        supportsArchive: Bool,
        supportsConvert: Bool
    ) -> some View {
        CardSection(title: title) {
            if decisions.isEmpty {
                EmptyStateCard(title: "暂无内容", message: "这一层先保留分区和状态，不堆完整流程。")
            } else {
                VStack(spacing: AppTheme.spacing.md) {
                    ForEach(decisions, id: \.id) { decision in
                        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                                    Text(decision.title)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.colors.title)
                                    Text(decision.template.title)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.colors.body)
                                }
                                Spacer()
                                StatusBadge(title: decision.status.title, tint: statusTint(decision.status))
                            }

                            if let notes = decision.notes {
                                Text(notes)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.colors.body)
                            }

                            HStack(spacing: AppTheme.spacing.sm) {
                                ForEach(DecisionVoteValue.allCases, id: \.self) { vote in
                                    Button(vote.label(for: decision.template)) {
                                        Task {
                                            await viewModel.submitVote(for: decision, value: vote)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            HStack(spacing: AppTheme.spacing.sm) {
                                if supportsArchive {
                                    Button("归档") {
                                        Task {
                                            await viewModel.archive(decision)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if supportsConvert {
                                    Button("转为事项") {
                                        Task {
                                            await viewModel.convertToItem(decision)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.colors.accent)
                                }
                            }
                        }
                        .padding(AppTheme.spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.colors.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private func statusTint(_ status: DecisionStatus) -> Color {
        switch status {
        case .pendingResponse:
            AppTheme.colors.warning
        case .consensusReached:
            AppTheme.colors.success
        case .noConsensusYet:
            AppTheme.colors.secondaryAccent
        case .archived:
            AppTheme.colors.body
        }
    }
}
