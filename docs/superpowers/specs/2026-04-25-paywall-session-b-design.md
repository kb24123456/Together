# Phase 3 · Session B — 订阅管理 + Grace Period UI + 合规文案 Design Spec

- **Date**: 2026-04-25
- **Status**: **v5** — v4 全部决策落定 + 执行期发现 raw vs effective status 边界遗漏，v5 补 § 2.1.1 effectiveStatus API 设计决策
- **Scope**: 在 Session A 已落地的付费墙 + 购买流之上，补齐"订阅管理 / Grace Period 横幅 / 合规文案 / Ask to Buy 翻转 / Restore 多场景"5 个收尾模块。
- **Inputs**:
  - Session A 收敛版：`docs/superpowers/specs/2026-04-24-paywall-session-a-design.md`（v8）
  - 产品决策：`docs/superpowers/specs/2026-04-22-premium-tier-split-design.md`（§ 5.2 grace period 产品规则）
  - Session A 落地：`memory/project_together_progress.md`（HEAD `34ec1af`，tag `phase-3-session-a-stable`）
  - 法律草稿：`docs/legal/privacy-policy.md`、`docs/legal/terms-of-service.md`

---

## § 0. 目标 & Non-Goals

### Session B 必须完成

1. **`ProfileSubscriptionView` Pro / grace 态充实**：当前 plan 名 + 续费 / 到期日期 + "在 App Store 管理订阅"按钮（StoreKit 2 `manageSubscriptionsSheet` + 跳 Settings 回落）；pendingApproval / grace 态分支文案
2. **Logbook 顶部 Grace Period 横幅**：`case .gracePeriod(originalExpiry, logbookFullUntil)` 时挂在 `CompletedHistoryView` 顶部，文案"订阅已到期 · 剩 N 天可看全历史"+ "续订" CTA
3. **合规文案最终版**：`LegalURLs` 集中常量替换 `PaywallLegalFooter` 的 2 处 `https://example.com/placeholder`；法律文档草稿补齐（开发者名 / 邮箱 / 生效日期 / 宽限期条款）；公网 URL 由运营拍板部署方案
4. **Ask to Buy 翻转反馈**：`pendingApproval → .pro` 状态翻转时给前台用户一次轻反馈（toast 或状态行视觉变化，按 § 10.D3 决策）
5. **Restore 路径打磨**：Profile Free 态加 secondary "恢复购买"入口（与 paywall 内同源调用）；真机覆盖 3 场景（卸载重装 / 家庭共享 / 网络失败）；错误文案分级
6. **i18n + a11y 基线**：新增组件全部接 `String(localized:)` + a11y label / hint（深度审计仍留 Session C）

### Session B 不覆盖（留 Session C 或独立 feature）

- VoiceOver / Dynamic Type / RTL **深度审计**（Session B 仅基线）
- StoreKit Configuration `.storekit` 本地测试文件
- Sentry / Crashlytics 接入
- 新设备首次打开 `.crossDeviceSync` 一次性引导
- Pre-Apple 审核全套 checklist
- Pro→Active 翻转的 **远程推送** 通知（仅做前台 toast；后台 push 走 RC Dashboard 配置 + 独立 spec）
- 纪念日"已 N 天"正计时（独立 feature，需要 ImportantDate 模型 mode 字段，独立 spec）

---

## § 1. 架构边界

### 1.1 已有资产（复用，不改）

| 资产 | 位置 | 用途 |
|---|---|---|
| `PremiumStatus` enum | `Together/Services/Premium/PremiumStatus.swift` | 含 `.pro(source, expiresAt)` / `.gracePeriod(originalExpiry, logbookFullUntil)` |
| `PremiumGate.refresh()` | `Together/Services/Premium/PremiumGate.swift` | restore 路径复用 |
| `PremiumGate.latestEntitlementExpiration` | 同上 | Pro 态续费日期来源 |
| `ProSubscriptionStatus` enum | `Together/Features/Profile/...` | `.pendingApproval` case Session A 已加 |
| `RootPaywallPresentation` | `Together/Features/Paywall/RootPaywallPresentation.swift` | grace 横幅 CTA 入 queue |
| `PaywallPurchasingProtocol` + `RevenueCatPaywallPurchasing` | `Together/Features/Paywall/...` | Profile restore 复用接口（不复用 PaywallViewModel） |
| `UpsellTrigger` enum 现有 case | `Together/Services/Premium/UpsellTrigger.swift` | 现有 case 不动，本 session 新增 `.graceExpiring`（在 § 1.3 改动） |
| `UpsellCopy` framework | `Together/Features/Paywall/UpsellCopy.swift` | 复用 `legalBodyText` / `formatPriceLine`；为 `.graceExpiring` 加 hero / subtitle 分支（在 § 1.3 改动） |

### 1.2 新增文件

