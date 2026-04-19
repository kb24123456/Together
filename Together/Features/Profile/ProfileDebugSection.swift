#if DEBUG
import SwiftUI

/// Dev-only "开发者" section 显示在 Profile 页底部。
/// 提供两档清盘：仅本地 / 本地 + 云端 solo zone。
struct ProfileDebugSection: View {
    @State private var confirmLocalNuke = false
    @State private var confirmCloudWipeStep1 = false
    @State private var confirmCloudWipeStep2 = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("开发者 (DEBUG)")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .padding(.horizontal, AppTheme.spacing.sm)

            VStack(spacing: AppTheme.spacing.sm) {
                Button(role: .destructive) {
                    confirmLocalNuke = true
                } label: {
                    Text("清空本地数据")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(role: .destructive) {
                    confirmCloudWipeStep1 = true
                } label: {
                    Text("清空本地 + 云端（危险）")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        .confirmationDialog(
            "清空本地数据？",
            isPresented: $confirmLocalNuke,
            titleVisibility: .visible
        ) {
            Button("确认清空", role: .destructive) {
                DebugResetCoordinator.scheduleLocalNuke()
                exit(0)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清掉 SwiftData 全表 + 所有 migration flag。CloudKit solo zone 保留（下次启动会重新拉回）。app 会立即退出。")
        }
        .confirmationDialog(
            "清空本地 + 云端？",
            isPresented: $confirmCloudWipeStep1,
            titleVisibility: .visible
        ) {
            Button("继续（还会再次确认）", role: .destructive) {
                confirmCloudWipeStep2 = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将同时清掉本地数据和 CloudKit solo zone 的所有备份，无法撤销。需要二次确认。")
        }
        .confirmationDialog(
            "再次确认",
            isPresented: $confirmCloudWipeStep2,
            titleVisibility: .visible
        ) {
            Button("我确定，全部清掉", role: .destructive) {
                DebugResetCoordinator.scheduleLocalPlusCloudWipe()
                exit(0)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这是最后一次确认。点击后 app 会立即退出，下次启动时本地 + 云端都会被清空。")
        }
    }
}
#endif
