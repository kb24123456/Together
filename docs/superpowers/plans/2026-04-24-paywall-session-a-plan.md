# Phase 3 · Session A — 核心付费墙 + 购买流 TDD Plan

- **Date**: 2026-04-24
- **Status**: **v4** — 经 3 轮自 review 收敛
- **Spec**: `docs/superpowers/specs/2026-04-24-paywall-session-a-design.md` (v8)
- **Base commit**: `4f00683` (tag `phase-2-premium`)
- **Execution mode**: Subagent-Driven TDD —— 复杂 task 双 review（spec + code quality），简单 task 仅 spec review
- **不含**：Session B/C 内容；a11y 深度审计；真 RC Dashboard production key

---

## § -1. Pre-flight Check（开工前必跑）

```bash
cd /Users/papertiger/Desktop/Together
git status                                                             # 必须 clean
git merge-base --is-ancestor phase-2-premium HEAD && echo ok           # phase-2-premium 必须是 HEAD 的祖先
git fetch origin && git log --oneline origin/main..HEAD                # 确认本地未 diverge（空输出 = 已同步）
xcodebuild -scheme Together-UnitTests -quiet build-for-testing
xcodebuild test -scheme Together-UnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30  # Phase 2 全 suite 绿
```

Scheme 名由 `xcodebuild -list -project Together.xcodeproj` 验证过：`Together-UnitTests` 是测试专用 scheme。

任何一项失败 → 不开工；先排查再开始 Task 1。

## § 0. 前置条件

代码前置（已在 main / `4f00683`）：
- [x] `PremiumGate` + `RCClientProtocol` + `RevenueCatClient` + `GrantsLoader`
- [x] `UpsellTrigger` enum
- [x] `ImportantDatesViewModel.pendingUpsellTrigger` + `dismissUpsell()`
- [x] `ProjectsViewModel.pendingUpsellTrigger` + `dismissUpsell()`
- [x] `RevenueCatConfig.publicSDKKey`（DEBUG test store key 已配）
- [x] `ProfileDebugSection` override picker（DEBUG）

运营前置（smoke 测试前必备，代码不阻塞）：
- [ ] RC Dashboard offering mark current + 至少 1 个 package
- [ ] RC entitlement `pro` attach 所有 package
- [ ] Sandbox Apple ID 在真机登录

---

## § 1. Task 清单

13 个 task（含 Task 9 拆的 4 个子 task 9a–9d），严格按依赖顺序；每个 task 独立通过测试 + commit 后再下一步。13 task 对应 13 commit。

### Task 1 — `PaywallPurchasingProtocol` + 数据类型 + `PaywallError`

**依赖**: 无
**复杂度**: 中 · 双 review
**产出文件**:
- `Together/Features/Paywall/PaywallPurchasing.swift` — 协议 + `PaywallOffering` / `PaywallPackage` / `PaywallPeriod` / `PaywallIntroOffer` / `PaywallPurchaseOutcome`
- `Together/Features/Paywall/PaywallError.swift` — enum + `init(from: Error)` 从 RC SDK 翻译

**关键决策已定**（spec § 2.2）:
- `PaywallPackage` 结构化字段（price: Decimal + currencyCode + period，非字符串）
- `PaywallPurchaseOutcome` 4 case：success / cancelled / pending / nothingToRestore
- `PaywallError` case：noOfferings / network / unknown / entitlementNotReady / nothingToRestore / debugOverrideMasksPro (`#if DEBUG`)

**验收**:
- 编译通过（含 Swift 6 strict concurrency：所有类型 `Sendable`）
- 无运行时逻辑要测；`PaywallError.init(from:)` 翻译表在 Task 4 测

**commit**: `feat(paywall): add PaywallPurchasingProtocol + models + PaywallError`

---

### Task 2 — `RevenueCatPaywallPurchasing` 生产实现

