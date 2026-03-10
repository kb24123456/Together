import SwiftUI

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Bindable var viewModel: HomeViewModel

    @Namespace private var cardNamespace

    var body: some View {
        contentLayer
            .background(AppTheme.colors.background.ignoresSafeArea())
            .fontDesign(.rounded)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if viewModel.loadState == .idle {
                    await viewModel.load()
                }
            }
    }

    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
            topArea
            ScrollView {
                itemFlowSection
                    .padding(.horizontal, AppTheme.spacing.md)
                    .padding(.top, AppTheme.spacing.sm)
                    .safeAreaPadding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(viewModel.isBackgroundScrollLocked)
        }
        .safeAreaPadding(.top, AppTheme.spacing.sm)
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.isEditorPresented {
                FloatingComposerButton(
                    onCreateItem: { appContext.router.activeComposer = .newItem },
                    onCreateDecision: { appContext.router.activeComposer = .newDecision }
                )
                .padding(.trailing, AppTheme.spacing.lg)
                .padding(.bottom, AppTheme.spacing.lg)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: viewModel.isEditorPresented)
    }

    private var topArea: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text(viewModel.selectedDateTitle)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.colors.title)
                .padding(.horizontal, AppTheme.spacing.md)

            weekStrip
                .padding(.horizontal, AppTheme.spacing.md)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: AppTheme.spacing.sm) {
            ForEach(viewModel.weekDates, id: \.self) { date in
                Button {
                    viewModel.selectDate(date)
                } label: {
                    VStack(spacing: AppTheme.spacing.xs) {
                        Text(viewModel.weekdayLabel(for: date))
                            .font(.caption.weight(.medium))
                        Text(date, format: .dateTime.day())
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(viewModel.isSelectedDate(date) ? AppTheme.colors.accent : AppTheme.colors.title)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing.sm)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(viewModel.isSelectedDate(date) ? AppTheme.colors.accent : .clear)
                            .frame(width: 22, height: 3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var itemFlowSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            if viewModel.visibleItems.isEmpty {
                EmptyStateCard(
                    title: "这一天还没有事项",
                    message: "切换到别的日期，或新建一张事项卡。未指定完成日期的新事项会归到创建当天。"
                )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    TimelineRailView(itemCount: viewModel.visibleItems.count, spacing: 12)

                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.visibleItems) { item in
                            HomeItemCardView(
                                item: item,
                                surfaceStyle: viewModel.cardSurfaceStyle(for: item),
                                ownershipTokens: viewModel.ownershipTokens(for: item),
                                roleLabel: viewModel.roleLabel(for: item),
                                namespace: cardNamespace,
                                isExpandedSource: viewModel.isEditorStageVisible && viewModel.expandedEditorItemID == item.id,
                                onTap: { viewModel.presentEditor(for: item) },
                                onTogglePin: {
                                    Task {
                                        await viewModel.togglePin(for: item)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct TimelineRailView: View {
    let itemCount: Int
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<max(itemCount, 1), id: \.self) { index in
                VStack(spacing: 0) {
                    Circle()
                        .fill(.white)
                        .frame(width: index == 0 ? 18 : 14, height: index == 0 ? 18 : 14)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0.89, green: 0.40, blue: 0.54), lineWidth: 2)
                        )

                    if index < itemCount - 1 {
                        Rectangle()
                            .fill(Color(red: 0.89, green: 0.40, blue: 0.54).opacity(0.7))
                            .frame(width: 2, height: 106 + spacing)
                    }
                }
            }
        }
        .padding(.top, 22)
        .frame(width: 22)
    }
}
