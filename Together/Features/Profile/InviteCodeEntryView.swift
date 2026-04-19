import SwiftUI

/// Sheet shown on Device B for entering a 6-digit numeric invite code.
struct InviteCodeEntryView: View {
    @Binding var isPresented: Bool
    let onAccept: (String) async -> String?

    @State private var code: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacing.lg) {
                Spacer()

                VStack(spacing: AppTheme.spacing.md) {
                    Image(systemName: "person.2.fill")
                        .font(AppTheme.typography.sized(48, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.profileAccent)

                    Text("输入邀请码")
                        .font(AppTheme.typography.sized(22, weight: .bold))
                        .foregroundStyle(AppTheme.colors.title)

                    Text("请输入伴侣分享的 6 位数字邀请码")
                        .font(AppTheme.typography.sized(15, weight: .medium))
                        .foregroundStyle(AppTheme.colors.body)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: AppTheme.spacing.sm) {
                    TextField("000000", text: $code)
                        .font(.system(size: 32, weight: .bold, design: .monospaced)) // design: .monospaced intentional
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .tracking(8)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                                .fill(AppTheme.colors.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radius.md, style: .continuous)
                                .stroke(AppTheme.colors.outline.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: code) {
                            // 限制为纯数字，最多 6 位
                            let filtered = code.filter(\.isNumber)
                            if filtered != code || filtered.count > 6 {
                                code = String(filtered.prefix(6))
                            }
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.typography.sized(13, weight: .medium))
                            .foregroundStyle(AppTheme.colors.coral)
                            .multilineTextAlignment(.center)
                    }
                }

                Button {
                    HomeInteractionFeedback.selection()
                    Task { await submit() }
                } label: {
                    ZStack {
                        Text("加入双人空间")
                            .font(AppTheme.typography.sized(16, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(isLoading ? 0 : 1)

                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radius.card, style: .continuous)
                            .fill(isCodeComplete ? AppTheme.colors.profileAccent : AppTheme.colors.outline)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isCodeComplete || isLoading)

                Spacer()
            }
            .padding(.horizontal, AppTheme.spacing.lg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                    .font(AppTheme.typography.sized(16, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body)
                }
            }
            .background(AppTheme.colors.background.ignoresSafeArea())
        }
    }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCodeComplete: Bool {
        trimmedCode.count == 6 && trimmedCode.allSatisfy(\.isNumber)
    }

    private func submit() async {
        guard isCodeComplete else { return }
        isLoading = true
        errorMessage = nil
        let error = await onAccept(trimmedCode)
        if let error {
            errorMessage = error
        }
        isLoading = false
    }
}