**依赖**: Task 1
**复杂度**: 低 · 仅 spec review
**产出文件**: `Together/Features/Paywall/RevenueCatPaywallPurchasing.swift`

**实现要点**（spec § 2.2 / § 2.11 末尾）:
- 持有 `[String: RevenueCat.Package]` 缓存；`loadOfferings` 清空后重填
- `loadOfferings` 读 `Purchases.shared.offerings().current`；nil 抛 `PaywallError.noOfferings`
- `purchase(packageID:)`：从缓存查 Package → `Purchases.shared.purchase(package:)` → 映射 RC 结果到 `PaywallPurchaseOutcome`
- `restorePurchases`：调 SDK → 检查 entitlement isActive → `.success` / `.nothingToRestore`
- 翻译层：RC `Package` / `StoreProduct` / `SubscriptionPeriod.Unit` → `PaywallPackage` 本地类型

**验收**:
- 编译通过
- 薄 pass-through 实现不写单测（Phase 2 `RevenueCatClient` 同策略）
- Task 11（真机 smoke）间接验证

**commit**: `feat(paywall): add RevenueCatPaywallPurchasing production impl`

---

### Task 3 — `UpsellCopy` 文案层 + tests

**依赖**: Task 1
**复杂度**: 低 · 仅 spec review
**产出文件**:
- `Together/Features/Paywall/UpsellCopy.swift` — 纯函数 + 常量
- `TogetherTests/UpsellCopyTests.swift`

**实现要点**（spec § 2.4 / § 2.11）:
- `UpsellDisplayKind` enum（spec § 2.1）
- hero 按 kind 切的字典（标题 / 副标 / `.lapse` banner）
- benefits 4 项固定顺序 + 按 trigger 首位提升算法
- `formatPriceLine(_: PaywallPackage) -> String`
- `formatTrial(_: PaywallIntroOffer?) -> String?`
- `legalBodyText(for: PaywallPackage?) -> String`（Apple 模板变量插值）

**Tests**（Swift Testing `@Suite`）:
- 每个 UpsellTrigger hero 文案 + benefit 首位
- `.lapse` banner 文本
- `.generic` fallback hero
- `formatPriceLine` 各周期（month/year/week/day + 多 unit）
- `formatTrial` 有/无免费试用 + 非免费介绍价
- `legalBodyText` nil pkg vs 具体 pkg

**commit**: `feat(paywall): add UpsellCopy + tests (format price / trial / legal)`

---

### Task 4 — `PaywallViewModel` + tests

**依赖**: Task 1, 3
**复杂度**: 高 · 双 review
**产出文件**:
- `Together/Features/Paywall/PaywallViewModel.swift` — `@MainActor @Observable`
- `TogetherTests/Stubs/StubPaywallPurchasing.swift` — `actor` 实现
- `TogetherTests/PaywallViewModelTests.swift`
- `TogetherTests/PaywallErrorTests.swift` — `PaywallError.init(from:)` 翻译表

**状态机**（spec § 2.3 / § 2.10 / § 2.12）:
- 8 个 ViewState case + `isInFlight`（含 `.succeeded`）+ `finishOnce` gate + `hasFinished` flag
- `purchaseSelected` 成功路径：`refresh()` → DEBUG override 分支 → `isPremium` 校验 → `.succeeded` → `holdThenFinish`
- `successHoldDuration: Duration = .seconds(1.2)` init 参数，测试注入 `.zero`

**中段 checkpoint**（防止 4h 一口气跑丢）:
- 2h 点：VM 骨架 + stub actor + state enum 完成 → 跑最小 test（load → ready）通过 → `git stash` 或 WIP marker（**不提交正式 commit**）作为断点
- 之后再推购买 / restore / error / finishOnce 路径，最终一次性整 commit

（避免与 § 3.5 "不 amend 已提交" 规则冲突 —— 中段不算正式 commit）

