import SwiftUI

struct HomeView: View {
    @Environment(AppContext.self) private var appContext
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
            topArea
            Spacer(minLength: 0)
        }
        .safeAreaPadding(.top, AppTheme.spacing.sm)
        .background(AppTheme.colors.background.ignoresSafeArea())
        .fontDesign(.rounded)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            FloatingComposerButton(
                onCreateItem: { appContext.router.activeComposer = .newItem },
                onCreateDecision: { appContext.router.activeComposer = .newDecision }
            )
            .padding(.trailing, AppTheme.spacing.lg)
            .padding(.bottom, AppTheme.spacing.lg)
        }
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
}
