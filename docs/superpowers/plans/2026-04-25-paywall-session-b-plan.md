# Phase 3 · Session B — 订阅管理 + Grace Period UI + 合规文案 TDD Plan

- **Date**: 2026-04-25
- **Status**: **v3** — v1 → v2 → v3 收敛（v3 加 smoke 期间撞 bug 复盘 + effectiveStatus 回归守卫）
- **Spec**: `docs/superpowers/specs/2026-04-25-paywall-session-b-design.md` (v4)
- **Base commit**: `34ec1af` (tag `phase-3-session-a-stable`)
- **Execution mode**: Subagent-Driven TDD —— 复杂 task 双 review（spec + code quality），简单 task 仅 spec review
- **不含**：Session C 内容（a11y 深度审计 / .storekit 文件 / Sentry / 跨设备 onboarding）；纪念日正计时（独立 feature）；运营资产（法律 URL 部署 / RC Dashboard 配置）

---

## § -1. Pre-flight Check（开工前必跑）

```bash
cd /Users/papertiger/Desktop/Together
git status                                                                  # 必须 clean
git merge-base --is-ancestor phase-3-session-a-stable HEAD && echo ok       # tag 必须是 HEAD 祖先
git fetch origin && git log --oneline origin/main..HEAD                     # 确认本地未 diverge（空输出 = 已同步）
xcodebuild -scheme Together-UnitTests -quiet build-for-testing
xcodebuild test -scheme Together-UnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30      # Session A 全 suite 绿
```

任何一项失败 → 不开工；先排查再开始 Task 1。

---

## § 0. 前置条件

代码前置（已在 main / `34ec1af`）：
- [x] `PremiumStatus` enum 含 `.gracePeriod(originalExpiry, logbookFullUntil)` / `.pro(source, expiresAt)`
- [x] `PremiumGate.latestEntitlementExpiration`（Phase 2 commit 7 / Session A Task 7 已暴露）
- [x] `RootPaywallPresentation` 合并器（Session A Task 5）
- [x] `PaywallPurchasingProtocol` + `RevenueCatPaywallPurchasing`（Session A Task 1-2）
- [x] `UpsellTrigger.Kind` + `UpsellDisplayKind` + `UpsellCopy`（Session A Task 3 / v8 § 2.8）
- [x] `ProSubscriptionStatus.pendingApproval` case + 文案（Session A Task 9c）
- [x] `PaywallLegalFooter` 占位 URL + `legalBodyText`（Session A Task 6）
- [x] `docs/legal/privacy-policy.md` / `terms-of-service.md` 草案（Session A 准备）

运营前置（smoke 测试前必备，代码不阻塞）：
- [ ] Sandbox 家庭共享测试账号（用于 Smoke S4）
- [ ] Sandbox 加速续订失败模拟方案（用于 Smoke S2 grace 触发）
- [ ] 法律文档 `[NEEDS_OPERATOR_INPUT]` 字段填实（pre-TestFlight 必做，不阻塞 commit）
- [ ] Privacy / ToS 公网 URL 部署（pre-TestFlight 必做，不阻塞 commit）

---

## § 1. Task 清单

14 个 task，严格按依赖顺序；每个 task 独立通过测试 + commit 后再下一步。14 task 对应 14 commit。

### Task 1 — `LegalURLs` 常量 + tests

**依赖**: 无
**复杂度**: 低 · 仅 spec review
**产出文件**:
- `Together/Services/Premium/LegalURLs.swift`
- `TogetherTests/LegalURLsTests.swift`

**实现要点**（spec § 2.8）:
```swift
enum LegalURLs {
    static let privacy = URL(string: "https://placeholder.together-app.com/privacy")!
    static let terms = URL(string: "https://placeholder.together-app.com/terms")!
}
```

**Tests**（Swift Testing `@Suite`）:
- `privacy.scheme == "https"` && `terms.scheme == "https"`
- `privacy.host` 不含 `"example.com"` && `terms.host` 不含 `"example.com"`
- 两个 URL 都成功构造（force unwrap 不会 trap）
- 注释提醒：终值在 pre-TestFlight 单独 PR 替换

**验收**:
- 编译通过；测试全绿

**commit**: `feat(premium): add LegalURLs constants + tests`

---

