import SwiftUI

struct AppLockOverlay: View {
    let biometricService: BiometricAuthServiceProtocol
    let onUnlocked: () -> Void

    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacing.lg) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppTheme.colors.sky)

                Text("Together 已锁定")
                    .font(AppTheme.typography.textStyle(.headline, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title)

                Button {
                    authenticate()
                } label: {
                    HStack(spacing: AppTheme.spacing.xs) {
                        Image(systemName: biometricIconName)
                        Text("解锁")
                    }
                    .font(AppTheme.typography.textStyle(.body, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.spacing.lg)
                    .padding(.vertical, AppTheme.spacing.sm)
                    .background(AppTheme.colors.sky, in: Capsule())
                }
                .disabled(isAuthenticating)
            }
        }
        .onAppear {
            authenticate()
        }
    }

    private var biometricIconName: String {
        let name = biometricService.biometricTypeName()
        switch name {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.open.fill"
        }
    }

    private func authenticate() {
        guard isAuthenticating == false else { return }
        isAuthenticating = true

        Task {
            let success = (try? await biometricService.authenticate(
                reason: "解锁 Together"
            )) ?? false

            await MainActor.run {
                isAuthenticating = false
                if success {
                    onUnlocked()
                }
            }
        }
    }
}