**Tests 矩阵**:
- State 转换：idle → load → ready；cancel/pending/nothingToRestore/network 分支；purchase success / entitlementNotReady / debugOverrideMasksPro；restore success / nothingToRestore
- `finishOnce` gate：succeeded 期间 requestClose 不应触发 `.userClosed` 覆盖 `.purchasedOrRestored`
- `onFinished` 只被调一次
- `isInFlight` 在 purchasing / restoring / succeeded 为 true
- `dismissError()` 回 ready

**Stub 行为**:
- `actor StubPaywallPurchasing` 可配置 `nextPurchaseOutcome: Result<PaywallPurchaseOutcome, Error>` 队列
- fixed offering：3 个 package（月/年 + 年含 7 天试用）

**PaywallErrorTests**:
- RC `ErrorCode.purchaseCancelledError` → `.cancelled`（via outcome，不进 PaywallError）
- RC `ErrorCode.networkError` → `.network`
- 未知 Error → `.unknown`

**commit**: `feat(paywall): add PaywallViewModel + tests (stub purchasing actor)`

---

### Task 5 — `RootPaywallPresentation` + tests

**依赖**: Task 3（需要 `UpsellDisplayKind` 给 `Kind.toDisplayKind()` 映射）
**复杂度**: 中 · 双 review
**产出文件**:
- `Together/Features/Paywall/RootPaywallPresentation.swift` — `@MainActor @Observable`
- `TogetherTests/RootPaywallPresentationTests.swift`

**实现要点**（spec § 2.8）:
- `Kind` enum `.quota(UpsellTrigger)` / `.lapse(PremiumLapseNotice)`
- `Kind.toDisplayKind() -> UpsellDisplayKind` extension
- `requestTrigger` 追加队尾 + 去重
- `requestLapse` 插队列头 + 不 preempt 当前 presenting
- `dismissCurrent` pop 队头到 presenting

**Tests**:
- 空态 requestTrigger → 立即 presenting
- 已 presenting + requestTrigger → 入队
- requestLapse 插队头（presenting 不变）
- dismissCurrent 按顺序出队（lapse 先出）
- 去重：同 trigger 连续请求只入队一次
- 同 kind 已 presenting 时新请求被丢弃

**commit**: `feat(paywall): add RootPaywallPresentation + tests`

---

### Task 6 — `UpsellContent` + `UpsellSheet` + `PaywallPackageCard` + `PaywallLegalFooter` + previews

**依赖**: Task 3, 4
**复杂度**: 中 · 仅 spec review（View 层，主要人工看 Preview）
**产出文件**:
- `Together/Features/Paywall/UpsellContent.swift`
- `Together/Features/Paywall/UpsellSheet.swift`
- `Together/Features/Paywall/PaywallPackageCard.swift`
- `Together/Features/Paywall/PaywallLegalFooter.swift`

**实现要点**（spec § 3.1 / § 3.2 / § 3.3 / § 2.11）:
- `UpsellContent(displayKind:, viewModel:)` 主体 —— hero / benefits / packages / CTA / inline error / restore / legal footer
- `UpsellSheet` ZStack + `Image(systemName: "xmark.circle.fill")` 手搓 close（不用 NavigationStack）
- Package 卡片：选中态橙色边框 + 试用徽章
- `PaywallLegalFooter` 变量插值模板 + `https://example.com/placeholder` 占位 URL
- error inline：所有 `.failed` case 走 inline 红字（除 `.pendingApproval` 是静默关 sheet）
- 成功 overlay：`.succeeded` 时大 checkmark + "已解锁 Together Pro"
- a11y 基线（spec § 9）：每个 card `accessibilityLabel` + CTA `accessibilityHint` + success checkmark label

**Previews**:
- `UpsellContent` — 4 种 displayKind × 2 种 state（ready / succeeded）
- `PaywallPackageCard` — selected / unselected / with-trial
- `PaywallLegalFooter` — 有 pkg / nil pkg