### Task 2 — `PaywallLegalFooter` 接 `LegalURLs`

**依赖**: Task 1
**复杂度**: 低 · 仅 spec review
**产出文件**: `Together/Features/Paywall/PaywallLegalFooter.swift`（修改）

**实现要点**:
- 删除局部 `private static let privacyURL` / `termsURL`
- 改为 `LegalURLs.privacy` / `LegalURLs.terms`
- 不动 `legalBodyText`

**Tests**: 无新测试（Session A 既有 PaywallLegalFooter 渲染测试如有则 grep 确认仍绿）

**验收**:
- 编译通过；既有测试绿
- 视觉上 paywall sheet legal footer 行为不变

**commit**: `refactor(paywall): wire PaywallLegalFooter to LegalURLs`

---

### Task 3 — `UpsellTrigger.graceExpiring` + `UpsellDisplayKind.graceExpiring` + `UpsellCopy` + tests

**依赖**: 无
**复杂度**: 中 · 双 review
**产出文件**:
- `Together/Services/Premium/UpsellTrigger.swift`（修改）
- `Together/Features/Paywall/UpsellDisplayKind.swift`（修改）
- `Together/Features/Paywall/UpsellCopy.swift`（修改）
- `TogetherTests/UpsellCopyTests.swift`（扩展）

**实现要点**（spec § 2.4 / § 2.5）:
- `UpsellTrigger.Kind` 加 `case graceExpiring(daysRemaining: Int)`
- `Kind.toDisplayKind()` 加 `.graceExpiring(daysRemaining: Int)` 映射
- `UpsellDisplayKind` 加 `case graceExpiring(daysRemaining: Int)`
- `UpsellCopy.heroText(for:)`：`.graceExpiring → "续订 Together Pro，保留你的回忆"`
- `UpsellCopy.subtitleText(for:)`：`.graceExpiring(let n) → "你的订阅将在 \(n) 天后彻底失效。续订后立即恢复完整体验。"`
- `UpsellCopy.benefitsOrder(for:)`：`.graceExpiring` 与 `.generic` 一致

**Ripple 检查**：编译期 switch case 完整性会强制以下函数补齐 case：
- `Kind.toDisplayKind`
- `heroText(for:)` / `subtitleText(for:)` / `benefitsOrder(for:)`
- 任何已有的 `switch trigger.kind { ... }` / `switch displayKind { ... }`
- `RootPaywallPresentation.keyFor(trigger:)` —— 本 task 内**仅占位**让编译过：`case .graceExpiring(let n): return "graceExpiring_\(n)"`（dedup 真值 nil 留 Task 12 + 测试）

**Tests**（扩展 `UpsellCopyTests`）:
- `.graceExpiring(daysRemaining: 7)` hero 字面值
- `.graceExpiring(daysRemaining: 7)` subtitle 含 "7 天" 字串
- `.graceExpiring(daysRemaining: 1)` subtitle 含 "1 天"
- `.graceExpiring` benefits 数量 + 首位与 `.generic` 一致

**验收**:
- 编译通过（含所有依赖 switch）；测试全绿

**commit**: `feat(premium): add UpsellTrigger.graceExpiring + UpsellDisplayKind + UpsellCopy variant + tests`

---

### Task 4 — `PaywallViewModel.handleRestoreOutcome` 错误文案分级 + tests

**依赖**: 无（Session A `PaywallViewModel` 已就位）
**复杂度**: 低 · 仅 spec review
**产出文件**:
- `Together/Features/Paywall/PaywallViewModel.swift`（修改）
- `TogetherTests/PaywallViewModelTests.swift`（扩展）

**实现要点**（spec § 2.10 A 选项）:
- `handleRestoreOutcome(_ outcome: PaywallPurchaseOutcome)` 内文案分级：
  - `.success` → 走原 success 路径不动
  - `.nothingToRestore` → `.error(message: "没有可恢复的订阅")`
  - 网络异常（PaywallError.network）→ `.error(message: "网络异常，请稍后重试")`
  - 其他 → `.error(message: "恢复失败，请联系支持")`
- 已有的 `.error(.network)` 翻译路径保持不变；本 task 仅细分文案