| 文件 | 类型 |
|---|---|
| `Together/Features/Profile/ProfileSubscriptionDetailSection.swift` | View — Pro / grace / pendingApproval 三态详情 |
| `Together/Features/Profile/ManageSubscriptionLink.swift` | View modifier — `manageSubscriptionsSheet` + URL 回落 |
| `Together/Features/Logbook/GracePeriodBanner.swift` | View — Logbook 顶部横幅 |
| `Together/Services/Premium/LegalURLs.swift` | 常量 — Privacy / ToS / 订阅条款 URL single source of truth |
| `Together/Services/Premium/PendingApprovalObserver.swift` | @MainActor class — 监听 PremiumGate.status，detect pendingApproval→pro 边沿，触发 OSLog（B 方案下加 toast） |
| `TogetherTests/ProfileSubscriptionDetailSectionTests.swift` | 单测 — 4 态快照 |
| `TogetherTests/GracePeriodBannerTests.swift` | 单测 — 倒计时计算 + 文案 + CTA enqueue |
| `TogetherTests/LegalURLsTests.swift` | 单测 — URL 非占位、可构造、https |
| `TogetherTests/PendingApprovalObserverTests.swift` | 单测 — status 序列驱动 callback |
| `TogetherTests/UpsellCopyTests.swift` (扩展) | `.graceExpiring` hero / subtitle |
| `TogetherTests/PaywallViewModelTests.swift` (扩展) | restore 错误文案分级 |

### 1.3 改动文件

| 文件 | 改动 |
|---|---|
| `Together/Features/Profile/ProfileSubscriptionView.swift` | `proPlaceholder` 占位 → `ProfileSubscriptionDetailSection`；Free 态保留 UpsellContent 内置 restore（不新增按钮） |
| `Together/Features/Paywall/PaywallViewModel.swift` | `handleRestoreOutcome` 错误文案分级（nothingToRestore / network / unknown）|
| `Together/AppContext/AppContainer.swift` | 注册并持有 `PendingApprovalObserver` |
| `Together/Features/Paywall/PaywallLegalFooter.swift` | 局部 `privacyURL` / `termsURL` 删除，改读 `LegalURLs` |
| `Together/Features/Paywall/UpsellCopy.swift` | 加 `.graceExpiring` 的 hero / subtitle 分支；`legalBodyText` 已符合 Apple 3.1.2(a) 不动 |
| `Together/Features/Paywall/UpsellDisplayKind.swift` | 加 `.graceExpiring` case（v8 spec § 2.8 引入的统一类型） |
| `Together/Features/Profile/CompletedHistoryView.swift` | 顶部条件渲染 `GracePeriodBanner` |
| `Together/Services/Premium/UpsellTrigger.swift` | 加 `.graceExpiring` case（含 Kind.toDisplayKind 映射） |
| `Together/Features/Paywall/RootPaywallPresentation.swift` | 合并器加 `.graceExpiring` 的 dedupKey 策略（见 § 2.4） |
| `docs/legal/privacy-policy.md` | 补齐草稿空白 |
| `docs/legal/terms-of-service.md` | 补齐草稿空白 + 加宽限期条款 |
| `docs/superpowers/runbooks/phase-3-paywall-smoke.md` | 追加 Session B 5 个真机场景 |

### 1.4 依赖方向

```
ProfileSubscriptionView
   ├─ ProfileSubscriptionDetailSection (new)
   │     ├─ ManageSubscriptionLink (new) ──→ StoreKit / openURL
   │     └─ PremiumGate.status / latestEntitlementExpiration (existing)
   └─ Free 态 UpsellContent 内置 restore (existing, 文案优化)

CompletedHistoryView
   └─ GracePeriodBanner (new)
         ├─ PremiumGate.status (read .gracePeriod)
         └─ "续订" → RootPaywallPresentation.enqueue(.graceExpiring) (existing reuse)

PaywallLegalFooter
   └─ LegalURLs (new)
```

无循环依赖；新增组件全部叶子节点，对 Session A 核心状态机零侵入。

---

## § 2. 关键决策

### 2.1 续费日期数据流：复用 `latestEntitlementExpiration`，不扩展模型

**决策**：`ProfileSubscriptionDetailSection` 直接读 `premiumGate.latestEntitlementExpiration`（Phase 2 commit 7 已暴露）+ `PremiumStatus.gracePeriod` 的关联值；不在 `PremiumStatus.pro` 加 `renewalDate` 关联值。

**理由**：
- `PremiumStatus.pro(source, expiresAt:)` 的 `expiresAt` 与 `latestEntitlementExpiration` 等价（数据来源同 RC `EntitlementInfo.expirationDate`）；扩展会引入双源不一致风险
- Session A 的合并器 / refresh 路径已对 `latestEntitlementExpiration` 做了 race 防护，复用避免重新审计

**Grant 来源行为**：
- `.pro(.grant)` 时 `expiresAt` 通常为 nil（白名单授予无到期日）；`latestEntitlementExpiration` 同样为 nil
- View 层显式分支：`expiresAt == nil && source == .grant` → 文案"由 Together 团队赠送 · 终身有效"（无续费日期行）
- `.pro(.subscription)` 且 nil 视作异常：tag 为 R26 防御 fallback 显示"订阅有效"（不暴露日期），同时 OSLog warning

**续费 vs 已取消文案选择**：当前不区分 willRenew（RC `EntitlementInfo.willRenew` 未由 PremiumGate 暴露，扩展 = scope 增）。Session B 文案统一用**中性措辞**"有效期至 YYYY 年 M 月 D 日"，不写"下次续费"避免误导已取消但仍在 active 期的用户。区分 willRenew 留 Session C。

### 2.1.1 PremiumGate `effectiveStatus` API（v5 加；执行期补充）

**问题（v4 spec 遗漏）**：v4 spec 默认 view 直接读 `gate.status`，但 `status` 是真实合并状态，不含 DEBUG override；`isPremium` / `allowsFullLogbook` 等 computed 用 `(overrideStatus ?? status)` 已经处理了 override，但**新加的 view（DetailSection / GracePeriodBanner / CompletedHistoryView）需要 `switch` 拆 status case**，直接读 raw 漏掉 override → DEBUG picker 切 Pro/Grace 时显示空白（Session B Smoke S1 撞到）。

