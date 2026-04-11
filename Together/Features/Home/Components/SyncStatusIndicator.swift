import SwiftUI

/// 同步状态小图标，在双人模式下显示于 Home 页面
struct SyncStatusIndicator: View {
    let isSyncing: Bool
    let lastSyncedAt: Date?
    let lastSyncError: String?

    @State private var showSuccess = false

    var body: some View {
        HStack(spacing: 4) {
            if isSyncing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.textTertiary)
                    .symbolEffect(.rotate, options: .repeating, value: isSyncing)
            } else if let lastSyncError, !lastSyncError.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.coral)
            } else if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.7))
                    .transition(.opacity)
            }

            // 同步时间戳（调试用）
            if let lastSyncedAt {
                Text(syncTimeText(lastSyncedAt))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.6))
            } else {
                Text("未同步")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.colors.textTertiary.opacity(0.4))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isSyncing)
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .onChange(of: lastSyncedAt) { _, newValue in
            guard newValue != nil else { return }
            showSuccess = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                showSuccess = false
            }
        }
    }

    private func syncTimeText(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(seconds)秒前" }
        return "\(seconds / 60)分前"
    }
}