**Tests**（扩展 `PaywallViewModelTests`）:
- restore stub 返回 `.success` → state 进入 succeeded 分支（既有断言）
- restore stub 返回 `.nothingToRestore` → state.error.message == "没有可恢复的订阅"
- restore stub throw `PaywallError.network` → state.error.message == "网络异常，请稍后重试"
- restore stub throw `PaywallError.unknown` → state.error.message == "恢复失败，请联系支持"

**验收**:
- 编译通过；新增 4 个测试 case 全绿；既有 PaywallViewModelTests 不回归

**commit**: `feat(paywall): refine PaywallViewModel.handleRestoreOutcome error tiers + tests`

---

### Task 5 — `ManageSubscriptionLink` View

**依赖**: 无
**复杂度**: 低 · 仅 spec review
**产出文件**: `Together/Features/Profile/ManageSubscriptionLink.swift`

**实现要点**（spec § 2.2 / D2-A）:
```swift
struct ManageSubscriptionLink: View {
    @State private var showManagement = false

    var body: some View {
        Button {
            showManagement = true
        } label: {
            Label("在 App Store 管理订阅", systemImage: "creditcard")
        }
        .manageSubscriptionsSheet(isPresented: $showManagement)
        .accessibilityHint("双击打开订阅管理")
    }
}
```

**前置确认**：`xcodebuild -showBuildSettings -scheme Together -project Together.xcodeproj 2>&1 | grep IPHONEOS_DEPLOYMENT_TARGET`（一次性，确认 ≥ 15.0；项目实际 17+，纯防御性确认）

**Tests**: 无（StoreKit sheet Apple 黑盒，纯 modifier 无可测状态机）；Smoke S1 间接验证

**验收**:
- 编译通过
- Preview 渲染按钮（`#Preview`）

**commit**: `feat(profile): add ManageSubscriptionLink`

---

### Task 6 — `ProfileSubscriptionDetailSection`（4 态）+ tests

**依赖**: Task 3 + Task 5（grace 态 `enqueue(.graceExpiring(...))` 需要 case 已存在）
**复杂度**: 中 · 双 review
**产出文件**:
- `Together/Features/Profile/ProfileSubscriptionDetailSection.swift`
- `TogetherTests/ProfileSubscriptionDetailSectionTests.swift`

**实现要点**（spec § 3.1 + D3-A+animation）:
```swift
struct ProfileSubscriptionDetailSection: View {
    let status: PremiumStatus
    let expiration: Date?  // = premiumGate.latestEntitlementExpiration
    @Environment(RootPaywallPresentation.self) private var rootPaywallPresentation

    var body: some View {
        Group {
            switch status {
            case .pro(.subscription, _):       proActiveBody
            case .pro(.grant, _):              proGrantBody
            case .gracePeriod(_, let until):   graceBody(until: until)
            // pendingApproval 由 ProSubscriptionStatus 派生（spec § 2.6）
            // 当 status == .pro 但实际是 pending 待批，由 ProfileSubscriptionView 在外层判断
            default:                           EmptyView()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.3), value: status)
    }

    // proActiveBody: 标题 + "有效期至 [expiration]" + ManageSubscriptionLink
    // proGrantBody:  标题 + "由 Together 团队赠送 · 终身有效"
    // graceBody:     黄色背景 + 标题 + "剩 N 天可看全历史" + 续订按钮 (enqueue) + ManageSubscriptionLink
    // pendingBody:   标题 + "批准后自动激活" + 无管理按钮
}
```

**关键决策**（spec § 2.1 / § 2.6）:
- `expiration` 显式分支 nil（grant 来源时）
- 中性文案 "有效期至" 而非 "下次续费"
- pendingApproval 实际不在 `PremiumStatus` 内 → 该态由 `ProfileSubscriptionView` 在外层独立处理（见 Task 7）；本 view 不渲染 pending 态
- `RootPaywallPresentation` 通过 environment 注入，grace 续订按钮 enqueue `.graceExpiring(daysRemaining: N)`

**Tests**（Swift Testing `@Suite` + ViewInspector 或 snapshot 二选一；用现有项目惯例）:
- `.pro(.subscription, expiresAt: 2026-12-31)` → 文案含 "有效期至" + 日期 + 含 "管理订阅" 按钮
- `.pro(.grant, expiresAt: nil)` → 文案含 "终身有效"，不含管理按钮
- `.gracePeriod(originalExpiry: now-1d, logbookFullUntil: now+7d)` → 文案含 "剩 7 天" + 含续订按钮 + 含管理按钮
- `.pro(.subscription, expiresAt: nil)` → 防御 fallback，文案 "订阅有效"，不 crash
- enqueue stub：grace 态点续订按钮调用 `enqueue(.graceExpiring(daysRemaining: 7))`