**决策（v5 / commit `c550dd9` 落地）**：PremiumGate 暴露 `effectiveStatus: PremiumStatus { overrideStatus ?? status }`。
- **View 层应读 effectiveStatus**：DetailSection / Banner / 任何 `switch gate.???.case` 的 view 必须用此值
- **Service 层继续用 raw status**：lapse 检测 / 诊断 OSLog / 内部合并 = 关心真实 RC + grant 状态，不应被 override 干扰
- `isPremium` / `allowsFullLogbook` 改实现为读 `effectiveStatus`（行为不变，单一来源）

**回归守卫**：`PremiumGateEffectiveStatusTests` 7 case 显式覆盖 raw vs effective 分离行为；任何后续 view 误读 raw status 会被 smoke/PR review 时这套测试的存在 documentation 提醒（虽然不能直接拦截）。

**Session C 应补**：新增 view 写 spec 时显式标"View 层读 effectiveStatus"（架构原则），避免再次遗漏。

### 2.2 "在 App Store 管理订阅"实现：StoreKit 2 sheet + URL 回落

**决策**：使用 SwiftUI 原生 `.manageSubscriptionsSheet(isPresented:)` modifier。本 app 已使用 `@Observable`（iOS 17+），sheet API 自 iOS 15+ 可用，无版本问题。失败 / 用户主动取消时无回落（系统 sheet 自身处理）；**仅当用户报告 sheet 异常**时再考虑 URL 回落（commit 1 不实现，预留 hook）。

**前置确认**：commit 4 前 `git grep "iOS 17"` / 检查 `@Observable` 用法即可确认 minDeployment ≥ 15。

**为什么不用 RevenueCat `Purchases.shared.showManageSubscriptions()`**：
- RC 封装层无 SwiftUI 友好 API，需要 UIKit scene 桥接，与 Session A 协议分层冲突
- 直接调 StoreKit 2 是 Apple 推荐路径

**实现骨架**（伪码）：
```swift
struct ManageSubscriptionLink: View {
    @State private var showManagement = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("在 App Store 管理订阅") { showManagement = true }
            .manageSubscriptionsSheet(isPresented: $showManagement)
            // 异常时不依赖 sheet — 用户从 Settings 入口仍可管理
    }
}
```

**回落策略**：Session B 内仅原生 sheet 路径；URL 回落代码不写（YAGNI）。

### 2.3 Grace Period 横幅 CTA：入 RootPaywallPresentation 合并器

**决策**：横幅是**单个 Button**，整行作为 hit area，右侧箭头是视觉提示（不是单独按钮）。点击调用 `rootPaywallPresentation.enqueue(.graceExpiring)`，复用 Session A 合并器。横幅自身不持有 sheet。

**为什么不直接绑 `.sheet`**：
- Session A 设计原则：所有 paywall sheet 走 root 单一合并器，避免 Logbook 局部 sheet 与 root paywall 冲突
- `.graceExpiring` 是新 `UpsellTrigger` case，hero / subtitle 文案与 lapse 类似但语义不同（仍在宽限期 vs 已结束）

**横幅样式**：
- 黄色背景（`AppTheme.colors.warningSurface` / 同 lapse 横幅）
- 单行（必要时换 2 行），结构 `[⚠] 订阅已到期 · 剩 N 天可看全历史   →`
- N = `max(1, Calendar.current.dateComponents([.day], from: now, to: logbookFullUntil).day ?? 1)`
- 整行 Button，VoiceOver label "订阅已到期，剩 N 天可看全历史"，hint "双击立即续订"
- 不可关闭

**为什么不让横幅可关闭**：
- 宽限期总长 14 天（产品 spec § 5.2），关闭后用户失忆 → Apple 退订挽回路径会失效
- 与 lapse `PremiumLapseNotice` 的差异：lapse 是 Pro 已彻底失效后的"软件感想"，可 dismiss；grace 是仍有功能但即将失效的"硬时间窗"，不应 dismiss

### 2.4 `.graceExpiring` 合并器 dedupKey 策略

**决策**：与 `.lapse` dedupKey 策略**不同**——
- `.lapse` 是被动通知，dedupKey = `lapse_<expiredAt 秒>`，同一周期只推一次
- `.graceExpiring` 是用户主动点击 banner 触发，**不去重**——dedupKey = `nil`（每次点击都允许入 queue）

**理由**：
- 主动点击不弹反而是 bug
- 若用户在 paywall 内取消又回到 logbook 再点，应能再次打开 paywall
- 合并器现有"in-flight 时新 enqueue 入 queue"机制（Session A § 2.8 / § 2.9）保证不会双 sheet

**实现**：合并器 `keyFor(trigger:)` 中 `.graceExpiring` 显式 `return nil`。

### 2.5 `.graceExpiring` 文案策略

**`UpsellTrigger` case 形态**：
```swift
case graceExpiring(daysRemaining: Int)
```
关联值由 `GracePeriodBanner` 在点击时传入（banner 内部已根据 PremiumGate.status 算出 N）。`UpsellDisplayKind.graceExpiring(daysRemaining: Int)` 同样带关联值，给 `UpsellContent` 渲染 subtitle 时使用。