**验收**:
- Xcode Preview 全部跑通（stub 注入）
- Dynamic Type 默认 / XL 肉眼可读
- 无硬编码颜色（走 `AppTheme`）

**commit**: `feat(paywall): add UpsellContent + UpsellSheet + PaywallPackageCard + PaywallLegalFooter + previews`

---

### Task 7 — `PremiumGate.latestEntitlementExpiration` 只读属性

**依赖**: 无
**复杂度**: 低 · 仅 spec review
**产出文件**: `Together/Services/Premium/PremiumGate.swift`（改动）

**实现**（spec § 2.5）:
- private `cachedProExpirationDate: Date?`
- `safeFetchRC` 成功分支追加缓存（无条件写，不管 isActive）
- public `latestEntitlementExpiration: Date? { cachedProExpirationDate }`
- 不改 `computeStatus` 合并算法；不改现有 public API

**验收**:
- 跑 Phase 2 全 suite（`TogetherTests`）全绿 —— 无回归
- Phase 2 `PremiumGateLifecycleTests` / `PremiumGateMergeTests` / `PremiumStatusTests` / `PremiumStatusCacheTests` 全绿

**commit**: `feat(premium): expose PremiumGate.latestEntitlementExpiration`

---

### Task 8 — `PremiumGateRefreshTests` 审计 + 补齐（Phase 2 debt）

**依赖**: Task 7
**复杂度**: 中 · 仅 spec review
**产出文件**:
- `TogetherTests/PremiumGateRefreshTests.swift`

**实现要点**（spec § 6.1 / R44）:
1. 先读 `PremiumGateLifecycleTests.swift` 现有 6 tests，列出覆盖的 refresh 场景
2. 补齐缺口：
   - 连续 refresh race — 只保留最后一次结果
   - refresh 期间 logOut 作废
   - refresh 失败时保留上次 status（不回退到 unknown）
   - `latestEntitlementExpiration` 在 refresh 失败分支不被 overwrite（用 stale RC client）
3. 避免 `Task.sleep` 依赖，用 `AsyncStream` 信号控制释放时机（follow-up #2 同类教训）

**验收**:
- 新 suite 全绿
- Phase 2 全 suite 仍绿
- CI 多跑 10 次无 flaky

**commit**: `test(premium): audit + extend PremiumGateRefreshTests (Phase 2 debt)`

---

### Task 9a — AppRootView sheet 挂点 + AppContext 持有合并器 + LapseAcknowledgedStore

**依赖**: Task 5, 6
**复杂度**: 中 · 双 review
**产出 / 改动**:
- `Together/Features/Paywall/LapseAcknowledgedStore.swift` — 新增（spec § 2.5）
- `Together/App/AppContext.swift`
  - 新增 `rootPaywallPresentation: RootPaywallPresentation`
  - 新增 `lapseAcknowledgedStore: LapseAcknowledgedStore`
  - 新增 `paywallPurchasing: PaywallPurchasingProtocol`（DI RevenueCatPaywallPurchasing）
  - 新增 `paywallDidDismiss(kind:)` 方法
- `Together/App/AppRootView.swift`
  - 唯一 `.sheet(item: $appContext.rootPaywallPresentation.presenting)` 挂点
  - `.onChange(of: presenting)` 变 nil 调 `paywallDidDismiss`

**验收**:
- App 启动跑通（未触发任何 sheet）
- DEBUG override 切 Free → Pro 无 sheet 弹出（override 保护）
- 编译通过，现有测试全绿

**commit**: `feat(paywall): mount rootPaywallPresentation + single .sheet on AppRootView`

---

### Task 9b — 替换配额 alert 为付费墙 sheet（Anniversaries + Projects）

**依赖**: 9a
**复杂度**: 中 · 双 review
**改动文件**:
- `Together/Features/Anniversaries/ImportantDatesManagementView.swift:50-61` — 删 alert；加 `.onChange(of: viewModel.pendingUpsellTrigger)` 触发 `requestTrigger`
- `Together/App/AppRootView.swift:72-83` — 删 alert；加同类 onChange（观察 `appContext.projectsViewModel.pendingUpsellTrigger`）

