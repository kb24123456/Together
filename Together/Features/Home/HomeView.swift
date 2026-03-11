import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                weekCalendarSection
                timelineSection
            }
            .padding(.horizontal, AppTheme.spacing.xl)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.top, 6)
        .background(backgroundView)
        .font(AppTheme.typography.body)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                AppTheme.colors.background,
                AppTheme.colors.backgroundSoft
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.headerDateText)
                    .font(AppTheme.typography.sized(38, weight: .bold))
                    .tracking(-1.1)
                    .foregroundStyle(AppTheme.colors.title)
            }
            .frame(height: 56, alignment: .center)

            Spacer(minLength: 0)

            HStack(spacing: -10) {
                avatarBubble(viewModel.partnerAvatar, tint: AppTheme.colors.avatarWarm)
                avatarBubble(viewModel.currentUserAvatar, tint: AppTheme.colors.avatarNeutral)
            }
            .padding(6)
            .background(AppTheme.colors.surface.opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.colors.outlineStrong.opacity(0.6), lineWidth: 1)
            }
            .frame(height: 56)
        }
    }

    private var weekCalendarSection: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.weekDates, id: \.self) { date in
                let isSelected = viewModel.isSelectedDate(date)
                Button {
                    guard !isSelected else { return }
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                        viewModel.selectDate(date)
                    }
                    triggerSoftDateFeedback()
                } label: {
                    VStack(spacing: 4) {
                        Text(date, format: .dateTime.day())
                            .font(
                                AppTheme.typography.sized(
                                    26,
                                    weight: isSelected ? .bold : .semibold
                                )
                            )
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.title
                                : AppTheme.colors.textTertiary
                            )

                        Text(viewModel.weekdayLabel(for: date))
                            .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                            .foregroundStyle(
                                isSelected
                                ? AppTheme.colors.coral
                                : AppTheme.colors.body.opacity(0.7)
                            )
                    }
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.timelineEntries.enumerated()), id: \.element.id) { index, entry in
                HomeTimelineRow(entry: entry)

                if index < viewModel.timelineEntries.count - 1 {
                    DashedDivider()
                        .stroke(AppTheme.colors.separator, style: StrokeStyle(lineWidth: 1.5, dash: [3, 8]))
                        .frame(height: 1)
                        .padding(.leading, 4)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func triggerSoftDateFeedback() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.85)
        #endif
    }

    private func avatarBubble(_ avatar: HomeAvatar, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint)

            Image(systemName: avatar.systemImageName)
                .font(AppTheme.typography.sized(16, weight: .semibold))
                .foregroundStyle(AppTheme.colors.title)
        }
        .frame(width: 44, height: 44)
        .overlay {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 2)
        }
        .accessibilityLabel(avatar.displayName)
    }
}

private struct HomeTimelineRow: View {
    let entry: HomeTimelineEntry

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing.md) {
            timelineSymbol
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(AppTheme.typography.sized(19, weight: .bold))
                    .foregroundStyle(entry.isMuted ? AppTheme.colors.body.opacity(0.45) : AppTheme.colors.title)

                HStack(spacing: 8) {
                    Text(entry.executionLabel)
                    if let locationText = entry.locationText, locationText.isEmpty == false {
                        Text(locationText)
                    }
                }
                .font(AppTheme.typography.textStyle(.caption1, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(entry.isMuted ? 0.4 : 0.68))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(entry.timeText)
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.timeText.opacity(entry.isMuted ? 0.42 : 0.82))

                Text(entry.statusText)
                    .font(AppTheme.typography.textStyle(.caption1, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.42))
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var timelineSymbol: some View {
        switch entry.accentColorName {
        case "sun":
            Image(systemName: entry.symbolName)
                .font(AppTheme.typography.sized(21, weight: .semibold))
                .foregroundStyle(AppTheme.colors.sun)
        case "violet":
            Image(systemName: entry.symbolName)
                .font(AppTheme.typography.sized(21, weight: .semibold))
                .foregroundStyle(AppTheme.colors.violet)
        case "coral":
            if entry.showsSolidSymbol {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.colors.outlineStrong.opacity(0.75), lineWidth: 1.2)
                    }
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(AppTheme.typography.sized(12, weight: .bold))
                            .foregroundStyle(AppTheme.colors.coral)
                    }
            } else {
                Image(systemName: entry.symbolName)
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)
            }
        default:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.4, dash: [4, 5])
                )
                .foregroundStyle(AppTheme.colors.outlineStrong.opacity(0.85))
        }
    }
}

private struct DashedDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