**文案**：
- `hero`: "续订 Together Pro，保留你的回忆"
- `subtitle`: "你的订阅将在 N 天后彻底失效。续订后立即恢复完整体验。"（N 注入）
- `benefits` 排序：与 `.generic` 一致（Pro 全功能列表）
- 价格 / 法律文案：与 `.generic` 一致

**Ripple（编译期 Switch case 完整性强制）**：新增 case 触及——
- `UpsellTrigger.Kind` 枚举 + `Kind.toDisplayKind()`（含关联值传递）
- `UpsellDisplayKind` 枚举
- `UpsellCopy.heroText(for:)` / `subtitleText(for:)` / `benefitsOrder(for:)`
- `RootPaywallPresentation.keyFor(trigger:)`（dedupKey 见 § 2.4）

编译期会逐一报错；commit 3 (`feat: add .graceExpiring case`) 必须一次性补齐才能过编译，强制不遗漏。

`UpsellTrigger.Kind.toDisplayKind()` 映射：`.graceExpiring → .graceExpiring`（新 displayKind case），`UpsellContent` 渲染时与 `.generic` 同布局，仅 hero / subtitle 不同。

### 2.6 Ask to Buy `pendingApproval → .pro` 翻转反馈

**决策（v4 拍板：A + animation）**：
- 仅在 ProfileSubscriptionView 状态行视觉变化（pendingApproval → Pro 文案）
- 无额外 toast / 通知组件
- ProfileSubscriptionDetailSection 包一层 `.transition(.opacity.combined(with: .scale(scale: 0.95)))` + `.animation(.easeInOut(duration: 0.3), value: status)`，让翻转有视觉过渡而非干巴巴替换
- 加 `OSLog` 标记翻转事件以便 Session C 评估是否升级

**实现**：
- 前置确认：commit 11 前 `git grep "@Published\\|@Observable" PremiumGate.swift` 确认通知机制；若都没有则需要先在 PremiumGate 暴露 `AsyncStream<PremiumStatus>` 或 `@Observable` wrapper（独立 commit）
- 新增 `PendingApprovalObserver`（@MainActor class）订阅 status 变化，detect 序列 `.pendingApproval → .pro` 边沿，触发副作用
- **生命周期归属**：`AppContainer` 持有（与 `PremiumGate` 同层），随 app 进程存在；不绑 AppRootView（root view 几乎不 onDisappear，归属错位）
- 内部用 `lastSeenStatus: PremiumStatus?` 内存变量跟踪上一次值，仅在 `lastSeenStatus == .pendingApproval && new == .pro` 时触发

**风险**：app 后台时翻转 → 重启后 `lastSeenStatus` 是 nil，新 status 是 `.pro`，无法回放 pending → pro 的边沿。Session B 不解决（持久化"上次见过的 status"复杂度 = 一个迷你状态机），留 Session C 评估。

### 2.7 合规文案：检查 grace period 场景

**决策**：审计 `UpsellCopy.legalBodyText(for:)`，确认 grace period 场景下文案是否需要分支：
- Apple 3.1.2(a) 要求自动续费的完整模板（订阅周期 / 价格 / 续费 24h 前关闭说明 / 在账户设置管理）
- grace period 场景下用户**已订阅过**，文案无需改写（购买动作仍是新购，订阅条款相同）
- **结论**：不改 `legalBodyText`，仅检查 `.graceExpiring` displayKind 渲染时无遗漏

### 2.8 LegalURLs 集中常量

**决策**：单一文件 `Together/Services/Premium/LegalURLs.swift`：
```swift
enum LegalURLs {
    static let privacy = URL(string: "https://placeholder.together-app.com/privacy")!
    static let terms = URL(string: "https://placeholder.together-app.com/terms")!
}
```

**为什么集中**：
- Session B 只 commit 代码 + placeholder URL；运营拍板部署方案后**只改一处**
- 单测 `LegalURLsTests` 守卫：scheme == https，host 不含 `example.com`（弱校验，允许 `placeholder.*` 通过 commit；TestFlight 前再人工核对真 host）

**为什么不要 `subscription` 单独 URL**：Apple 3.1.2(a) 不要求单独的 subscription terms 页，订阅条款在 ToS 内即可（已在 § 2.10 法律文档补齐部分覆盖）。

**部署方案**（运营侧，§ 10.D4 待拍板）：
- A：GitHub Pages（公开 repo，免费）
- B：Cloudflare Pages / Vercel（静态托管）
- C：自建 / 现有官网

代码侧只关心"URL 是合法 https"，部署方案 Session B 不阻塞代码 commit；URL 终值 ≥ 上 TestFlight 前替换（在 commit 13 / 14 完成后单独一个 PR）。

### 2.9 法律文档草稿补齐

**草稿现状**（调研结果）：
- 两文档已成文，标注"草案"
- 待补齐：开发者主体名 / 联系邮箱 / 生效日期 / 修订记录

**Session B 内**：
- 把这些占位标注为 `[NEEDS_OPERATOR_INPUT]` 块，运营拍板后替换
- 补充 grace period 章节：宽限期 14 天 / 期间数据可见 / 期满后数据保留策略（产品 spec § 5.2 已定义，搬运过来）
- 补充：自动续费扣款失败后的宽限期是 Apple 而非 Together 主动控制的说明

### 2.10 Profile Restore 入口（含 scope 重新评估）

**Scope 重新评估**：调研显示 `UpsellContent` 内已有"恢复购买"按钮（位于 paywall sheet 底部）。`ProfileSubscriptionView` Free 态当前的实现是局部 `PaywallViewModel` + `UpsellContent`，意味着 **Free 态 Profile 已经渲染了 restore 按钮**（在 UpsellContent 内），**新增 ProfileRestoreButton 会重复**。