**验收**:
- 4 + 1 = 5 个测试 case 全绿
- Preview 4 态都能渲染

**commit**: `feat(profile): add ProfileSubscriptionDetailSection (4 states) + tests`

---

### Task 7 — `ProfileSubscriptionView` 接入 detail section

**依赖**: Task 6
**复杂度**: 中 · 双 review
**产出文件**: `Together/Features/Profile/ProfileSubscriptionView.swift`（修改）

**实现要点**（spec § 4.1）:
- 替换 `proPlaceholder` 占位 VStack
- Pro / grace / pendingApproval 三层判断：
  ```swift
  let gate = appContext.container.premiumGate
  if isPendingApproval {  // 由 ProSubscriptionStatus 推导（Session A 已加）
      pendingApprovalBody  // 简单文案 view
  } else if gate.isPremium {
      ProfileSubscriptionDetailSection(
          status: gate.status,
          expiration: gate.latestEntitlementExpiration
      )
      .environment(rootPaywallPresentation)  // 通过现有 environment 注入
  } else {
      freeState  // 现有 PaywallViewModel + UpsellContent，不动
  }
  ```
- pendingApproval 判断逻辑：复用 Session A 已实现的 `ProSubscriptionStatus.pendingApproval` 推导（如果 Session A 未在 view 层暴露则需要确认数据流）
- Free 态保留 `UpsellContent` 内置 restore 不变（D5-A）

**前置确认**：commit 前 grep `pendingApproval` 在 ProfileSubscriptionView 当前的处理方式；确认从 `ProSubscriptionStatus` 还是 `PremiumStatus` 派生

**Tests**: 无新测试（view 层接入；逻辑覆盖在 Task 6）；Preview 验证 4 态切换

**验收**:
- 编译通过
- Preview 切换 4 态都正确渲染
- DEBUG override picker 切换不 crash

**commit**: `feat(profile): wire ProfileSubscriptionView to detail section`

---

### Task 8 — `GracePeriodBanner` + tests

**依赖**: Task 3
**复杂度**: 中 · 双 review
**产出文件**:
- `Together/Features/Logbook/GracePeriodBanner.swift`
- `TogetherTests/GracePeriodBannerTests.swift`

**实现要点**（spec § 2.3 / § 3.2）:
```swift
struct GracePeriodBanner: View {
    let logbookFullUntil: Date
    var now: Date = .now                       // DI for testing
    var calendar: Calendar = .current          // DI for testing (生产 .current 跟随用户 timezone)

    @Environment(RootPaywallPresentation.self) private var rootPaywallPresentation

    private var daysRemaining: Int {
        max(1, calendar.dateComponents([.day], from: now, to: logbookFullUntil).day ?? 1)
    }

    var body: some View {
        Button {
            rootPaywallPresentation.enqueue(.graceExpiring(daysRemaining: daysRemaining))
        } label: {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("订阅已到期 · 剩 \(daysRemaining) 天可看全历史")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.horizontal, AppTheme.spacing.md)
            .padding(.vertical, AppTheme.spacing.sm)
            .background(AppTheme.colors.warningSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("订阅已到期，剩 \(daysRemaining) 天可看全历史")
        .accessibilityHint("双击立即续订")
        .accessibilityAddTraits(.isButton)
    }
}
```

**Tests**（注入固定 `calendar`：`Calendar(identifier: .gregorian)` + `TimeZone(identifier: "UTC")` 避免 device timezone flakiness）:
- `now=2026-01-01 00:00 UTC, logbookFullUntil=2026-01-08 00:00 UTC` → daysRemaining == 7
- `now=2026-01-01, logbookFullUntil=2026-01-02` → daysRemaining == 1
- `now=2026-01-08, logbookFullUntil=2026-01-08` → daysRemaining == 1（min 1 守卫）
- `now=2026-01-09, logbookFullUntil=2026-01-08`（边界过期）→ daysRemaining == 1
- 文案断言：`"订阅已到期"` + `"剩 N 天可看全历史"`
- enqueue stub：点击触发 `enqueue(.graceExpiring(daysRemaining: 7))`

