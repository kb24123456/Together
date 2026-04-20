import SwiftUI

/// Appearance subscreen accessed via the "通知与外观" group's "外观" row.
/// Replaces the former capsule-tab picker that lived inline on the
/// Profile main scroll. Three options: 跟随系统 / 浅色 / 深色.
///
/// Persists via `AppearanceManager.mode` (identical to the old capsule tab).
struct ProfileAppearanceView: View {
    @Environment(AppContext.self) private var appContext

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { index, mode in
                    row(for: mode)

                    if index < AppearanceMode.allCases.count - 1 {
                        Divider()
                            .overlay(AppTheme.colors.hairline)
                            .padding(.leading, AppTheme.spacing.md)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.top, AppTheme.spacing.lg)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for mode: AppearanceMode) -> some View {
        let isSelected = appContext.appearanceManager.mode == mode
        return Button {
            HomeInteractionFeedback.selection()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                appContext.appearanceManager.mode = mode
            }
        } label: {
            HStack(spacing: AppTheme.spacing.md) {
                Text(mode.title)
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(AppTheme.colors.title)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTheme.typography.sized(14, weight: .bold))
                        .foregroundStyle(AppTheme.colors.selectionTint)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}