**Session B 决策（见 § 10.D5 待拍板）**：
- **A 选项（推荐）**：不新增 ProfileRestoreButton；"Restore 路径打磨" 仅做：(a) 真机覆盖 3 场景（卸载重装 / 家庭共享 / 网络失败）；(b) `PaywallViewModel.restore()` 错误文案分级优化（区分 nothingToRestore / network / unknown）；(c) Smoke runbook 新增 S3-S5
- **B 选项**：在 ProfileSubscriptionView Free 态 **替换** `UpsellContent` 中的 restore 按钮位置，让 Profile 上下文有更显眼的入口（成本：UpsellContent 需暴露 `displayKind` 让 Profile 隐藏自带 restore，再外加独立 ProfileRestoreButton）

**默认走 A**：scope 最小化、与 UpsellContent 已有逻辑无冲突；如运营反馈 Profile 入口不显眼再升级 B。

**A 选项实现细节**：
- 不新增组件
- 在 `PaywallViewModel.handleRestoreOutcome()` 内完善错误分支：
  - `.nothingToRestore` → "没有可恢复的订阅"
  - `.network` → "网络异常，请稍后重试"
  - `.unknown` → "恢复失败，请联系支持"
- 真机 smoke S3 / S4 / S5 见 § 5.2

### 2.11 测试 stub 策略

- `ManageSubscriptionLink`：纯 modifier，无可单测的状态机；StoreKit sheet 不可单测（Apple 不暴露 hook），留 smoke S1。**不写测试文件，避免 0 信号**
- `GracePeriodBanner`：snapshot 3 个 N 值（1 / 7 / 13 天），文案断言；CTA 触发 enqueue（mock 合并器）
- `ProfileSubscriptionDetailSection`：4 态快照（pro+sub / pro+grant / grace / pendingApproval）；注入 mock PremiumGate
- `LegalURLs`：URL 构造 + scheme == https + host !contains "example.com"
- `PendingApprovalObserver`：注入 mock PremiumGate，发 status 序列：
  - [.unknown, .pendingApproval, .pro] → callback 触发 1 次
  - [.unknown, .pro] → 0 次（无 pending 边沿）
  - [.unknown, .pendingApproval, .free] → 0 次（pending → free 不算成功翻转）
  - [.pendingApproval, .pro, .pendingApproval, .pro] → 2 次（多次循环都触发）
- `PaywallViewModel.handleRestoreOutcome` 错误文案分级：扩展现有 `PaywallViewModelTests`

---

## § 3. UI 规格

### 3.1 `ProfileSubscriptionDetailSection`（Pro / grace / pendingApproval 三态）

**Pro 态**（自上而下）：
1. 大标题"Together Pro · 已激活"
2. 副标题"下次续费：YYYY 年 M 月 D 日"（来自 `latestEntitlementExpiration`，本地化日期）
3. 来源行（仅 `.pro(.grant)` 时显示）："由 Together 团队赠送 · 终身有效"
4. `ManageSubscriptionLink` 按钮（仅 `.pro(.subscription)` 时显示）

**Grace 态**：
1. 黄色 inset 背景
2. 大标题"订阅已到期"
3. 副标题"剩 N 天可看全历史，期满后将自动降级为 Free"（N 实时计算自 PremiumGate.gracePeriod 关联值）
4. Primary "立即续订"按钮 → 通过环境对象 `rootPaywallPresentation` enqueue `.graceExpiring(daysRemaining: N)`
5. Secondary `ManageSubscriptionLink`（仍可看到原订阅以便用户在 Apple 端重新订阅）

**PendingApproval 态**：
1. 大标题"Together Pro · 等待家长审批"
2. 副标题"批准后自动激活，无需重新购买"
3. 无管理按钮（pending 期间 Apple 不允许操作）

### 3.2 `GracePeriodBanner`（Logbook 顶部）

```
┌─────────────────────────────────────────────────────────┐
│ ⚠  订阅已到期 · 剩 N 天可看全历史      [续订 →]        │
└─────────────────────────────────────────────────────────┘
```

- Padding: `AppTheme.spacing.md` 水平 / `.sm` 垂直
- 文字：`AppTheme.typography.sized(13)`
- N = max(1, days(now → logbookFullUntil))
- 整行可点 = "续订" CTA（VoiceOver hint："双击立即续订"）
- 不可关闭

### 3.3 Free 态 Profile 不新增组件

按 § 2.10 / § 10.D5 决策（A 选项），Free 态 Profile **不新增** restore 按钮。Restore 入口由 `UpsellContent` 内置已有按钮承接，Session B 仅做错误文案分级。

---

## § 4. 接入点

### 4.1 `ProfileSubscriptionView`

替换 `proPlaceholder` 占位：
```swift
let gate = appContext.container.premiumGate
if gate.isPremium {
    ProfileSubscriptionDetailSection(
        status: gate.status,
        expiration: gate.latestEntitlementExpiration  // nil 时分支处理
    )
} else {
    freeState  // 现有 PaywallViewModel + UpsellContent，含内置 restore
}
```

### 4.2 `CompletedHistoryView`

`List` 顶部加：
```swift
if case .gracePeriod(_, let until) = appContext.container.premiumGate.status {
    Section {
        GracePeriodBanner(logbookFullUntil: until)
            .listRowInsets(EdgeInsets())  // 去 List 默认间距
            .listRowBackground(Color.clear)
    }
}
```

