import SwiftUI

struct AnniversariesView: View {
    @Bindable var viewModel: AnniversariesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                CardSection(title: "最近一个重要日子", subtitle: "首版只承担基础记录与提醒") {
                    Text(viewModel.summaryText)
                        .font(.headline)
                        .foregroundStyle(AppTheme.colors.title)
                }

                CardSection(title: "纪念日列表") {
                    if viewModel.anniversaries.isEmpty {
                        EmptyStateCard(title: "暂无纪念日", message: "后续接新增、编辑、删除和排序。")
                    } else {
                        VStack(spacing: AppTheme.spacing.md) {
                            ForEach(viewModel.anniversaries, id: \.id) { anniversary in
                                VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                                    Text(anniversary.name)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.colors.title)
                                    Text(anniversary.eventDate, format: .dateTime.year().month().day())
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.colors.body)
                                }
                                .padding(AppTheme.spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.colors.background, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }

                Button("新增纪念日（占位）") {}
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.colors.accent)
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.md)
            .padding(.bottom, AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("纪念日")
        .task {
            if viewModel.loadState == .idle {
                await viewModel.load()
            }
        }
    }
}