**验收**:
- 6 个测试 case 全绿
- Preview 渲染（注意 RootPaywallPresentation 在 Preview 用 stub）

**commit**: `feat(logbook): add GracePeriodBanner + tests`

---

### Task 9 — `CompletedHistoryView` 接入 banner

**依赖**: Task 8
**复杂度**: 低 · 仅 spec review
**产出文件**: `Together/Features/Profile/CompletedHistoryView.swift`（修改）

**实现要点**（spec § 4.2）:
```swift
List {
    if case .gracePeriod(_, let until) = appContext.container.premiumGate.status {
        Section {
            GracePeriodBanner(logbookFullUntil: until)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
    // 既有 sections（含 LogbookPairSummaryHero）
}
```

**Plan 内决断（不在 spec）**：
- banner 在配对模式 `LogbookPairSummaryHero` **之上**（grace 是更高优先级的"硬时间窗"通知；用户应先看到再决定续订）
- 空态时也显示（不被空态文案吃掉）
- UX 走查 follow-up：如设计反馈不当，调整为 Section header inset 或合入 hero

**Tests**: 无新测试

**验收**:
- 编译通过
- Preview / DEBUG override 切到 `.gracePeriod` 时顶部出现横幅
- 切回 `.pro` 横幅消失（无残留布局）

**commit**: `feat(logbook): wire CompletedHistoryView grace banner`

---

### Task 10 — `PendingApprovalObserver` + tests

**依赖**: 无（PremiumGate 已存在）
**复杂度**: 中 · 双 review
**产出文件**:
- `Together/Services/Premium/PendingApprovalObserver.swift`
- `TogetherTests/PendingApprovalObserverTests.swift`

**前置确认**（commit 前必跑）：
```bash
git grep -n "@Observable\|@Published\|AsyncStream<PremiumStatus" Together/Services/Premium/PremiumGate.swift
```
- 若 `PremiumGate` 已是 `@Observable` → Observer 用 `Observation.Tracking` 或 `withObservationTracking`
- 若有 Combine `@Published` → Observer 用 sink
- 若都没有 → **本 task 拆分**：先加一个独立 commit 暴露 `AsyncStream<PremiumStatus>` 或转 `@Observable`，再做 Observer

**实现要点**（spec § 2.6 + D3-A）:
```swift
@MainActor
final class PendingApprovalObserver {
    private let premiumGate: PremiumGate
    private let logger = Logger(subsystem: "Together", category: "PendingApprovalObserver")
    private var lastSeenStatus: PremiumStatus?
    private var task: Task<Void, Never>?

    init(premiumGate: PremiumGate) {
        self.premiumGate = premiumGate
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            // 监听 status 流（具体形态由前置确认决定）
            for await status in self?.premiumGate.statusStream ?? .init { _ in } {
                self?.handle(newStatus: status)
            }
        }
    }

    func stop() { task?.cancel() }

    private func handle(newStatus: PremiumStatus) {
        defer { lastSeenStatus = newStatus }
        guard case .pendingApproval = lastSeenStatus,  // 或 ProSubscriptionStatus 推导
              case .pro = newStatus else { return }
        logger.info("Pending approval transitioned to active")
    }
}
```

**注**：`lastSeenStatus` 用 `PremiumStatus` 还是 `ProSubscriptionStatus`？决策：用 `ProSubscriptionStatus`（pendingApproval 来源）；如 `PremiumStatus` 不含 pending case 则需要从 `ProSubscriptionStatus` 派生。前置确认中再敲定。

**Tests**:
- 序列 `[.unknown, .pendingApproval, .pro]` → `handle` 触发 1 次
- 序列 `[.unknown, .pro]` → 0 次
- 序列 `[.pendingApproval, .free]` → 0 次（pending → free 不算成功翻转）
- 序列 `[.pendingApproval, .pro, .pendingApproval, .pro]` → 2 次
- 序列 `[.pendingApproval, .pendingApproval, .pro]` → 1 次（中间状态不重复触发）

**验收**:
- 5 个测试 case 全绿
- 编译通过；无 Sendable 警告