### 4.3 `PaywallLegalFooter`

删除局部 URL 常量，引入 `LegalURLs`：
```swift
Link("隐私政策", destination: LegalURLs.privacy)
Link("使用条款", destination: LegalURLs.terms)
```

### 4.4 `RootPaywallPresentation`

新增 `.graceExpiring` 入 queue 路径；`keyFor(.graceExpiring) → nil`（不去重，见 § 2.4）。

### 4.5 `AppContainer`

注册 `PendingApprovalObserver`：
```swift
final class AppContainer {
    let premiumGate: PremiumGate
    let pendingApprovalObserver: PendingApprovalObserver

    init(...) {
        // ... existing
        self.pendingApprovalObserver = PendingApprovalObserver(premiumGate: premiumGate)
        self.pendingApprovalObserver.start()  // 内部 Task 监听 status stream
    }
}
```

---

## § 5. 测试策略

### 5.1 Swift Testing 新增

| 测试文件 | 覆盖 |
|---|---|
| `ProfileSubscriptionDetailSectionTests` | 4 态快照（pro+sub / pro+grant / grace / pendingApproval）|
| `GracePeriodBannerTests` | N=1/7/13 文案、整行可点、不可关闭、CTA 调 enqueue |
| `LegalURLsTests` | URL 合法 + 非 example.com host + https only |
| `PendingApprovalObserverTests` | 4 个状态序列 → callback 触发次数（见 § 2.11） |
| `UpsellCopyTests`（扩展） | `.graceExpiring` hero / subtitle |
| `PaywallViewModelTests`（扩展） | restore 错误文案分级（nothingToRestore / network / unknown） |

### 5.2 真机 Sandbox Smoke（追加 5 场景到 runbook）

| # | 场景 | 期望 |
|---|---|---|
| S1 | Pro 态打开 Profile → 点"在 App Store 管理订阅" | 弹原生 sheet，可看到订阅 + 取消选项 |
| S2 | 触发 grace period（Sandbox 加速续订失败 / 手动改 RC 测试 entitlement）→ 打开 Logbook | 顶部黄色横幅展示 N 天，点横幅 → 走 paywall（`.graceExpiring` displayKind） |
| S3 | 卸载重装 → 打开 paywall 点"恢复购买" | 1-3s 后状态行翻 Pro，无错误；网络断开时显示"网络异常，请稍后重试" |
| S4 | Family Share 副账号点"恢复购买" | 同 S3，subscription 来源经 RC 同步识别为家庭共享 |
| S5 | Ask to Buy：购买后 pending → 家长批准 → app 在前台保持 | Profile 状态行从"等待家长审批"翻"Pro 已激活"，OSLog 记录翻转事件 |
| S6 | 在 paywall 内点 "恢复购买" 但当前账号无任何订阅 | 显示"没有可恢复的订阅"，无网络错误误报 |

### 5.3 不做

- `manageSubscriptionsSheet` 自身渲染（Apple 黑盒，无法单测）
- 14 天宽限期跨日界 / DST 切换的精确边界（Calendar API 已处理；过度测试边际收益低）
- pending → pro 翻转的"app 在后台"场景（Session B 不实现，无意义测试）

---

## § 6. 风险 & Mitigation

| # | 风险 | Mitigation |
|---|---|---|
| 1 | `manageSubscriptionsSheet` Sandbox 可能不弹 / 弹空 sheet | Apple 已知问题；smoke runbook 标注"Sandbox 测试此 sheet 不稳定属正常"，TestFlight / 正式环境验证 |
| 2 | Family Share restore 行为依赖 RC + Apple 后台同步 | 不在代码层兜底；smoke S4 做主路径验证，文档说明用户体感 |
| 3 | pendingApproval → pro 翻转 app 后台场景丢失 | Session B 不解决；OSLog 提供观测，必要时 Session C 加 lastSeenStatus 持久化 |
| 4 | 法律文档 URL 部署阻塞 Session B 验收 | 代码 commit 用 placeholder host (`https://placeholder.together-app.com/...`)；`LegalURLsTests` 守卫 `host !contains "example.com"`（不强制最终 host，避免 commit 被卡）；`docs/legal/README.md` 明确部署 owner = 运营，TestFlight 前替换 |
| 5 | grace banner 在 logbook 空态遮挡引导文案 | banner 占用顶部 1 行；空态文案下移；smoke 验证 |
| 6 | Pro grant 来源（无 expiresAt）UI 文案错误 | DetailSection 显式分支 `.pro(.grant)` → "终身 Pro"，单测覆盖 |

---

## § 7. 部署 / 运营前置条件

| # | 事项 | Owner | Session B 是否阻塞 |
|---|---|---|---|
| 1 | 法律文档草稿补齐（开发者名 / 邮箱 / 生效日期 / 宽限期条款） | 运营 / 产品 | 不阻塞 commit；阻塞 TestFlight |
| 2 | Privacy / ToS 公网 URL 部署（方案见 § 10.D4） | 运营 | 同上 |
| 3 | RC Dashboard：grace period 推送（可选）| 运营 | 不阻塞（Session B 仅前台 toast）|
| 4 | Sandbox 家庭共享测试账号 | 测试 | 阻塞 smoke S4 |

---

## § 8. Accessibility 基线

