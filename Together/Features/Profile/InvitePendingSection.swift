import SwiftUI

/// 邀请已发出状态的 UI 区块：6 位数字邀请码 + 倒计时 + 操作按钮
struct InvitePendingSection: View {
    let invite: Invite?
    let onCopy: (String) -> Void
    let onCheckAccepted: () async -> Void
    let onCancel: () async -> Void
    let onRegenerate: () async -> Void

    @State private var copiedCode = false
    @State private var remainingSeconds: Int = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: AppTheme.spacing.sm) {
            if let invite, let code = Optional(invite.inviteCode), !code.isEmpty {
                if remainingSeconds > 0 {
                    // ── 邀请码展示 ──
                    inviteCodeCard(code: code)

                    // ── 倒计时 ──
                    HStack(spacing: AppTheme.spacing.xxs) {
                        Image(systemName: "clock")
                            .font(AppTheme.typography.sized(12))
                        Text("有效期剩余 \(formattedTime)")
                            .font(AppTheme.typography.sized(13, weight: .medium))
                    }
                    .foregroundStyle(remainingSeconds <= 30 ? AppTheme.colors.danger : AppTheme.colors.textTertiary)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds <= 30)

                    // ── 取消邀请 ──
                    Button {
                        HomeInteractionFeedback.selection()
                        Task { await onCancel() }
                    } label: {
                        Text("取消邀请")
                            .font(AppTheme.typography.sized(13, weight: .medium))
                            .foregroundStyle(AppTheme.colors.danger)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppTheme.spacing.xxs)
                } else {
                    // ── 已过期 ──
                    VStack(spacing: AppTheme.spacing.xs) {
                        HStack(spacing: AppTheme.spacing.xs) {
                            Image(systemName: "clock.badge.xmark")
                                .font(AppTheme.typography.sized(14))
                            Text("邀请码已过期")
                                .font(AppTheme.typography.sized(14, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.colors.textTertiary)

                        Button {
                            HomeInteractionFeedback.selection()
                            Task { await onRegenerate() }
                        } label: {
                            actionButtonLabel(title: "重新生成邀请码", tint: AppTheme.colors.profileAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // activeInvite 丢失兜底
                Text("邀请数据异常")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary)

                Button {
                    HomeInteractionFeedback.selection()
                    Task { await onCancel() }
                } label: {
                    actionButtonLabel(title: "重置状态", tint: AppTheme.colors.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { startTimer(); startPolling() }
        .onDisappear { timerTask?.cancel(); pollTask?.cancel() }
        .onChange(of: invite?.id) { startTimer(); startPolling() }
    }

    // MARK: - Subviews

    private func inviteCodeCard(code: String) -> some View {
        VStack(spacing: AppTheme.spacing.md) {
            Text("邀请码")
                .font(AppTheme.typography.sized(12, weight: .medium))
                .foregroundStyle(AppTheme.colors.textTertiary)

            // 6 位数字大号等宽显示，字间距加大
            Text(formatDigits(code))
                .font(.system(size: 36, weight: .bold, design: .monospaced)) // design: .monospaced intentional
                .foregroundStyle(AppTheme.colors.title)
                .tracking(8)

            HStack(spacing: AppTheme.spacing.md) {
                Button {
                    onCopy(code)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        copiedCode = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copiedCode = false }
                    }
                } label: {
                    Label(
                        copiedCode ? "已复制" : "复制邀请码",
                        systemImage: copiedCode ? "checkmark" : "doc.on.doc"
                    )
                    .font(AppTheme.typography.sized(13, weight: .semibold))
                    .foregroundStyle(
                        copiedCode ? AppTheme.colors.profileAccent : AppTheme.colors.body
                    )
                    .padding(.horizontal, AppTheme.spacing.md)
                    .padding(.vertical, AppTheme.spacing.xs)
                    .background(
                        Capsule()
                            .fill(
                                copiedCode
                                ? AppTheme.colors.profileAccentSoft
                                : AppTheme.colors.backgroundSoft.opacity(0.9)
                            )
                    )
                }
                .buttonStyle(.plain)

                ShareLink(item: "Together 邀请码: \(code)") {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body)
                        .padding(.horizontal, AppTheme.spacing.md)
                        .padding(.vertical, AppTheme.spacing.xs)
                        .background(
                            Capsule()
                                .fill(AppTheme.colors.backgroundSoft.opacity(0.9))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                .fill(AppTheme.colors.surfaceElevated)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                .stroke(AppTheme.colors.outline.opacity(0.14), lineWidth: 1)
        }
    }

    private func actionButtonLabel(title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTheme.typography.sized(14, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                    .fill(AppTheme.colors.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.radius.lg, style: .continuous)
                    .stroke(AppTheme.colors.outline.opacity(0.14), lineWidth: 1)
            }
    }

    // MARK: - Timer & Auto-poll

    private func startTimer() {
        timerTask?.cancel()
        guard let invite else { remainingSeconds = 0; return }
        let remaining = Int(invite.expiresAt.timeIntervalSinceNow)
        remainingSeconds = max(0, remaining)

        guard remainingSeconds > 0 else { return }

        timerTask = Task { @MainActor in
            while !Task.isCancelled && remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                let r = Int(invite.expiresAt.timeIntervalSinceNow)
                remainingSeconds = max(0, r)
            }
        }
    }

    /// 每 5 秒自动检查对方是否已接受邀请
    private func startPolling() {
        pollTask?.cancel()
        guard invite != nil else { return }

        pollTask = Task { @MainActor in
            while !Task.isCancelled && remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await onCheckAccepted()
            }
        }
    }

    private var formattedTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// "123456" → "123 456"（中间加空格更易读）
    private func formatDigits(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let idx = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<idx]) \(code[idx...])"
    }
}
