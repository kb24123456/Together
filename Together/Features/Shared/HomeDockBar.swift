import SwiftUI

struct HomeDockBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Namespace private var projectButtonNamespace
    let isQuickCapturePresented: Bool
    let isProjectModePresented: Bool
    let isProjectButtonReturning: Bool
    let onProfileTapped: () -> Void
    let onComposeTapped: () -> Void
    let onQuickCaptureTapped: () -> Void
    let onProjectsTapped: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            dockShell
                .frame(maxWidth: .infinity, alignment: .center)

            floatingProjectButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(isProjectModePresented)
        }
        .animation(dockAnimation, value: isProjectModePresented)
        .animation(dockAnimation, value: isProjectButtonReturning)
    }

    private var dockShell: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: AppTheme.spacing.lg) {
                    dockContent
                }
                .padding(.horizontal, AppTheme.spacing.xl)
            } else {
                dockContent
                    .padding(.horizontal, AppTheme.spacing.lg)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: AppTheme.colors.shadow.opacity(0.9), radius: 24, y: 12)
                    .padding(.horizontal, AppTheme.spacing.xl)
            }
        }
    }

    private var dockContent: some View {
        HStack(spacing: 0) {
            dockSlot {
                circleButton(
                    systemImage: "person.crop.circle",
                    accessibilityLabel: "打开个人页",
                    action: onProfileTapped
                )
                .offset(x: isProjectModePresented ? -18 : 0, y: isProjectModePresented ? 72 : 0)
                .opacity(isProjectModePresented ? 0 : 1)
                .scaleEffect(isProjectModePresented ? 0.84 : 1)
                .allowsHitTesting(!isProjectModePresented)
            }

            dockSlot {
                primaryButton
                    .offset(y: isProjectModePresented ? 88 : 0)
                    .opacity(isProjectModePresented ? 0 : 1)
                    .scaleEffect(isProjectModePresented ? 0.88 : 1)
                    .allowsHitTesting(!isProjectModePresented)
            }

            dockSlot {
                projectToggleButton(isReturning: false)
                    .opacity(isProjectModePresented ? 0 : 1)
                    .scaleEffect(isProjectModePresented ? 0.92 : 1)
                    .allowsHitTesting(!isProjectModePresented)
            }

            dockSlot {
                circleButton(
                    systemImage: isQuickCapturePresented ? "xmark" : "square.and.pencil",
                    accessibilityLabel: isQuickCapturePresented ? "关闭快速捕捉" : "打开快速捕捉",
                    action: onQuickCaptureTapped
                )
                .offset(x: isProjectModePresented ? 18 : 0, y: isProjectModePresented ? 72 : 0)
                .opacity(isProjectModePresented ? 0 : 1)
                .scaleEffect(isProjectModePresented ? 0.84 : 1)
                .allowsHitTesting(!isProjectModePresented)
            }
        }
    }

    private func dockSlot<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var primaryButton: some View {
        Button {
            HomeInteractionFeedback.selection()
            onComposeTapped()
        } label: {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(28, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
                .frame(width: 120, height: 64)
        }
        .buttonStyle(.plain)
        .modifier(GlassCapsuleModifier())
        .accessibilityLabel("新建任务")
    }

    private var floatingProjectButton: some View {
        projectToggleButton(isReturning: true)
            .padding(.trailing, AppTheme.spacing.xl)
            .opacity(isProjectModePresented ? 1 : 0)
            .offset(y: isProjectModePresented ? 0 : 88)
    }

    private func projectToggleButton(isReturning: Bool) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            onProjectsTapped()
        } label: {
            Image(systemName: isReturning ? "arrow.uturn.backward.circle.fill" : "square.stack.3d.up.fill")
                .font(AppTheme.typography.sized(isReturning ? 21 : 22, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .modifier(GlassCircleModifier())
        .matchedGeometryEffect(id: "home-project-toggle", in: projectButtonNamespace)
        .accessibilityLabel(isReturning ? "返回 Today" : "打开项目模式")
        .accessibilityHint(isReturning ? "返回任务视图" : "切换到项目视图")
    }

    private var dockAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: isProjectButtonReturning ? 0.42 : 0.38, dampingFraction: 0.86)
    }

    private func circleButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HomeInteractionFeedback.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(22, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .modifier(GlassCircleModifier())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.74))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.65), lineWidth: 1)
                }
        }
    }
}

private struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .background(
                    Circle()
                        .fill(.white.opacity(0.74))
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.65), lineWidth: 1)
                }
        }
    }
}
