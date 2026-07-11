import SwiftUI

struct PersonalIdentityBootstrapView: View {
    let title: String
    let message: String
    let primaryButtonTitle: String?
    let onPrimaryAction: (() -> Void)?
    let onUseLocally: (() -> Void)?

    var body: some View {
        ZStack {
            GradientGridBackground()

            VStack(spacing: AppTheme.spacing.xl) {
                Image("EmptyCalendar")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 136, height: 136)
                    .accessibilityHidden(true)

                VStack(spacing: AppTheme.spacing.sm) {
                    Text(title)
                        .font(AppTheme.typography.sized(20, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text(message)
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.64))
                        .multilineTextAlignment(.center)
                }

                if let primaryButtonTitle, let onPrimaryAction {
                    Button(primaryButtonTitle, action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                if let onUseLocally {
                    Button("先在本机使用", action: onUseLocally)
                        .buttonStyle(.borderless)
                        .font(AppTheme.typography.sized(15, weight: .semibold))
                }
            }
            .padding(.horizontal, AppTheme.spacing.xxl)
            .frame(maxWidth: 440)
        }
        .ignoresSafeArea()
    }
}