- `ManageSubscriptionLink`：a11y label "在 App Store 管理订阅"，hint "双击打开订阅管理"
- `GracePeriodBanner`：a11y label "订阅已到期，剩 N 天可看全历史"，trait `.button`，hint "双击立即续订"，N 用 `String.localizedStringWithFormat` + 整数本地化
- `ProfileSubscriptionDetailSection`（grace 态）：a11y combine 把多行子标题拼成单一朗读串
- 续费日期：用 `Date.formatted(.dateTime.year().month().day())` 默认本地化；VoiceOver 读出完整日期
- 深度审计（VoiceOver 全流程 / RTL / Dynamic Type 极限）留 Session C

---

## § 9. i18n

- 所有新文案走 `String(localized:)`
- 数字插值（N 天）走 `IntegerFormatStyle` 本地化
- 日期走 `Date.formatted(.dateTime.year().month().day())`
- 法律文档：Session B 仅中文版；英文版留 Session C 上架前

---

## § 10. 决策摘要（v4 全部落定）

| # | 议题 | 决策 | 理由 |
|---|---|---|---|
| **D1** | 续费日期来源 | **A. 不扩展模型**，View 层读 `latestEntitlementExpiration` | 避免双源；Phase 2 commit 7 已暴露并测试 |
| **D2** | "在 App Store 管理订阅" 实现 | **A. SwiftUI `manageSubscriptionsSheet`** | Apple 推荐路径；不离开 app；不需 UIKit scene 桥接 |
| **D3** | Ask to Buy 翻转反馈 | **A + animation**：状态行视觉变化 + `.transition + .animation` 过渡 + OSLog | 零新组件；scope 最小；动画补足体感 |
| **D4** | 法律文档公网 URL 部署 | **D. 暂用占位 URL** | 让代码 plan 不阻塞运营进度；运营拍板部署方案后单独 PR 替换（pre-TestFlight 必做）|
| **D5** | Profile Free 态独立 restore 按钮 | **A. 不新增** | UpsellContent 内置 restore 已可见；新增会重复；如后续反馈不显眼再升级 B |

技术决策（架构边界、数据流、合并器入 queue、生命周期归属、文案中性化、关联值形态、视觉过渡）在 v0 → v1 → v2 → v3 → v4 自 review 已全部收敛。

本 spec 准备就绪，可进入 writing-plans 阶段拆 task 级 TDD plan。

---

## § 11. Commit 计划

| # | Commit | 依赖 |
|---|---|---|
| 1 | `feat(premium): add LegalURLs constants + tests` | — |
| 2 | `refactor(paywall): wire PaywallLegalFooter to LegalURLs` | 1 |
| 3 | `feat(premium): add UpsellTrigger.graceExpiring + UpsellDisplayKind + UpsellCopy variant + tests` | — |
| 4 | `feat(paywall): refine PaywallViewModel.handleRestoreOutcome error tiers + tests` | — |
| 5 | `feat(profile): add ManageSubscriptionLink` | — |
| 6 | `feat(profile): add ProfileSubscriptionDetailSection (4 states) + tests` | 5 |
| 7 | `feat(profile): wire ProfileSubscriptionView to detail section` | 6 |
| 8 | `feat(logbook): add GracePeriodBanner + tests` | 3 |
| 9 | `feat(logbook): wire CompletedHistoryView grace banner` | 8 |
| 10 | `feat(premium): add PendingApprovalObserver + tests` | — |
| 11 | `feat(premium): register PendingApprovalObserver in AppContainer` | 10 |
| 12 | `feat(paywall): add .graceExpiring dedup nil rule in RootPaywallPresentation` | 3 |
| 13 | `docs(legal): fill draft placeholders + add grace period clause` | — |
| 14 | `docs(paywall): phase-3-session-b smoke runbook (S1–S6)` | 1–12 |

14 个 commit（commit 9 / 10 原"ProfileRestoreButton" 替换为"PendingApprovalObserver"）。每个独立通过测试后再下一步；Session A + B 全 suite 在 commit 11 后和 14 后各跑一次回归。

**Pre-TestFlight 单独 PR**（不在本 spec 14 commit 内）：
- 替换 `LegalURLs` 常量为终值（运营拍板部署方案后）
- 法律文档草稿 `[NEEDS_OPERATOR_INPUT]` 填实

---

## § 12. 自 review 记录

- **v0 (内部草稿)**: 初稿
- **v0 → v1**: 打掉 7 条
  - R1: 续费日期来源是否扩展模型 → § 2.1 决策不扩展，避免双源
  - R2: grace banner 是否走合并器 → § 2.3 入 RootPaywallPresentation queue，与 Session A 设计原则一致
  - R3: ManageSubscriptionLink 是否要 RC 封装 → § 2.2 直接 StoreKit 2 SwiftUI modifier，避免 UIKit 桥接
  - R4: pendingApproval → pro 翻转的后台场景 → § 2.6 风险栏明确不解决，OSLog 观测即可
  - R5: 是否复用 PaywallViewModel 整个 → § 2.10 仅复用 `PaywallPurchasingProtocol` 接口
  - R6: LegalURLs 是否阻塞 commit → § 2.8 / § 6.4 占位 URL 可合 main，弱守卫只校验 host !contains "example.com"
  - R7: grace banner 是否可关闭 → § 2.3 不可关闭，区分 lapse（可关）vs grace（硬时间窗）