**commit**: `feat(premium): add PendingApprovalObserver + tests`

---

### Task 11 — `AppContainer` 注册 `PendingApprovalObserver`

**依赖**: Task 10
**复杂度**: 低 · 仅 spec review
**产出文件**: `Together/AppContext/AppContainer.swift`（或同名 / 同层文件，commit 前 `find` 确认路径）

**实现要点**（spec § 4.5）:
- AppContainer 持有 `let pendingApprovalObserver: PendingApprovalObserver`
- `init` 末尾调 `pendingApprovalObserver.start()`
- 进程级生命周期；不绑 view onDisappear

**Tests**: 无新测试（容器组装）

**验收**:
- 编译通过
- 启动 app 后 OSLog 中出现 `Logger("PendingApprovalObserver")` 在 status 变化时的日志
- 关闭 app 重启后无重复触发

**commit**: `feat(premium): register PendingApprovalObserver in AppContainer`

---

### Task 12 — `RootPaywallPresentation.keyFor` 把 `.graceExpiring` 占位 key 改为 `nil` + tests

**依赖**: Task 3
**复杂度**: 低 · 仅 spec review
**产出文件**:
- `Together/Features/Paywall/RootPaywallPresentation.swift`（修改）
- `TogetherTests/RootPaywallPresentationTests.swift`（扩展）

**实现要点**（spec § 2.4）:
- 把 Task 3 中的占位 `case .graceExpiring(let n): return "graceExpiring_\(n)"` 改为 `case .graceExpiring: return nil`
- 不去重（用户主动点击不应被吃掉）

**Tests**（扩展 `RootPaywallPresentationTests`）:
- 连续 enqueue 两次 `.graceExpiring(daysRemaining: 7)` → queue 内有 2 个待处理（未去重）
- enqueue `.graceExpiring(7)` 再 enqueue `.lapse(...)` → 都入 queue（独立条目）
- 已有 `.lapse` dedup 行为不回归

**为什么拆 commit**：Task 3 用占位 key 让全项目编译通过；Task 12 是真正的 dedup 策略 + 行为测试。这样可以独立 git revert 任一段。

**验收**:
- 3 个新测试全绿；既有 RootPaywallPresentationTests 不回归

**commit**: `feat(paywall): switch .graceExpiring dedupKey to nil + tests`

---

### Task 13 — 法律文档草稿补齐 + 宽限期条款

**依赖**: 无
**复杂度**: 低 · 仅 spec review（文档审阅）
**产出文件**:
- `docs/legal/privacy-policy.md`（修改）
- `docs/legal/terms-of-service.md`（修改）
- `docs/legal/README.md`（如不存在则新建，注明部署 owner = 运营）

**实现要点**（spec § 2.9 / § 7）:
- 把"草案"标注替换为正式版
- 占位字段（开发者主体名 / 联系邮箱 / 生效日期）改为 `[NEEDS_OPERATOR_INPUT: 开发者主体名]` 等显式占位标记，便于运营 grep 替换
- ToS 加宽限期条款（产品 spec § 5.2 搬运）：
  - 订阅自动续费失败后，自动进入 14 天宽限期
  - 宽限期内可继续看全历史、所有 Pro 功能不变
  - 宽限期由 Apple 控制，期满 Apple 自动降级为 Free
  - 宽限期间用户随时可在 Apple 订阅设置内重新订阅恢复
- ToS 加自动续费章节（已在 PaywallLegalFooter 文案，文档版本同步）

**Tests**: 无（文档）

**验收**:
- 两份文档可读；占位标记清晰
- README 明确：运营拍板部署方案 + URL 落地后单独 PR 替换 `LegalURLs` 常量

**commit**: `docs(legal): fill draft placeholders + add grace period clause`

---

### Task 14 — Session B Smoke Runbook (S1–S6)

**依赖**: Task 1-12（代码完成）
**复杂度**: 低 · 仅 spec review
**产出文件**: `docs/superpowers/runbooks/phase-3-paywall-smoke.md`（追加 Session B 部分）

**实现要点**（spec § 5.2）:
- 追加 "## Session B 真机 smoke (S1-S6)" 章节
- 每个场景：前置（账号 / 状态）、操作、期望、实际记录占位、不通过的处理路径
- S1: 在 App Store 管理订阅
- S2: Grace period 横幅 + 续订
- S3: 卸载重装 restore
- S4: Family Share restore
- S5: Ask to Buy pending → active 翻转
- S6: nothingToRestore 错误文案