**验收**:
- 真机：Free override → 建第 6 个纪念日 → sheet 弹（不是 alert）；买成功 → 关 sheet → 再建不拦
- 真机：Free override → 建第 4 个项目 → 同上
- Phase 2 `ImportantDatesViewModelQuotaTests` / `ProjectsViewModelQuotaTests` 无需改动，仍绿

**commit**: `feat(paywall): replace quota alerts with paywall sheet (Anniversaries + Projects)`

---

### Task 9c — Profile 主动入口 + SubscriptionView 重写

**依赖**: 9a
**复杂度**: 中 · 双 review
**改动文件**:
- `Together/Features/Profile/ProfileSubscriptionView.swift` — 重写：按 `premiumGate.status` 分支（Free → `UpsellContent(displayKind: .generic, viewModel: localVM)`；Pro/grace → `ProSubscriptionPlaceholder`）
- `Together/Features/Profile/ProfileProEntryRow.swift` 或上级 — Pro 态子标题增加 `.pendingApproval` 态（spec § 10 ③ 决策）
- 删除现有 `ProFeatureRow` 占位视图（被 UpsellContent 替代）

**实现要点**:
- local VM factory：`makeLocalPaywallViewModel(dismissAction:)` 持有 `onFinished` closure，`.purchasedOrRestored` 时 `dismissAction()` pop nav
- `ProSubscriptionStatus` 扩 `.pendingApproval` case（spec § 2.10）

**验收**:
- Free 用户 Profile 点 Pro 行 → nav push → UpsellContent 显示 generic hero
- Pro 用户点 → Placeholder（Session B 充实）
- `.pendingApproval` 子标题 "等待家长审批" 显示

**commit**: `feat(paywall): wire Profile manual entry + SubscriptionView Free/Pro branch`

---

### Task 9d — Pro→Free lapse UI surface + DEBUG 模拟按钮 + dedup

**依赖**: Task 7, 9a
**复杂度**: 中 · 双 review
**改动文件**:
- `Together/Features/Paywall/PremiumLapseNotice.swift` — 新增 struct + `debugSample(now:)` 工厂
- `Together/App/AppContext.swift:984 handlePremiumStatusChange` — 从 `premiumGate.latestEntitlementExpiration` 读真实 expired；DEBUG override 分支 skip；计算 dedupKey；contains 检查；调 `requestLapse`
- `Together/Features/Profile/ProfileDebugSection.swift` — 新增 "🧪 模拟 Pro→Free lapse sheet" 按钮（DEBUG only）

**验收**:
- 真机场景 7a：DEBUG 按钮 → sheet 弹；关 → 再点 → 再弹（UUID dedup）
- 真机场景 7b：override Pro → Free → **sheet 不弹**（override 保护；OSLog 有 `lapsed at runtime` 但无 `paywall.lapse.requested`）
- Phase 2 `handlePremiumStatusChange` 数据面逻辑（`stopSoloSync`）不回归

**commit**: `feat(paywall): surface Pro→Free lapse via rootPaywallPresentation + DEBUG simulator + dedup`

---

### Task 10 — Session A smoke runbook

**依赖**: 9a–9d
**复杂度**: 低 · 仅 spec review
**产出文件**: `docs/superpowers/runbooks/phase-3-paywall-smoke.md`

**内容**（spec § 6.2 覆盖）:
- 前置准备（Sandbox Apple ID / test store / RC Dashboard mark current）
- 10 个真机场景 checklist
- 失败模式排障（RC `customerInfo` 不 propagate / offerings.current nil / Ask to Buy 卡 pending）
- OSLog 检查清单（subsystem `com.pigdog.Together/Premium`）

