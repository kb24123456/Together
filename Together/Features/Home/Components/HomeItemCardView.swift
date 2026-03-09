import SwiftUI

struct HomeItemCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: Item
    let surfaceStyle: HomeCardSurfaceStyle
    let ownershipTokens: [HomeAvatarToken]
    let roleLabel: String
    let namespace: Namespace.ID
    let isExpandedSource: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        let palette = palette(for: surfaceStyle)
        let displayDate = item.dueAt ?? item.createdAt

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: AppTheme.spacing.sm) {
                Text(displayDate, format: .dateTime.hour().minute())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.timeText)
                    .padding(.horizontal, palette.timePillInsets.horizontal)
                    .padding(.vertical, palette.timePillInsets.vertical)
                    .background(palette.timePillFill, in: Capsule())

                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette.accessoryText)
                        .frame(width: 28, height: 28)
                        .background(palette.accessoryFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isPinned ? "取消置顶" : "置顶事项")

                Spacer(minLength: 0)
            }

            Text(item.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.leading)
                .fontDesign(.rounded)
                .lineLimit(1)

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .fontDesign(.rounded)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer(minLength: 0)

                HStack(spacing: -8) {
                    ForEach(ownershipTokens) { token in
                        Text(token.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(avatarForeground(for: token, palette: palette))
                            .frame(width: 36, height: 36)
                            .background(palette.avatarFill, in: Circle())
                            .overlay(Circle().stroke(palette.avatarStroke, lineWidth: 1))
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(palette.background)
                .matchedGeometryEffect(id: item.id, in: namespace)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
        .shadow(color: palette.shadowColor, radius: 20, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .opacity(isExpandedSource ? 0.001 : 1)
        .onTapGesture(perform: onTap)
    }

    private func avatarForeground(for token: HomeAvatarToken, palette: HomeCardPalette) -> Color {
        switch colorScheme {
        case .dark:
            return palette.avatarText
        default:
            return palette.avatarText
        }
    }

    private func palette(for style: HomeCardSurfaceStyle) -> HomeCardPalette {
        switch (style, colorScheme) {
        case (.accent, .dark):
            HomeCardPalette(
                background: Color(red: 0.067, green: 0.067, blue: 0.075),
                primaryText: Color(red: 0.957, green: 0.686, blue: 0.753),
                secondaryText: Color(red: 0.820, green: 0.604, blue: 0.667),
                timeText: Color(red: 0.925, green: 0.631, blue: 0.702),
                timePillFill: Color(red: 0.110, green: 0.110, blue: 0.133),
                accessoryText: Color(red: 0.957, green: 0.686, blue: 0.753),
                accessoryFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarText: Color(red: 0.949, green: 0.694, blue: 0.757),
                avatarStroke: Color(red: 0.953, green: 0.604, blue: 0.690).opacity(0.24),
                border: Color(red: 0.165, green: 0.165, blue: 0.192),
                shadowColor: Color.black.opacity(0.22),
                timePillInsets: (horizontal: 12, vertical: 7)
            )
        case (.accent, _):
            HomeCardPalette(
                background: Color(red: 0.918, green: 0.498, blue: 0.600),
                primaryText: Color(red: 0.996, green: 0.992, blue: 0.996),
                secondaryText: Color(red: 1.0, green: 0.898, blue: 0.925),
                timeText: Color(red: 0.996, green: 0.972, blue: 0.984),
                timePillFill: Color.white.opacity(0.14),
                accessoryText: Color(red: 0.996, green: 0.972, blue: 0.984),
                accessoryFill: Color.white.opacity(0.14),
                avatarFill: Color(red: 1.0, green: 0.969, blue: 0.980),
                avatarText: Color(red: 0.788, green: 0.353, blue: 0.490),
                avatarStroke: Color.white.opacity(0.4),
                border: Color.white.opacity(0.14),
                shadowColor: Color(red: 0.788, green: 0.353, blue: 0.490).opacity(0.14),
                timePillInsets: (horizontal: 12, vertical: 7)
            )
        case (.muted, .dark):
            HomeCardPalette(
                background: Color(red: 0.067, green: 0.067, blue: 0.075),
                primaryText: Color(red: 0.949, green: 0.933, blue: 0.914),
                secondaryText: Color(red: 0.745, green: 0.714, blue: 0.690),
                timeText: Color(red: 0.831, green: 0.804, blue: 0.776),
                timePillFill: .clear,
                accessoryText: Color(red: 0.745, green: 0.714, blue: 0.690),
                accessoryFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarFill: Color(red: 0.102, green: 0.102, blue: 0.122),
                avatarText: Color(red: 0.949, green: 0.933, blue: 0.914),
                avatarStroke: Color(red: 0.184, green: 0.184, blue: 0.216),
                border: Color(red: 0.165, green: 0.165, blue: 0.192),
                shadowColor: Color.black.opacity(0.22),
                timePillInsets: (horizontal: 0, vertical: 0)
            )
        case (.muted, _):
            HomeCardPalette(
                background: Color.white,
                primaryText: Color(red: 0.090, green: 0.090, blue: 0.102),
                secondaryText: Color(red: 0.463, green: 0.463, blue: 0.502),
                timeText: Color(red: 0.420, green: 0.420, blue: 0.447),
                timePillFill: .clear,
                accessoryText: Color(red: 0.420, green: 0.420, blue: 0.447),
                accessoryFill: Color(red: 0.955, green: 0.955, blue: 0.965),
                avatarFill: Color(red: 0.078, green: 0.078, blue: 0.086),
                avatarText: .white,
                avatarStroke: Color.black.opacity(0.08),
                border: Color.black.opacity(0.06),
                shadowColor: Color.black.opacity(0.05),
                timePillInsets: (horizontal: 0, vertical: 0)
            )
        }
    }
}

private struct HomeCardPalette {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let timeText: Color
    let timePillFill: Color
    let accessoryText: Color
    let accessoryFill: Color
    let avatarFill: Color
    let avatarText: Color
    let avatarStroke: Color
    let border: Color
    let shadowColor: Color
    let timePillInsets: (horizontal: CGFloat, vertical: CGFloat)
}