**Tests**: 无

**验收**:
- runbook 章节完整；占位字段（实际结果 / 截图链接）就绪

**commit**: `docs(paywall): phase-3-session-b smoke runbook (S1-S6)`

---

## § 2. Milestone 回归 / tag

完成 Task 12 后（代码全部就位）：
- 跑完整 Phase 2 + Session A + Session B 全 test suite 确认绿
- 修补任何回归

完成 Task 14（含真机 smoke 全 PASS）后：
- `git tag phase-3-session-b-stable`
- push tag 到 origin

Pre-TestFlight 单独 PR（不在本 14 commit 内）：
- 替换 `LegalURLs` 常量为运营拍板的终值 URL
- 把 `[NEEDS_OPERATOR_INPUT]` 字段填实

---

## § 3. 总工期估算

| Task | 估时 |
|---|---|
| 1 + 2（LegalURLs + footer 接入）| 1h |
| 3（UpsellTrigger.graceExpiring + ripple + tests）| 1.5h |
| 4（restore 错误文案分级 + tests）| 1h |
| 5 + 6 + 7（ManageSubscriptionLink + DetailSection + 接入）| 3.5h |
| 8 + 9（GracePeriodBanner + 接入）| 2h |
| 10 + 11（PendingApprovalObserver + AppContainer 注册，含前置确认拆分风险）| 2.5h |
| 12（合并器 dedup nil + tests）| 0.5h |
| 13（法律文档草稿补齐）| 1h |
| 14（runbook）| 1h |
| 真机 smoke | 2h |
| **合计** | **~16h ≈ 1 工作日** |

Session A 用了 22h；Session B scope 较小（5 模块 vs 10 模块 + 合并器 + 状态机），符合 spec § 0 估计。

---

## § 3.5 Rollback 策略

**原则**：**不 amend 已推送的 commit**；不 force-push。每个 task commit 失败后按下列处理：

| 失败类型 | 处理 |
|---|---|
| 测试红 | 同 task 内 fix + 新 commit；squash 由 review agent 判断 |
| 架构选型翻车（实现后发现 spec 某处不可行）| **pause 本 task**，回 spec 改 → bump 版本号 → 再开 task；不在 plan 内偷偷改方向 |
| Session A 回归 | 立即 pause 整个 Session B；先独立 bugfix commit；Session A suite 全绿后再续 |
| Phase 2 回归 | 同上 |
| 已推送后发现错 | `git revert <commit>` + 新 commit；**不 reset** |
| `PremiumGate` 通知机制不存在（Task 10 前置确认失败）| 拆 commit 10a "expose status stream" + 10b "add PendingApprovalObserver"；不在 Task 10 内塞两个改动 |
| `ProSubscriptionStatus.pendingApproval` 数据流不清楚（Task 7 前置确认失败）| 同上拆分；先独立 commit 澄清数据流 |

已 push 的 commit 永远不改历史；Together repo 无 force-push 授权。

---

## § 4. 风险清单（执行期）

| 风险 | 缓解 |
|---|---|
| Task 10 PremiumGate 通知机制不存在 → 需要先暴露 stream | Task 10 前置确认；如缺则按 § 3.5 拆 commit 10a/10b |
| Task 7 pendingApproval 在 view 层的派生路径与 Session A 文档不一致 | Task 7 前置确认；必要时拆出独立 refactor commit |
| `ProfileSubscriptionDetailSection` 的 `RootPaywallPresentation` environment 注入路径与 Session A 设计不一致 | Task 6 前先 grep `RootPaywallPresentation` 注入点；如需调整接入点列入风险 |
| `manageSubscriptionsSheet` Sandbox 不弹（Apple 已知问题）| 已在 spec § 6 风险 1 标注；smoke S1 失败不阻塞 commit，TestFlight 验证 |
| Family Share restore 行为不可控（依赖 RC + Apple 后台）| 已在 spec § 6 风险 2 标注；smoke S4 失败时记录 + 文档化用户体感 |
| grace banner 在配对模式 `LogbookPairSummaryHero` 之上 / 之下决策可能与 UI 走查冲突 | Task 9 接入后 Preview 双模式核对；如 UX 反馈不对再调整为 Section header inset |
| ProfileSubscriptionDetailSection 的 `.transition` 动画在 PremiumStatus 反复变化时闪烁（Session A debug override picker）| Task 6 测试覆盖；必要时 `.animation(value: status)` 替换为更稳定 trigger |

