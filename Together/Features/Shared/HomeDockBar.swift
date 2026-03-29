import SwiftUI

struct HomeDockBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var selectionNamespace
    @Namespace private var glassNamespace

    let edgeInset: CGFloat
    let selectedDestination: DockDestination?
    let isMonthModeActive: Bool
    let isProjectsModeActive: Bool
    let isHubExpanded: Bool
    let isInteractionEnabled: Bool
    let onProfileTapped: () -> Void
    let onCalendarTapped: () -> Void
    let onHubPrimaryTapped: () -> Void
    let onHubLongPressed: () -> Void
    let onProjectsTapped: () -> Void

    @State private var suppressHubPrimaryTap = false

    private let groupedControlHeight: CGFloat = 40
    private let groupedCapsuleVerticalPadding: CGFloat = 6
    private let hubButtonDiameter: CGFloat = 48
    private let buttonWidth: CGFloat = 54
    private let selectionCornerRadius: CGFloat = 20
    private let dockSymbolSize: CGFloat = 22
    private let hubHitTargetSize: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            groupedButtons
            hubPrimaryButton
        }
        .padding(.horizontal, edgeInset)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(isInteractionEnabled)
        .animation(selectionAnimation, value: selectedDestination)
        .animation(selectionAnimation, value: isHubExpanded)
    }

    private var groupedButtons: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 18) {
                    groupedButtonsContent
                }
            } else {
                groupedButtonsContent
            }
        }
    }

    private var groupedButtonsContent: some View {
        HStack(spacing: 4) {
            dockButton(
                destination: .profile,
                systemImage: "gearshape",
                activeSystemImage: "gearshape",
                accessibilityLabel: "打开个人页",
                isDisabled: false,
                action: onProfileTapped
            )
            dockButton(
                destination: .calendar,
                systemImage: "calendar",
                activeSystemImage: "arrow.counterclockwise",
                accessibilityLabel: isMonthModeActive ? "收起月历" : "打开月历",
                isDisabled: false,
                action: onCalendarTapped
            )
            dockButton(
                destination: .agent,
                systemImage: "sparkles",
                activeSystemImage: "sparkles",
                accessibilityLabel: "Agent 即将到来",
                isDisabled: true,
                action: {}
            )
            dockButton(
                destination: .projects,
                systemImage: "square.stack",
                activeSystemImage: "arrow.counterclockwise",
                accessibilityLabel: isProjectsModeActive ? "返回 Today" : "打开项目",
                isDisabled: false,
                action: onProjectsTapped
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, groupedCapsuleVerticalPadding)
        .modifier(DockGroupedCapsuleModifier())
    }

    private func dockButton(
        destination: DockDestination,
        systemImage: String,
        activeSystemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = isDestinationSelected(destination)

        return Button {
            guard !isDisabled else { return }
            HomeInteractionFeedback.selection()
            action()
        } label: {
            ZStack {
                if isSelected && showsSelectionBackground(for: destination) {
                    RoundedRectangle(cornerRadius: selectionCornerRadius, style: .continuous)
                        .fill(AppTheme.colors.surface.opacity(0.84))
                        .matchedGeometryEffect(id: "dock-selection", in: selectionNamespace)
                        .frame(width: buttonWidth, height: groupedControlHeight)
                        .glassEffectIfAvailable(in: glassNamespace, id: "dock-selection-bg")
                }

                Image(systemName: isSelected ? activeSystemImage : systemImage)
                    .font(AppTheme.typography.sized(dockSymbolSize, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(foregroundColor(isSelected: isSelected, isDisabled: isDisabled))
                    .frame(width: buttonWidth, height: groupedControlHeight)
                    .contentTransition(.symbolEffect(.replace))
                    .blurReplaceTransition(value: isSelected)
            }
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.42 : 1)
            .scaleEffect(isSelected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isDisabled ? "该入口暂未开放" : "")
    }

    private var hubPrimaryButton: some View {
        Button {
            if suppressHubPrimaryTap {
                suppressHubPrimaryTap = false
                return
            }
            HomeInteractionFeedback.selection()
            onHubPrimaryTapped()
        } label: {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(22, weight: .regular))
                .foregroundStyle(AppTheme.colors.title)
                .frame(width: hubButtonDiameter, height: hubButtonDiameter)
                .scaleEffect(isHubExpanded ? 0.94 : 1)
                .rotationEffect(.degrees(isHubExpanded ? 45 : 0))
                .animation(selectionAnimation, value: isHubExpanded)
        }
        .buttonStyle(.plain)
        .modifier(GlassCircleModifier())
        .padding(6)
        .frame(width: hubHitTargetSize, height: hubHitTargetSize)
        .contentShape(Rectangle())
        .padding(-6)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    suppressHubPrimaryTap = true
                    HomeInteractionFeedback.selection()
                    onHubLongPressed()
                }
        )
        .accessibilityLabel(isHubExpanded ? "关闭更多入口" : "新建任务")
        .accessibilityHint("轻点新建任务，长按打开更多入口")
    }

    private func foregroundColor(isSelected: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return AppTheme.colors.title.opacity(0.32)
        }
        return AppTheme.colors.title
    }

    private func isDestinationSelected(_ destination: DockDestination) -> Bool {
        switch destination {
        case .calendar:
            return isMonthModeActive
        case .projects:
            return isProjectsModeActive
        default:
            return selectedDestination == destination
        }
    }

    private func showsSelectionBackground(for destination: DockDestination) -> Bool {
        switch destination {
        case .calendar, .projects:
            return false
        default:
            return true
        }
    }

    private var selectionAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 0.82)
    }
}

private struct DockGroupedCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.84))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.76), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }
}

private struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(
                    Circle()
                        .fill(.white.opacity(0.84))
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.76), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }
}

private extension View {
    @ViewBuilder
    func glassEffectIfAvailable(in namespace: Namespace.ID, id: String) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(.white.opacity(0.2)), in: .rect(cornerRadius: 18))
                .glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    func blurReplaceTransition<T: Equatable>(value: T) -> some View {
        self
            .transition(.blurReplace)
            .animation(.easeInOut(duration: 0.2), value: value)
    }
}
