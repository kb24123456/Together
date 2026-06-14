import AuthenticationServices
import SwiftUI

struct SignInView: View {
    let authService: AuthServiceProtocol
    let onSignedIn: (AuthSession) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            backgroundMesh
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: AppTheme.spacing.xl) {
                    BrandLogoStatic()

                    Text("十有八九，常想一二")
                        .font(AppTheme.typography.sized(22, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(AppTheme.colors.title)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

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
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
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

                    legalFooter

                    #if DEBUG
                    // 模拟器 / 开发环境快速登录（生成随机用户）
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
        .animation(AppTheme.motion.micro, value: errorMessage)
    }

    private var backgroundMesh: some View {
        let baseColors: [Color] = colorScheme == .dark
            ? [
                AppTheme.colors.background,
                Color(red: 0.16, green: 0.13, blue: 0.13),
                Color(red: 0.13, green: 0.15, blue: 0.18),
                AppTheme.colors.background,
                Color(red: 0.18, green: 0.14, blue: 0.13),
                AppTheme.colors.background,
                AppTheme.colors.background,
                Color(red: 0.13, green: 0.16, blue: 0.18),
                AppTheme.colors.background
            ]
            : [
                AppTheme.colors.background,
                Color(red: 0.99, green: 0.93, blue: 0.91),
                Color(red: 0.91, green: 0.95, blue: 0.99),
                AppTheme.colors.background,
                Color(red: 0.98, green: 0.94, blue: 0.92),
                AppTheme.colors.background,
                AppTheme.colors.background,
                Color(red: 0.93, green: 0.96, blue: 0.99),
                AppTheme.colors.background
            ]

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5, 0), .init(1, 0),
                .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                .init(0, 1), .init(0.5, 1), .init(1, 1)
            ],
            colors: baseColors
        )
    }

    private var legalFooter: some View {
        HStack(spacing: 4) {
            Text("登录即同意")
            Link("隐私政策", destination: LegalURLs.privacy)
                .foregroundStyle(AppTheme.colors.body)
                .underline()
            Text("·")
            Link("使用条款", destination: LegalURLs.terms)
                .foregroundStyle(AppTheme.colors.body)
                .underline()
        }
        .font(AppTheme.typography.sized(11, weight: .regular))
        .foregroundStyle(AppTheme.colors.textTertiary)
        .padding(.top, AppTheme.spacing.xs)
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
                calendarReminderEnabled: false
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
                    HomeInteractionFeedback.error()
                }
            }
        }
    }
}