- **v1 → v2**: 打掉 16 条
  - R8: § 1.1 把"新增 .graceExpiring"错归为"已有资产" → 移到 § 1.3 改动；§ 1.1 改为"现有 case 不动，本 session 新增见 § 1.3"
  - R9: § 1.3 重复列了两次 `UpsellCopy` 路径（Features/Paywall + Services/Premium） → 后者删除
  - R10: § 2.1 `.pro(.grant)` 来源 expiresAt 为 nil 的行为没规定 → 补显式分支"由 Together 团队赠送 · 终身有效"
  - R11: § 2.2 minDeployment 假设未核对 → 加确认 step（commit 4 前 git grep）
  - R12: § 2.5 新增 case 的编译期 ripple 没列清 → 加 Switch case 完整性 ripple 说明
  - R13: § 2.6 `PremiumGate` 通知机制未确认 → 加 commit 11 前置确认；如缺则先暴露 AsyncStream
  - R14: § 2.8 `LegalURLs.subscription` 多余 → 删除（Apple 不要求单独页）
  - R15: § 2.10 实现骨架自相矛盾（"复用协议"又"直调 Purchases.shared"） → 整个 § 2.10 重写为 scope 重新评估，发现 Profile Free 态已通过 UpsellContent 内置 restore，不应新增按钮 → 改 D5 决策为"不新增"
  - R16: § 3.2 banner 同时写"整行可点"和 "[续订 →]"按钮，结构矛盾 → 澄清为单个 Button + 视觉箭头
  - R17: § 3.3 ProfileRestoreButton 成功态 1.5s hold 与 status 翻 Pro 后 View 切分支冲突 → 整个 § 3.3 重写为"不新增组件"
  - R18: § 4.2 `EdgeInsets.zero` API 不存在 → 改 `EdgeInsets()`
  - R19: § 5.2 S2 用"24h"描述 Sandbox 加速时间不准 → 改"Sandbox 加速续订失败 / 手动改 RC 测试 entitlement"
  - R20: § 6.4 测试守卫"release schema 强制非占位"不可行（Swift Testing 无 schema 区分）→ 改弱守卫只查 host !contains "example.com"
  - R21: § 2.6 PendingApprovalObserver 绑 AppRootView.onDisappear 错位 → 改归属 AppContainer 进程级
  - R22: § 2.10 / D5 重新定义为"是否新增独立按钮"而非"是否在 Session B 加 restore 入口"（restore 已在 Free 态可见）
  - R23: § 2.1 续费日期文案 "下次续费" 误导已取消但仍 active 的用户 → 改中性 "有效期至"；willRenew 区分留 Session C
  - R24: § 2.4 `.graceExpiring` 合并器 dedupKey 策略未定义 → 显式 nil（不去重，主动点击不可被吃掉）
  - 副产物：§ 1.2 / § 1.3 / § 11 commit 计划随 R15 / R17 重排，14 个 commit 顺序保持不变但 9-10 由 ProfileRestore 替换为 PendingApprovalObserver；§ 4 加 4.5 AppContainer 注册；§ 5.2 smoke 增 S6
- **v2 → v3**: 打掉 2 条
  - R25: § 3.1 grace 态 "立即续订"按钮 enqueue 路径未说明 → 加 "通过环境对象 rootPaywallPresentation"，关联值 daysRemaining 传递
  - R26: § 2.5 N 关联值显式形态 → `case graceExpiring(daysRemaining: Int)` 明确（避免实现时再纠结）
- **v3 → v4**: 5 条产品/运营决策由用户拍板（D1-A / D2-A / D3-A+animation / D4-D / D5-A）；ripple 到 § 2.6（加 animation）+ § 10（决策摘要从"待拍板"变"全部落定"）
- **v4 收敛判定**：
  - 全部产品/运营决策已落定
  - 技术决策（架构 / 数据流 / 合并器 / 生命周期 / 文案 / 关联值形态 / 视觉过渡）全部收敛
  - 每轮自 review 问题数：（v0 内化）→ 7 → 16 → 2 → 0；用户拍板 v4 一次性收敛
  - 14 个 commit 颗粒度独立可测；编译期强制 case 完整性
  - 与 Session A 协议层 / 合并器 / 状态机零冲突
  - 进入 writing-plans 阶段

- **v4 → v5（执行期 + smoke 期补）**：打掉 R27 共 1 条
  - **R27 / Smoke S1 撞 bug**：v4 spec 默认 view 直接读 `gate.status`，但 status 不含 DEBUG override；新加 view 内 `switch gate.status` 拆 case 时 picker 切 Pro/Grace 走 `.unknown` 命中 EmptyView（详情见 plan v3 的 PP1 复盘）
  - **修复**（v5 落地）：spec 加 § 2.1.1 PremiumGate `effectiveStatus` API；3 处 view + Observer 改读 effective；Service 层（OSLog 诊断）保留 raw；hotfix commit `c550dd9` + 回归测试 `PremiumGateEffectiveStatusTests` 7 case
  - **教训**：Spec / Plan 应显式标"View 层读 effectiveStatus"（架构原则）；新加 view 时 review 应 cover raw vs effective 区分。Session C 写 spec 时记得开头列此原则
- **v5 收敛判定**：
  - R27 闭环（spec 补 § 2.1.1 + 回归测试）
  - 真机 smoke S1/S2/S5 PASS；S3/S4/S6 留 TestFlight
  - 法律 URL 部署 production（github.com/kb24123456/together-app-legal）
  - tag `phase-3-session-b-stable` 已推 origin
  - Session B scope 全部完成；进入 TestFlight / Session C 评估
