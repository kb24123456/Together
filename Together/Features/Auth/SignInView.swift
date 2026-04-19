import AuthenticationServices
import SwiftUI

struct SignInView: View {
    let authService: AuthServiceProtocol
    let onSignedIn: (AuthSession) -> Void

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.colors.homeBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: AppTheme.spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTheme.typography.sized(64, weight: .light))
                        .foregroundStyle(AppTheme.colors.accent)
                        .symbolEffect(.breathe, options: .repeating)

                    Text("Together")
                        .font(AppTheme.typography.textStyle(.largeTitle, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("一起，更好地完成每一件事")
                        .font(AppTheme.typography.textStyle(.subheadline, weight: .regular))
                        .foregroundStyle(AppTheme.colors.body)
                }

                Spacer()

                VStack(spacing: AppTheme.spacing.md) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.typography.textStyle(.footnote, weight: .regular))
                            .foregroundStyle(AppTheme.colors.danger)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Handling is done via the authService directly
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius.card))
                    .disabled(isSigningIn)
                    .opacity(isSigningIn ? 0.6 : 1.0)
                    .overlay {
                        if isSigningIn {
                            RoundedRectangle(cornerRadius: AppTheme.radius.card)
                                .fill(.ultraThinMaterial)
                            ProgressView()
                        }
                    }
                    .onTapGesture {
                        guard isSigningIn == false else { return }
                        performSignIn()
                    }

                    #if DEBUG
                    // 模拟器 / 开发环境快速登录（生成随机用户，用于配对测试）
                    Button {
                        performDevSignIn()
                    } label: {
                        HStack(spacing: AppTheme.spacing.xs) {
                            Image(systemName: "hammer.fill")
                                .font(AppTheme.typography.sized(14))
                            Text("开发者快速登录")
                                .font(AppTheme.typography.textStyle(.subheadline, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.colors.body)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius.card))
                    }
                    .disabled(isSigningIn)
                    #endif
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.bottom, AppTheme.spacing.xxl)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: errorMessage)
    }

    #if DEBUG
    private func performDevSignIn() {
        isSigningIn = true
        errorMessage = nil

        let devUser = User(
            id: UUID(),
            appleUserID: "dev-simulator-\(UUID().uuidString.prefix(8))",
            displayName: "测试用户",
            avatarSystemName: "person.crop.circle.fill",
            createdAt: .now,
            updatedAt: .now,
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: false,
                calendarReminderEnabled: false,
                futureCollaborationInviteEnabled: true
            )
        )
        let session = AuthSession(state: .signedIn, user: devUser)
        onSignedIn(session)
    }
    #endif

    private func performSignIn() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                let session = try await authService.signInWithApple()
                await MainActor.run {
                    onSignedIn(session)
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    if let authError = error as? ASAuthorizationError,
                       authError.code == .canceled {
                        // User cancelled — no error message needed
                        return
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
