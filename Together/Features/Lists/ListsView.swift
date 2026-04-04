import SwiftUI

struct ListsView: View {
    @Bindable var viewModel: ListsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                if viewModel.isPairModeActive {
                    pairModeHeader
                } else {
                    CardSection(
                        title: "当前是个人清单视图",
                        subtitle: viewModel.spaceSummary
                    ) {
                        Text("这里展示的是单人空间下的清单数据。")
                            .font(AppTheme.typography.textStyle(.body, weight: .medium))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.76))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                CardSection(title: "系统清单", subtitle: "先把收集、Today 和即将到来分清") {
                    VStack(spacing: AppTheme.spacing.sm) {
                        ForEach(viewModel.systemLists) { list in
                            listRow(list, isShared: viewModel.isPairModeActive)
                        }
                    }
                }

                CardSection(title: "自定义清单", subtitle: "后续在这里继续扩展标签、分组和批量整理") {
                    VStack(spacing: AppTheme.spacing.sm) {
                        if viewModel.customLists.isEmpty {
                            EmptyStateCard(title: "还没有自定义清单", message: "下一步会把新建、编辑和整理流程接进这里。")
                        } else {
                            ForEach(viewModel.customLists) { list in
                                listRow(list, isShared: viewModel.isPairModeActive)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.spacing.xl)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("清单")
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewModel.loadState == .idle else { return }
            await viewModel.load()
        }
    }

    private var pairModeHeader: some View {
        CardSection(title: "双人清单", subtitle: viewModel.spaceSummary) {
            HStack(spacing: 12) {
                PairListModeAvatarStrip(
                    currentUser: viewModel.currentUser,
                    partner: viewModel.partner
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("共享清单")
                        .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("这里的系统清单和自定义清单都只读取双人空间，不会混入单人数据。")
                        .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func listRow(_ list: TaskList, isShared: Bool) -> some View {
        HStack(spacing: AppTheme.spacing.md) {
            Circle()
                .fill(list.kind == .custom ? AppTheme.colors.secondaryAccent : AppTheme.colors.accent)
                .frame(width: 10, height: 10)

            Text(list.name)
                .font(AppTheme.typography.textStyle(.body, weight: .medium))
                .foregroundStyle(AppTheme.colors.title)

            Spacer()

            if isShared {
                Text("共享")
                    .font(AppTheme.typography.sized(11, weight: .bold))
                    .foregroundStyle(AppTheme.colors.coral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppTheme.colors.coral.opacity(0.12))
                    )
            }

            Text("\(list.taskCount)")
                .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
        }
        .padding(.vertical, 2)
    }
}

private struct PairListModeAvatarStrip: View {
    let currentUser: User?
    let partner: User?

    var body: some View {
        HStack(spacing: -8) {
            avatar(for: currentUser, fill: AppTheme.colors.surfaceElevated)
            if partner != nil {
                avatar(for: partner, fill: AppTheme.colors.avatarWarm)
            }
        }
        .frame(width: partner == nil ? 40 : 70, height: 40, alignment: .leading)
    }

    @ViewBuilder
    private func avatar(for user: User?, fill: Color) -> some View {
        UserAvatarView(
            avatarAsset: user?.avatarAsset ?? .system("person.crop.circle.fill"),
            displayName: user?.displayName ?? "用户",
            size: 40,
            fillColor: fill,
            symbolColor: AppTheme.colors.title,
            symbolFont: AppTheme.typography.sized(14, weight: .semibold)
        )
        .overlay {
            Circle()
                .stroke(.white.opacity(0.92), lineWidth: 2)
        }
    }
}
