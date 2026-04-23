# Phase 2 Premium — Smoke Test Runbook

手动验收清单。代码已全部合入 `main`（commit `e01bd44` 及其前序），这份文档指引你用 DEBUG build + 真实 Supabase grants 跑一遍完整通路，确认生产上线前没有回归。

## 0. 预备

- [ ] Debug build 已 install 到模拟器 iPhone 17 或真机（两个 Apple ID 都可以）
- [ ] 两条 developer grant 已写入 `premium_grants`（`supabase/scripts/premium_grants_bootstrap.sql` Section 1 已执行）
- [ ] Console.app 已打开并筛选 subsystem `com.pigdog.Together`、category `Premium`

---

## Step 1 — DEBUG override picker 四态冒烟

启动 App → 登入 → Profile → 滚到最底 Debug 区域 → "会员状态" 卡片。

| 选项 | 预期"当前生效"显示 | 预期行为 |
|---|---|---|
| 真实状态 | `Pro · 白名单 · 永久`（你有 developer grant） | 一切不受限 |
| Free | `Free` | 下面 Step 2 列出的限制全部生效 |
| Pro · 订阅（30 天后到期） | `Pro · 订阅 · YYYY-MM-DD 到期` | 无限制 |
| Pro · 永久白名单 | `Pro · 白名单 · 永久` | 无限制 |
| Grace · 剩 7 天 | `Grace · 剩 7 天` | **同步继续、Logbook 可全历史、quota 仍放行**（因 gracePeriod.isPremium=true） |
| Grace · 剩 1 天 | `Grace · 剩 1 天` | 同上 |

- [ ] 每切一次，"当前生效"立刻更新
- [ ] "真实计算"一直保持 `Pro · 白名单`（未被 override 污染）
- [ ] 点"立即重新计算" → spinner 转一下 → 状态卡片刷新，Console 出现 `PremiumGate refreshed →` 日志

## Step 2 — Free 下 4 个 gate

Override 设为 **Free** 后：

### 2.1 Logbook 30 天 floor
- [ ] 进 Profile → 日志（CompletedHistoryView）
- [ ] 如果你有完成时间超过 30 天的旧记录：应**看不到**它们
- [ ] 如果你只有近期记录：应看到全部（未超 30 天）
- [ ] 切回 Pro → 下拉刷新 → 老记录重新出现

### 2.2 Anniversaries quota
- [ ] 进纪念日管理（ImportantDatesManagementView）
- [ ] 需要 pair 绑定才能进这个页面。如果没绑定，可以用 DEBUG override 模拟；否则跳过
- [ ] 已有自己创建的 5 条以下：创建新的应成功
- [ ] 已有 5 条：点"+"创建 → 填完 → 保存 → **弹 "纪念日已达上限" alert**
- [ ] 点"好的"关闭 alert → Override 切 Pro → 再创建应成功

### 2.3 Projects quota
- [ ] 从任意页点 "+" → 选 "项目"（composer sheet）
- [ ] 已有自己创建的 3 个以下：创建新的应成功
- [ ] 已有 3 个：composer 填完保存 → composer 关闭 → 回到主界面 → **弹 "项目已达上限" alert**
- [ ] 点"好的"关闭 → Override 切 Pro → 再创建应成功

### 2.4 Cross-device sync gate
- [ ] 当前 Override=Free，**冷启动 App**（杀掉重开）
- [ ] Console 应看到 `[Coordinator] Solo engine skipped: user is not premium`
- [ ] 无跨设备同步迹象（`health` 指标不增）
- [ ] Override 切 Pro → 冷启动 → Console 应看到 `✅ Solo CKSyncEngine started`

---

## Step 3 — 真实 grant 通路

- [ ] Debug override 切回 "真实状态"
- [ ] Console 筛选 `Premium` 观察：`RC configured` / `PremiumGate bootstrapped → .pro(source: grant, ...)`
- [ ] `isPremium == true`，上述所有 free 限制全部解除

## Step 4 — 撤销 grant 运行时一致性（P2.1 验证）

在 Supabase SQL Editor（或 MCP）运行：
```sql
UPDATE premium_grants SET revoked_at = now()
WHERE user_id = '<你的 auth.users.id>' AND category = 'developer';
```

- [ ] App 内手动 Debug → "立即重新计算"
- [ ] Console 应看到：
  - `PremiumGate refreshed → free`
  - `Premium lapsed at runtime — stopping solo sync`
  - `[Coordinator] Solo CKSyncEngine stopped`
- [ ] 立刻尝试创建第 6 个纪念日 / 第 4 个项目：应触发对应 upsell alert

恢复 grant（测试完成后）：
```sql
UPDATE premium_grants SET revoked_at = NULL
WHERE user_id = '<你的 auth.users.id>';
```

## Step 5 — 离线缓存兜底

- [ ] Override 切 "真实状态"
- [ ] 正常启动一次让缓存写入（Console 可见 `PremiumGate bootstrapped → .pro`）
- [ ] 模拟器开 Airplane Mode / 断网
- [ ] 杀掉 App 重启
- [ ] 冷启动：Console 应看到 bootstrap 过程（RC + Supabase 都 fail）后 gate 从缓存恢复到 `.pro` 状态
- [ ] App 仍能按 Pro 功能使用

---

## Step 6 — 回归

- [ ] 自动测试套件绿：
  ```
  xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:TogetherTests/PremiumGateMergeTests \
    -only-testing:TogetherTests/PremiumGateLifecycleTests \
    -only-testing:TogetherTests/PremiumStatusCacheTests \
    -only-testing:TogetherTests/PremiumStatusTests \
    -only-testing:TogetherTests/ImportantDatesViewModelQuotaTests \
    -only-testing:TogetherTests/ProjectsViewModelQuotaTests
  ```
- [ ] Full build 无 warning 增量

---

## Step 7 — 打里程碑

Smoke 过全部 ✅ 后：

```bash
git tag -a phase-2-premium -m "Phase 2 Premium Infrastructure complete

- PremiumGate with source-agnostic 14d grace + race protection
- premium_grants table + RLS + client merge
- RevenueCat SDK wired (DEBUG sandbox key / Release placeholder guard)
- Build-config aware API key + OSLog observability
- 4 gate points: solo sync / anniversaries / projects / Logbook
- Runtime Pro → Free transition stops sync
- ProfileDebugSection override picker for fast verification"
```

## TestFlight 前运营清单（非代码）

- [ ] RC Dashboard → Apps → iOS → 上传 App Store Connect In-App Purchase P8 Key（Issuer ID / Key ID / Bundle ID `com.pigdog.Together`）
- [ ] 复制 `appl_…` production key 替换 [RevenueCatConfig.swift](../../../Together/Services/Premium/RevenueCatConfig.swift) `#else` 分支的 placeholder
- [ ] App Store Connect 建订阅 Product ID → RC Dashboard 关联到 entitlement `pro`
- [ ] 确认 `supabase/scripts/premium_grants_bootstrap.sql` Section 2 (grandfather) 在**发版当天**执行
- [ ] Sandbox Apple ID 真机走完整购买 → 切账号 → 回原账号仍 Pro 全流程
