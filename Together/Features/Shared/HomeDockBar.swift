import SwiftUI

struct HomeDockBar: View {
    let isProjectLayerPresented: Bool
    let onProfileTapped: () -> Void
    let onComposeTapped: () -> Void
    let onProjectsTapped: () -> Void

    var body: some View {
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
        HStack(spacing: AppTheme.spacing.lg) {
            circleButton(
                systemImage: "person.crop.circle",
                action: onProfileTapped
            )

            primaryButton

            circleButton(
                systemImage: isProjectLayerPresented ? "square.grid.2x2.fill" : "square.grid.2x2",
                action: onProjectsTapped
            )
        }
    }

    private var primaryButton: some View {
        Button(action: onComposeTapped) {
            Image(systemName: "plus")
                .font(AppTheme.typography.sized(28, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
                .frame(width: 120, height: 64)
        }
        .buttonStyle(.plain)
        .modifier(GlassCapsuleModifier())
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppTheme.typography.sized(22, weight: .semibold))
                .foregroundStyle(AppTheme.colors.body)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .modifier(GlassCircleModifier())
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
