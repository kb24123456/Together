import SwiftUI

/// 同步状态小图标，在双人模式下显示于 Home 页面
struct SyncStatusIndicator: View {
    let status: SharedSyncStatus

    @State private var showSuccess = false

    var body: some View {
        HStack(spacing: AppTheme.spacing.xxs) {
            if status.level == .syncing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppTheme.typography.sized(11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .symbolEffect(.rotate, options: .repeating, value: status.level == .syncing)
            } else if status.failedMutationCount > 0 || resolvedErrorText != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppTheme.typography.sized(11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)
            } else if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppTheme.typography.sized(11, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.7))
                    .transition(.opacity)
            }

            // 同步时间戳（调试用）
            if let lastSyncedAt = status.lastSuccessfulSync {
                Text(syncTimeText(lastSyncedAt))
                    .font(.system(size: 10, weight: .medium, design: .monospaced)) // design: .monospaced intentional
                    .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.6))
            } else {
                Text("未同步")
                    .font(AppTheme.typography.sized(10, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.4))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: status.level == .syncing)
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .onChange(of: status.lastSuccessfulSync) { _, newValue in
            guard newValue != nil else { return }
            showSuccess = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                showSuccess = false
            }
        }
    }

    private var resolvedErrorText: String? {
        status.lastSendError
        ?? status.lastFetchError
        ?? status.lastError
    }

    private func syncTimeText(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(seconds)秒前" }
        return "\(seconds / 60)分前"
    }
}
