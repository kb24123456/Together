#if DEBUG
import SwiftUI

/// Dev-only "开发者" section 显示在 Profile 页底部。
/// 提供两档清盘、以及 Premium 状态 override picker（本机调试用）。
struct ProfileDebugSection: View {
    @Environment(AppContext.self) private var appContext
    @State private var confirmLocalNuke = false
    @State private var confirmCloudWipeStep1 = false
    @State private var confirmCloudWipeStep2 = false
    @State private var overrideSelection: PremiumOverrideOption = .none
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("开发者 (DEBUG)")
                .font(AppTheme.typography.sized(13, weight: .semibold))
                .foregroundStyle(AppTheme.colors.textTertiary)
                .padding(.horizontal, AppTheme.spacing.sm)

            premiumOverrideCard

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
            .padding(AppTheme.spacing.md)
            .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
        }
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
            Text("这是最后一次确认。点击后 app 会立即退出，下次启动时本地 + 云端所有 zone（solo + pair-*）都会被清空。云端清理最长可能等 90 秒（3 次重试 × 30 秒超时），请耐心等待。")
        }
    }

    // MARK: - Premium Override

    private var premiumOverrideCard: some View {
        let gate = appContext.container.premiumGate
        let realStatus = gate.status
        let effectiveStatus = gate.overrideStatus ?? realStatus

        return VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            HStack(spacing: AppTheme.spacing.xs) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(AppTheme.colors.coral)
                Text("会员状态")
                    .font(AppTheme.typography.textStyle(.subheadline, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing.xxs) {
                statusRow(label: "真实计算", status: realStatus, isMuted: true)
                statusRow(label: "当前生效", status: effectiveStatus, isMuted: false)
            }
            .font(AppTheme.typography.textStyle(.caption1))
            .padding(AppTheme.spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.colors.surface, in: RoundedRectangle(cornerRadius: AppTheme.radius.sm))

            Picker("Override", selection: $overrideSelection) {
                ForEach(PremiumOverrideOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: overrideSelection) { _, newValue in
                applyOverride(newValue)
            }

            Button {
                isRefreshing = true
                Task {
                    await appContext.container.premiumGate.refresh()
                    isRefreshing = false
                }
            } label: {
                HStack {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshing ? "刷新中…" : "立即重新计算")
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radius.card))
    }

    @ViewBuilder
    private func statusRow(label: String, status: PremiumStatus, isMuted: Bool) -> some View {
        HStack(spacing: AppTheme.spacing.xs) {
            Text(label)
                .foregroundStyle(isMuted ? AppTheme.colors.textTertiary : AppTheme.colors.body)
            Spacer()
            Text(statusDisplay(status))
                .fontWeight(isMuted ? .regular : .semibold)
                .foregroundStyle(isMuted ? AppTheme.colors.body : AppTheme.colors.title)
        }
    }

    private func statusDisplay(_ status: PremiumStatus) -> String {
        switch status {
        case .unknown: return "Unknown"
        case .free: return "Free"
        case .pro(let source, let expiresAt):
            let src = source == .subscription ? "订阅" : "白名单"
            if let expiresAt {
                return "Pro · \(src) · \(expiresAt.formatted(date: .abbreviated, time: .omitted)) 到期"
            }
            return "Pro · \(src) · 永久"
        case .gracePeriod(let originalExpiry, let logbookFullUntil):
            let daysLeft = Int(logbookFullUntil.timeIntervalSince(Date()) / 86400)
            _ = originalExpiry
            return "Grace · 剩 \(max(daysLeft, 0)) 天"
        }
    }

    private func applyOverride(_ option: PremiumOverrideOption) {
        let gate = appContext.container.premiumGate
        switch option {
        case .none:
            gate.overrideStatus = nil
        case .free:
            gate.overrideStatus = .free
        case .proSubscription:
            gate.overrideStatus = .pro(
                source: .subscription,
                expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
            )
        case .proGrant:
            gate.overrideStatus = .pro(source: .grant, expiresAt: nil)
        case .graceEarly:
            let expiry = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            gate.overrideStatus = .gracePeriod(
                originalExpiry: expiry,
                logbookFullUntil: expiry.addingTimeInterval(14 * 86400)
            )
        case .graceLate:
            let expiry = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
            gate.overrideStatus = .gracePeriod(
                originalExpiry: expiry,
                logbookFullUntil: expiry.addingTimeInterval(14 * 86400)
            )
        }
    }
}

private enum PremiumOverrideOption: String, CaseIterable, Identifiable {
    case none = "真实状态"
    case free = "Free"
    case proSubscription = "Pro · 订阅（30 天后到期）"
    case proGrant = "Pro · 永久白名单"
    case graceEarly = "Grace · 剩 7 天"
    case graceLate = "Grace · 剩 1 天"

    var id: String { rawValue }
    var label: String { rawValue }
}
#endif