**验收**:
- 至少跑过场景 1/2/3/5/7a/8 一次打勾
- 场景 6/9 （卸载重装 / Ask to Buy）需 Sandbox 家庭账号，若无则标注 "待 Session B/C 验证"

**commit**: `docs(paywall): phase-3-session-a smoke runbook`

---

## § 2. Milestone 回归 / tag

完成 Task 10 后：
- `git tag phase-3-session-a`
- 跑完整 Phase 2 + Session A 全 test suite 确认绿
- push tag 到 origin

Phase 3 Session B 入场前：本 session 的 12 个 commit 全在 main；可 revert 整段但不预期会 revert。

---

## § 3. 总工期估算

| Task | 估时 |
|---|---|
| 1 + 2（协议 + 生产实现）| 2h |
| 3（UpsellCopy + tests）| 1.5h |
| 4（VM + tests + stub）| 4h |
| 5（合并器 + tests）| 1.5h |
| 6（View 层 + Preview）| 4h |
| 7（PremiumGate 属性）| 0.5h |
| 8（refresh tests）| 1.5h |
| 9a-9d（接入 + lapse）| 4h |
| 10（runbook）| 1h |
| 真机 smoke | 2h |
| **合计** | **~22h ≈ 1.5 工作日** |

与 memory 中 spec § 11 "1-1.5 天" 一致（真实人 + subagent 混合节奏）。

---

## § 3.5 Rollback 策略

**原则**：**不 amend 已推送的 commit**；不 force-push。每个 task commit 失败后按下列处理：

| 失败类型 | 处理 |
|---|---|
| 测试红 | 同 task 内 fix + 新 commit；两个小 commit 合并为一个 squash 由 review agent 判断 |
| 架构选型翻车（实现后发现 spec 某处不可行）| **pause 本 task**，回 spec 改 → bump 版本号 → 再开 task；不在 plan 内偷偷改方向 |
| Phase 2 回归 | 立即 pause 整个 Session A；先独立 bugfix commit；Phase 2 suite 全绿后再续 |
| 已推送后发现错 | `git revert <commit>` + 新 commit；**不 reset** |

已 push 的 commit 永远不改历史；Together repo 无 force-push 授权。

## § 4. 风险清单（执行期）

| 风险 | 缓解 |
|---|---|
| RC SDK 版本与 Phase 2 集成版本不兼容 | 锁定 Phase 2 已验证版本；不升级 SPM |
| Swift 6 strict concurrency 违规 | 所有新类型立即加 `Sendable`；CI 跑 `-strict-concurrency=complete` |
| Preview 注入 stub 在 SwiftUI 新版 `#Preview` 语法下失败 | 提前在 Task 6 起头 5 分钟验证单文件 Preview；失败回退到 `PreviewProvider` |
| Task 9a-9d 整合阶段出现 sheet 冲突 | spec § 2.8 合并器是架构解；真遇到冲突查是否有 View 层残留 `.sheet` 挂点 |
| Phase 2 refresh 测试补齐发现深 bug | Task 8 如果发现 bug → 立即 pause Session A + 独立 bugfix commit（不塞进 Task 8 commit） |

---

## § 5. 自 review 记录

- **v1**：初稿，按 spec § 11 的 12 commit 拆 12 task
- **v1 → v2**: 打掉 P1-P4 共 4 条（Task 5 依赖错 / 缺 pre-flight check / 缺 rollback 策略 / Task 4 缺中段 checkpoint）
- **v2 → v3**: 打掉 PP1-PP3 共 3 条（`git describe` 改 `merge-base`；scheme 名验证用 `Together-UnitTests`；中段 checkpoint 措辞与 rollback 策略一致化）
- **v3 → v4**: 打掉 PPP1 共 1 条（task 数量笔误：12 → 13，含 9a-9d 拆分）
- **v4 收敛判定**：每轮问题数 4 → 3 → 1 → 0；task 拓扑 / 验收 / review 级别 / 风险 / rollback / pre-flight / 计数一致性全部闭环
