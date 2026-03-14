import SwiftUI

enum ProjectsPresentationStyle {
    case screen
    case layer
}

struct ProjectsView: View {
    @Bindable var viewModel: ProjectsViewModel
    let style: ProjectsPresentationStyle

    init(
        viewModel: ProjectsViewModel,
        style: ProjectsPresentationStyle = .screen
    ) {
        self.viewModel = viewModel
        self.style = style
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                headerSection

                projectSection(
                    title: "推进中的项目",
                    subtitle: "长期推进的内容不进入 Today 主执行列表。",
                    projects: viewModel.activeProjects
                )

                projectSection(
                    title: "历史项目",
                    subtitle: "已完成和已归档的项目保留在这里。",
                    projects: viewModel.archivedProjects
                )
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, style == .layer ? 150 : AppTheme.spacing.xl)
            .padding(.bottom, style == .layer ? 240 : AppTheme.spacing.xl)
        }
        .background(backgroundView)
        .navigationTitle(style == .screen ? "项目" : "")
        .toolbar(style == .screen ? .visible : .hidden, for: .navigationBar)
        .task {
            guard viewModel.loadState == .idle else { return }
            await viewModel.load()
        }
    }

    private var backgroundView: some View {
        Group {
            if style == .layer {
                AppTheme.colors.projectLayerBackground.ignoresSafeArea()
            } else {
                AppTheme.colors.background.ignoresSafeArea()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            if style == .layer {
                Text("项目")
                    .font(AppTheme.typography.sized(34, weight: .bold))
                    .foregroundStyle(AppTheme.colors.projectLayerText)

                Text("把跨天推进的长期目标留在这一层，避免打断 Today 的执行节奏。")
                    .font(AppTheme.typography.textStyle(.body))
                    .foregroundStyle(AppTheme.colors.projectLayerSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func projectSection(
        title: String,
        subtitle: String,
        projects: [Project]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                Text(title)
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(sectionTitleColor)

                Text(subtitle)
                    .font(AppTheme.typography.textStyle(.subheadline))
                    .foregroundStyle(sectionSubtitleColor)
            }

            if projects.isEmpty {
                emptyState
            } else {
                VStack(spacing: AppTheme.spacing.md) {
                    ForEach(projects) { project in
                        projectCard(project)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Text("还没有项目")
                .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                .foregroundStyle(sectionTitleColor)

            Text("项目创建入口会在下一轮接进来，这一层先承接已有项目结构。")
                .foregroundStyle(sectionSubtitleColor)
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(cardOutline)
        }
    }

    private func projectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            HStack {
                Text(project.name)
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(sectionTitleColor)

                Spacer()

                StatusBadge(title: project.status.badgeTitle, tint: project.status.tint)
            }

            if let notes = project.notes {
                Text(notes)
                    .font(AppTheme.typography.textStyle(.subheadline))
                    .foregroundStyle(sectionSubtitleColor)
            }

            Text(project.targetDate.map { "截止于 \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "尚未设置截止日期")
                .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                .foregroundStyle(sectionSubtitleColor.opacity(0.86))

            Text("\(project.taskCount) 个关联事件")
                .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                .foregroundStyle(sectionSubtitleColor.opacity(0.86))
        }
        .padding(AppTheme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                .stroke(cardOutline)
        }
    }

    private var cardBackground: Color {
        style == .layer ? AppTheme.colors.projectLayerSurface : AppTheme.colors.surface
    }

    private var cardOutline: Color {
        style == .layer ? AppTheme.colors.projectLayerOutline : AppTheme.colors.outline
    }

    private var sectionTitleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerText : AppTheme.colors.title
    }

    private var sectionSubtitleColor: Color {
        style == .layer ? AppTheme.colors.projectLayerSecondaryText : AppTheme.colors.body
    }
}

private extension ProjectStatus {
    var badgeTitle: String {
        switch self {
        case .active:
            return "进行中"
        case .onHold:
            return "暂停"
        case .completed:
            return "已完成"
        case .archived:
            return "已归档"
        }
    }

    var tint: Color {
        switch self {
        case .active:
            return AppTheme.colors.accent
        case .onHold:
            return AppTheme.colors.warning
        case .completed:
            return AppTheme.colors.success
        case .archived:
            return AppTheme.colors.body
        }
    }
}