---

## § 5. 自 review 记录

- **v1**：初稿，按 spec § 11 的 14 commit 拆 14 task
- **v1 → v2**：打掉 P1-P6 共 6 条
  - P1: Task 6 依赖只写了 Task 5 → 应同时依赖 Task 3（grace 态用 `.graceExpiring` case）
  - P2: Task 8 GracePeriodBanner 用 `Calendar.current` 在测试时 timezone flake → DI calendar 参数；测试注入 UTC + Gregorian
  - P3: Task 3 ripple 列了 `RootPaywallPresentation.keyFor` 但 Task 12 又"加 dedup" 重复 → Task 3 用占位 key 让编译过；Task 12 改为真正的 nil 策略 + 测试，commit message 改 "switch ... to nil"
  - P4: Task 5 minDeployment 确认用 `git grep` 不可靠 → 改 `xcodebuild -showBuildSettings | grep IPHONEOS_DEPLOYMENT_TARGET`
  - P5: Task 9 banner 在 `LogbookPairSummaryHero` 之上 / 之下不在 spec 内决断 → plan 内合理决断（之上），并标注 UX 走查 follow-up
  - P6: 缺 v1 → v2 review 记录 → 本节补齐
- **v2 收敛判定**：
  - 14 task 拓扑闭环；Task 3 / 6 / 8 / 12 互相依赖关系清晰
  - 所有测试断言注入可重现的 fixture（DI calendar / now / mock observer）
  - rollback 策略覆盖 PremiumGate 通知机制不存在 / pendingApproval 数据流不清楚两个高风险点
  - 14 task = 14 commit（含 Task 3 占位 + Task 12 nil 策略 split）
  - 进入 writing-tests / 执行 Task 1 阶段

- **v2 → v3（Smoke 期间发现 + 复盘）**：打掉 PP1 共 1 条
  - **PP1 / Smoke S1 撞 bug**：`ProfileSubscriptionDetailSection` 切到 Pro/Grace 态显示空白
    - **根因**：plan 没区分 `PremiumGate.status`（raw 合并状态，不含 DEBUG override）vs "view 应读的 effective status"。Task 6/7/9 的 view 都直接读 `gate.status`，DEBUG override picker 切换时 `isPremium` 翻 true 进 Pro 分支，但 detail section switch 走 `.unknown` → `EmptyView`
    - **Fix**（commit `c550dd9`）：PremiumGate 加 `effectiveStatus` getter (`overrideStatus ?? status`)；ProfileSubscriptionView / CompletedHistoryView / PendingApprovalObserver 3 处改读 `effectiveStatus`；AppContext 诊断 OSLog 保留 raw status
    - **回归守卫**（独立 commit）：`PremiumGateEffectiveStatusTests` 7 case 显式测试 raw vs effective 分离行为
  - **教训**（应进 Session C plan）：
    - **Spec / Plan 应显式区分 raw status vs effective status**——View 层默认应该用 effective；Service 层（lapse 检测、诊断 log、内部合并逻辑）才用 raw。Session B 之前从未需要这个区分（isPremium 已经是 computed 含 override），但加 view 直接 `switch status` 暴露盲区
    - **Smoke 验证前应用 DEBUG override picker 自验**——这正是 picker 的设计目的；执行期跑过 Preview 但没在真机走 picker → 单元测试也没区分 raw vs effective → bug 直到真机 smoke 才暴露
- **v3 收敛判定**：
  - PP1 闭环（hotfix + 回归测试 + plan 复盘）
  - 全 suite + 真机 smoke S1/S2/S5 PASS；S3/S4/S6 留 TestFlight（DEBUG mock 天然限制）
  - tag `phase-3-session-b-stable` 已推 origin
  - 法律 URL 部署（together-app-legal repo + GitHub Pages）已 production；LegalURLs.swift 已替换 placeholder
  - 进入下一阶段（TestFlight 准备 / Session C scope 评估）
