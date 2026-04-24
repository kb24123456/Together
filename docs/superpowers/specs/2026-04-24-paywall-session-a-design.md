# Phase 3 · Session A — 核心付费墙 + 购买流 Design Spec

- **Date**: 2026-04-24
- **Status**: **v8** — 经 7 轮自 review + § 10 全部决策落地；可进入 writing-plans 阶段
- **Scope**: 把 Phase 2 已有的 `UpsellTrigger` 通道接到真付费墙 UI + RevenueCat 购买流，替换 3 处 alert 占位，加 Profile 主动升级入口。
- **Inputs**:
  - 产品决策：`docs/superpowers/specs/2026-04-22-premium-tier-split-design.md`（§ 3 撞墙 UX、§ 5.2 降级、§ 2 Pro 功能清单）
  - 技术基础：`docs/superpowers/specs/2026-04-22-premium-infrastructure-design.md`
  - Phase 2 落地：`memory/project_together_progress.md`（HEAD `4f00683`, tag `phase-2-premium`）

---

## § 0. 目标 & Non-Goals

### Session A 必须完成

1. `UpsellSheet` + `UpsellContent`（View 拆分）—— 按 `UpsellTrigger` 差异化 hero / benefit 排序
2. RevenueCat Offerings 拉取 + 产品列表渲染（结构化 `PaywallPackage`，非字符串）
3. 购买状态机：idle → loading → success / error（含 cancel / pending / 网络失败 / entitlementNotReady）
4. **恢复购买** 按钮
5. 购买成功 → `PremiumGate.refresh()` → 严格校验 `isPremium` → 关 Sheet 回原界面
6. 替换现有 3 处 alert 占位：
   - `ImportantDatesManagementView`（纪念日配额）
   - `AppRootView`（项目配额）
   - `AppContext.handlePremiumStatusChange`（Pro→Free 运行时）
7. `ProfileProEntryRow` / `ProfileSubscriptionView` Free 态主动升级入口复用 `UpsellContent`
8. **Sheet 合并器**：AppRootView 上所有 paywall sheet 走单一 `RootPaywallPresentation` 聚合状态，解决同层双 sheet 冲突
9. **合规占位**：购买按钮附近预留自动续费条款 / Privacy / ToS 链接结构（文案和 URL 由 Session B 填）
10. **Phase 2 债**：补 `PremiumGateRefreshTests`（Phase 2 遗留 follow-up #1），Session A 既然重度依赖 `refresh()` 就一起还

### Session A 不覆盖（留 Session B / C）

- Pro 态订阅管理（当前方案、续费日期、"在 App Store 管理订阅" 链接）
- Grace Period 专用 UI（Logbook 顶部横幅）
- 真正的合规**文案** / Privacy / ToS **URL**（Session B）
- 新设备首次打开的一次性 `.crossDeviceSync` 入口（本 session 实现触发机制，但产品侧触发点在其他 session 做）
- VoiceOver / Dynamic Type 深度审计（本 session 只落 a11y 基线，见 § 9）
- StoreKit Configuration 文件、Sentry / Crashlytics（Session C）
- 价格数字 / 方案数量 / 试用天数（运营 + Pricing spec）

---

## § 1. 架构边界

### 1.1 已有资产（复用，不改）

| 资产 | 位置 |
|---|---|
| `UpsellTrigger` enum | `Together/Services/Premium/UpsellTrigger.swift` |
| `PremiumGate.refresh()` | `Together/Services/Premium/PremiumGate.swift:70` |
| `RevenueCatClient` / `RCClientProtocol` | 同目录 |
| `RevenueCatConfig.entitlementIdentifier = "pro"` | 同目录 |
| `premiumLogger`（OSLog subsystem `com.pigdog.Together/Premium`） | AppContext |

### 1.2 新增文件

```
Together/Features/Paywall/
├── PaywallPurchasing.swift             # PaywallPurchasingProtocol + 数据类型
├── RevenueCatPaywallPurchasing.swift   # 生产实现（包 Purchases.shared）
├── PaywallError.swift                  # UI 层错误 enum + RC error 翻译
├── UpsellCopy.swift                    # hero/benefits 纯数据层
├── PaywallViewModel.swift              # @Observable 状态机
├── UpsellContent.swift                 # 主体视图（无 sheet 包装，可嵌 Profile）
├── UpsellSheet.swift                   # 轻量 sheet 包装（close btn + UpsellContent）
├── PaywallPackageCard.swift            # 单产品卡
├── PaywallLegalFooter.swift            # 合规占位（链接结构到位，URL/文案 Session B 填）
└── RootPaywallPresentation.swift       # sheet 合并器：quota + lapse + manual 统一驱动

Together/App/
└── AppContext.swift                    # 改动：premiumLapseNotice + 持久化去重 + 合并器持有

TogetherTests/
├── PaywallViewModelTests.swift
├── UpsellCopyTests.swift
├── PaywallErrorTests.swift
├── RootPaywallPresentationTests.swift
└── PremiumGateRefreshTests.swift       # 还 Phase 2 debt
```

### 1.3 改动文件

| 文件 | 改动 |
|---|---|
| `Together/Features/Anniversaries/ImportantDatesManagementView.swift:50-61` | 删 `.alert`，改为向 `AppContext.rootPaywallPresentation` 请求展示 `.trigger(.anniversaryQuota)`（不在本视图上直接 `.sheet`，保留给 root 合并器） |
| `Together/App/AppRootView.swift:72-83` | 删 `.alert`；挂唯一的 `.sheet(item: $appContext.rootPaywallPresentation.presenting)` |
| `Together/App/AppContext.swift:984 handlePremiumStatusChange` | 新增：从 `PremiumGate` 读真实 `entitlementExpiredAt`，去重后推给 `rootPaywallPresentation` |
| `Together/Features/Profile/ProfileSubscriptionView.swift` | Free 态嵌 `UpsellContent`；Pro 态留占位（Session B 充实） |
| `Together/Features/Profile/ProfileProEntryRow.swift`（或上级调用点） | 点击 → `rootPaywallPresentation.requestManual()` |
| `Together/Features/Anniversaries/ImportantDatesViewModel.swift` / `Together/Features/Projects/ProjectsViewModel.swift` | `pendingUpsellTrigger` 改为只作为配额判定的副作用；合并器订阅变化→弹 sheet；`dismissUpsell()` 保留 |

### 1.4 依赖方向

```
UpsellSheet / UpsellContent (View)
   ↓ holds
PaywallViewModel (@Observable, @MainActor)
   ↓ depends on
PaywallPurchasingProtocol          PremiumGate (.refresh, isPremium 读)
   ↓ impl
RevenueCatPaywallPurchasing
   ↓ wraps
Purchases.shared (RevenueCat SDK)

AppContext
  ├── rootPaywallPresentation: RootPaywallPresentation
  │     ↑ ProjectsVM.pendingUpsellTrigger 观察
  │     ↑ ImportantDatesVM.pendingUpsellTrigger 观察
  │     ↑ AppContext.handlePremiumStatusChange 推入
  │     ↑ ProfileProEntryRow.tap 主动调 requestManual()
  └── premiumLapseAcknowledgedStore: UserDefaults-backed，去重已通知的 lapse
```

`PaywallPurchasingProtocol` 与 `RCClientProtocol` **不合并**：后者职责是 "PremiumGate 拉 entitlement 快照"，前者负责 "offerings 展示 + 购买 + 恢复"，生命周期和调用方都不同。

---

## § 2. 关键决策

### 2.1 View 拆分：`UpsellContent` + `UpsellSheet`（R62 修）

`UpsellContent` = 主体（hero + benefits + packages + CTA + restore + legal footer），不带 close button / sheet 装饰。

`UpsellSheet` = 薄包装 `{ UpsellContent + 右上 close + 下滑禁用逻辑 }`。

**统一 display kind**：UpsellContent 接口不耦合 `RootPaywallPresentation.Kind`（合并器专用）也不耦合 `UpsellTrigger?`（只含 quota），用独立的显示层类型：

```swift
enum UpsellDisplayKind: Equatable, Sendable {
    case trigger(UpsellTrigger)      // 配额拦截 → 差异化 hero
    case lapse(PremiumLapseNotice)   // Pro → Free → hero + 顶部 "订阅已到期" banner
    case generic                     // Profile 主动升级 → fallback hero
}
```

映射关系：

| 调用语境 | 入参 → UpsellDisplayKind |
|---|---|
| Sheet 合并器 `.quota(t)` | `.trigger(t)` |
| Sheet 合并器 `.lapse(n)` | `.lapse(n)` |
| Profile SubscriptionView Free 态 | `.generic` |

`UpsellContent(displayKind: UpsellDisplayKind, viewModel: PaywallViewModel)` 签名。

**理由**：Profile 主动入口走 nav push 不要 close；quota / lapse 触发走 sheet 要 close；两种语境共享 content 但 kind 类型不同。统一到 display kind 避免 View 层做 `switch Kind → UpsellTrigger?` 的冗余翻译。

### 2.2 购买抽象：独立协议 + 结构化数据（R1 修）

```swift
protocol PaywallPurchasingProtocol: Sendable {
    func loadOfferings() async throws -> PaywallOffering
    func purchase(packageID: String) async throws -> PaywallPurchaseOutcome
    func restorePurchases() async throws -> PaywallPurchaseOutcome
}

struct PaywallOffering: Sendable {
    let offeringID: String
    let packages: [PaywallPackage]
}

struct PaywallPackage: Identifiable, Sendable, Equatable {
    let id: String                              // RC package identifier
    let productID: String                       // ASC product ID
    let localizedTitle: String                  // StoreProduct.localizedTitle
    let localizedPriceString: String            // "¥28" (RC 已格式化，不含周期)
    let price: Decimal
    let currencyCode: String
    let subscriptionPeriod: PaywallPeriod?      // .week(1) / .month(1) / .year(1) / nil (非订阅)
    let introductoryOffer: PaywallIntroOffer?   // 结构化，含 free-trial 特例
}

enum PaywallPeriod: Sendable, Equatable {
    case day(Int), week(Int), month(Int), year(Int)
}

struct PaywallIntroOffer: Sendable, Equatable {
    let period: PaywallPeriod
    let price: Decimal        // 0 = 免费试用
    var isFreeTrial: Bool { price == 0 }
}

enum PaywallPurchaseOutcome: Sendable, Equatable {
    case success                // entitlement 立即生效（典型成功）
    case cancelled              // 用户在系统弹窗取消
    case pending                // Ask to Buy / SCA 等异步批准
    case nothingToRestore       // 仅 restorePurchases 返回：无可恢复的订阅
}
```

**RevenueCatPaywallPurchasing 生产实现要点**（R55 / R60 修）：

- `purchase`：`Purchases.shared.purchase(package:)` 接收 `Package` 对象；生产实现缓存最近一次 `loadOfferings()` 返回的 packages（`[String: Package]`，`loadOfferings` 清空后重填）；`purchase(packageID:)` 从缓存查 Package 调 SDK
- `restore`：调 `Purchases.shared.restorePurchases()` → 检查 `customerInfo.entitlements[RevenueCatConfig.entitlementIdentifier]?.isActive` → `true` → `.success`；`false / nil` → `.nothingToRestore`
- 所有 throw 的 RC 错误由 VM 层 catch 后通过 `PaywallError.init(from: Error)` 翻译为 UI 层 case

UI 层的 "¥28 / 月"、"前 7 天免费" 这些字符串在 `UpsellCopy.formatPrice(package:)` 等纯函数里拼，可单测。`RevenueCatPaywallPurchasing` 负责 RC `Package` / `StoreProduct` / `SubscriptionPeriod.Unit` → 本地类型的翻译。

### 2.3 状态机（R17 明确 closure）

```swift
@MainActor
@Observable
final class PaywallViewModel {
    enum ViewState: Equatable {
        case idle
        case loadingOfferings
        case ready(PaywallOffering)
        case purchasing(packageID: String)
        case restoring
        case pendingApproval           // Ask to Buy：关 sheet 不报错
        case succeeded                 // 已解锁，展示 1.2s 后关 sheet
        case failed(PaywallError)      // 可 retry 回 ready
    }

    private(set) var state: ViewState = .idle
    private(set) var selectedPackageID: String?
    private var hasFinished = false    // R59：防止 succeeded 1.2s hold 期间 close 导致双 finish
    var isInFlight: Bool {
        // succeeded 纳入 in-flight，避免 hold 期间 close 按钮可点
        switch state { case .purchasing, .restoring, .succeeded: true; default: false }
    }

    // 内部所有 onFinished 调用必经此 gate：
    private func finishOnce(_ reason: PaywallFinishReason) {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished(reason)
    }

    init(
        purchasing: PaywallPurchasingProtocol,
        premiumGate: PremiumGate,
        onFinished: @MainActor @escaping (PaywallFinishReason) -> Void,
        logger: Logger = premiumLogger
    )

    func load() async
    func selectPackage(_ id: String)
    func purchaseSelected() async
    func restore() async
    func dismissError()
    func requestClose()                // close button 调；内部 onFinished(.userClosed)
    // 下滑关走 AppRootView 的 .sheet binding set-nil 路径，不经过 VM（R48）
}

enum PaywallFinishReason {
    case purchasedOrRestored           // 关 sheet 回原场景
    case pendingApproval               // 关 sheet，静默等家长审批
    case userClosed                    // 手动关闭（含下滑）
}
```

**R49/R50 简化**：`.nothingToRestore` / `.entitlementNotReady` / `.debugOverrideMasksPro` 都走 `.failed(PaywallError)` inline 展示路径，不再穿透到外层 alert / finishReason。`PaywallFinishReason` 精简到 3 个 case。

成功路径：`.purchasing` → `await purchasing.purchase()` → outcome `.success` → `await premiumGate.refresh()` →
- `isPremium == true` → `state = .succeeded` → `await holdThenFinish()` → `onFinished(.purchasedOrRestored)`
- `isPremium == false`（RC 最终一致延迟）→ `state = .failed(.entitlementNotReady)` inline
- DEBUG + `premiumGate.overrideStatus != nil` → `state = .failed(.debugOverrideMasksPro)` inline（R58）

`.pending` outcome → `state = .pendingApproval` → 立即 `onFinished(.pendingApproval)`。

`.nothingToRestore` outcome（仅 restore 路径）→ `state = .failed(.nothingToRestore)` inline，用户看完自己决定关闭 / 重试。

**成功态 1.2s 计时**（R27 / R54 修）：放 VM 内部，时长作为 init 参数：

```swift
init(
    purchasing: PaywallPurchasingProtocol,
    premiumGate: PremiumGate,
    onFinished: @MainActor @escaping (PaywallFinishReason) -> Void,
    successHoldDuration: Duration = .seconds(1.2),   // 测试注入 .zero
    logger: Logger = premiumLogger
)

private func holdThenFinish() async {
    try? await Task.sleep(for: successHoldDuration)
    finishOnce(.purchasedOrRestored)
}
```

### 2.4 文案策略（R12 修）

hero 按 trigger 切；benefits 列表首位提升，其余按固定顺序。

| Trigger | Hero 标题 | Hero 副标 | Benefits 首位 |
|---|---|---|---|
| `.anniversaryQuota` | 记录所有重要的日子 | 免费版最多 3 个纪念日 | 无限纪念日 |
| `.projectQuota` | 让每个项目都有位置 | 免费版最多 3 个项目 | 无限项目 |
| `.logbookHistory` | 重温每一次完成 | 免费版仅查看近 30 天记录 | 全量 Logbook 历史 |
| `.crossDeviceSync` | 找回你在其他设备的数据 | 开启 iPhone 与 iPad 同步 | 本人跨设备同步 |
| `nil`（Profile / manual） | 升级 Together Pro | 解锁全部 Pro 功能 | 固定顺序 |

Lapse（Pro→Free）复用 `.crossDeviceSync` hero + 顶部加一行 "订阅已到期 · 升级恢复同步"。

Benefits 固定 4 项：本人跨设备同步（iPhone / iPad）· 无限纪念日 · 无限项目 · 全量 Logbook。**不提 Mac**（Together 无 macOS target）。

### 2.5 Pro → Free 的 surface：`PremiumLapseNotice` + 持久化去重（R6 / R11 / R32 修）

```swift
struct PremiumLapseNotice: Equatable, Sendable {
    let entitlementExpiredAt: Date?   // 来源 PremiumGate 最新 snapshot；未知则 nil（fallback 文案）
    let detectedAt: Date              // 本地检测到 lapse 的时间，仅用于去重 key
    var dedupKey: String              // e.g. "lapse:<entitlementExpiredAt or detectedAt floored to day>"
}

// UserDefaults: com.pigdog.Together.premium.lapseAcknowledgedKeys (Set<String>)
```

`handlePremiumStatusChange`：

```swift
func handlePremiumStatusChange(wasPremium: Bool, isPremium: Bool) async {
    guard wasPremium, !isPremium else { return }
    premiumLogger.info("Premium lapsed at runtime — stopping solo sync")
    await container.syncEngineCoordinator.stopSoloSync()
    lastPremiumRefreshAt = nil

    #if DEBUG
    // R32：override picker 拨动会反复翻转 isPremium；DEBUG 下不自动推 UI，
    // 避免调试时被 sheet 骚扰。开发者手动测 lapse UI 走 ProfileDebugSection 的专用按钮。
    if premiumGate.overrideStatus != nil { return }
    #endif

    let expiredAt = premiumGate.latestEntitlementExpiration
    let notice = PremiumLapseNotice(
        entitlementExpiredAt: expiredAt,
        detectedAt: dateProvider.now(),
        dedupKey: lapseDedupKey(expiredAt: expiredAt, detectedAt: dateProvider.now())
    )
    guard !lapseAcknowledgedStore.contains(notice.dedupKey) else {
        premiumLogger.info("paywall.lapse.deduped \(notice.dedupKey)")
        return
    }
    rootPaywallPresentation.requestLapse(notice)
}
```

sheet dismiss（通过 AppRootView 观察 `presenting` 变为 nil）时 AppContext 调 `lapseAcknowledgedStore.insert(notice.dedupKey)`——同一次 lapse 后续冷启动不再弹。

**`LapseAcknowledgedStore` 定义**（R61 修）：

```swift
@MainActor
final class LapseAcknowledgedStore {
    private let defaults: UserDefaults
    private let key = "com.pigdog.Together.premium.lapseAcknowledgedKeys"
    private(set) var keys: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keys = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func contains(_ k: String) -> Bool { keys.contains(k) }
    func insert(_ k: String) {
        guard keys.insert(k).inserted else { return }
        defaults.set(Array(keys), forKey: key)
    }
}
```

持有方：`AppContext.lapseAcknowledgedStore`（init 时创建）。

**`lapseDedupKey` 实现骨架**（R57 修）：

```swift
func lapseDedupKey(expiredAt: Date?, detectedAt: Date) -> String {
    if let d = expiredAt {
        // 精确到秒；RC entitlement.expirationDate 在多次 refresh 间通常稳定
        return "lapse:\(Int(d.timeIntervalSince1970))"
    }
    // 无 expirationDate（从未订阅过 / 缓存丢）→ 按天去重，避免同一天反复弹
    let day = Int(detectedAt.timeIntervalSince1970 / 86_400)
    return "lapse:fallback:\(day)"
}
```

**粒度决策（v8 落定）**：默认 **精确到 expiredAt 秒**；无 expiredAt fallback 按天。挽回机制不依赖反复弹 sheet，依赖 `ProfileProEntryRow` 长期可见。

**ack 策略（v8 落定）**：`AppContext.paywallDidDismiss(kind: .lapse(n))` 任意路径（下滑 / close 按钮 / sheet binding set-nil）统一记 `lapseAcknowledgedStore.insert(n.dedupKey)`——与 Netflix / Notion / Dropbox 行业惯例一致。

**新增 `PremiumGate.latestEntitlementExpiration: Date?`**（R24 修）：

```swift
// PremiumGate 内部新增 private 字段，每次 fetchRC 成功后无条件缓存 snapshot 的 expirationDate
// （不管 isActive；失效订阅 RC 仍保留最近一次 expirationDate，正好就是 lapse UI 需要的）
private var cachedProExpirationDate: Date?

nonisolated(unsafe) var latestEntitlementExpiration: Date? { cachedProExpirationDate }

// 在 safeFetchRC 成功分支追加：
//   if case .success(let snap) = result { cachedProExpirationDate = snap.proExpirationDate }
```

不改 `computeStatus` 合并算法，向后兼容。Phase 2 现有 6 个 `PremiumGateLifecycleTests` 预期不受影响，commit 7 落地后必须跑 Phase 2 全 suite 校验（R34）。

**ProfileDebugSection 新增按钮**（R32 / R52 修）：

```swift
// DEBUG only
Button("🧪 模拟 Pro→Free lapse sheet") {
    appContext.rootPaywallPresentation.requestLapse(
        PremiumLapseNotice.debugSample(now: dateProvider.now())
    )
}

// PremiumLapseNotice 里：
static func debugSample(now: Date) -> Self {
    PremiumLapseNotice(
        entitlementExpiredAt: now.addingTimeInterval(-86_400),   // 假装昨天到期
        detectedAt: now,
        dedupKey: "lapse:debug:\(UUID().uuidString)"             // UUID 保证每次都过 dedup
    )
}
```

此路径 dedupKey 带 UUID → `lapseAcknowledgedStore.contains` 永不命中 → 可反复测。

### 2.6 Offerings 选择：`offerings.current`

只读 `offerings.current`。为 nil 进 `PaywallError.noOfferings`，UI 显示 "付费墙暂时不可用 · 重试" 按钮（R13）。

**前置条件（运营侧）**：RC Dashboard 必须把某个 offering 设为 `current`。列入 § 10 checklist。

### 2.7 购买后 `PremiumGate.refresh()` 串行化

`purchase()` 成功后 `await premiumGate.refresh()`，读 `isPremium`；为 false 进 `.entitlementNotReady` 错误分支（RC 最终一致延迟），提示 "购买已提交，稍后查看 Profile 确认"，关 sheet（避免用户困在 sheet）。

### 2.8 Root Sheet 合并器（R2 / R53 / R56 修）

```swift
@MainActor
@Observable
final class RootPaywallPresentation {
    enum Kind: Identifiable, Equatable {
        case quota(UpsellTrigger)
        case lapse(PremiumLapseNotice)
        var id: String { ... }
    }

    private(set) var presenting: Kind?
    private(set) var queue: [Kind] = []

    func requestTrigger(_ t: UpsellTrigger)   // 去重：相同 trigger 不追加
    func requestLapse(_ n: PremiumLapseNotice) // 插队到 queue 头部（lapse 紧急）
    func dismissCurrent()                      // sheet 关 → 出队下一个
}
```

**优先级规则**（R53 明确）：新请求**从不 preempt 当前 presenting**。差异体现在入队位置：
- `requestTrigger` → 追加到 queue 尾部
- `requestLapse` → 插到 queue **头部**（下次 dismissCurrent 时优先弹出）
- 去重：`presenting == newKind` 或 queue 已含相同 kind 时丢弃

**Profile 主动入口不走合并器**（R56）：保持现有 nav push 到 `ProfileSubscriptionView` 的路径；SubscriptionView Free 态自己嵌 `UpsellContent` 带局部 VM，独立于 sheet 路径。好处：(a) 合并器职责更窄；(b) nav 栈内的付费墙 UX 与 quota/lapse sheet 不同语境分开；(c) 不用为 Profile 场景引入无头 `manual` kind。

AppRootView **唯一** `.sheet(item: Binding(...))` 挂在 root 上：

```swift
.sheet(item: Binding(
    get: { appContext.rootPaywallPresentation.presenting },
    set: { if $0 == nil { appContext.rootPaywallPresentation.dismissCurrent() } }
)) { kind in
    UpsellSheet(
        displayKind: kind.toDisplayKind(),     // Kind.quota(t) → .trigger(t); Kind.lapse(n) → .lapse(n)
        purchasing: appContext.paywallPurchasing,
        gate: appContext.premiumGate,
        onFinished: { _ in appContext.rootPaywallPresentation.dismissCurrent() }
    )
}
```

这样 Quota VM 的 `pendingUpsellTrigger` 变化 / lapse notice 到达 / Profile tap 都走同一条渲染路径，**消除同层双 sheet 问题**。

订阅方式：`ImportantDatesManagementView` / `AppRootView` 不再直接看 `pendingUpsellTrigger`，而是在 AppContext 里对两个 VM 的 `pendingUpsellTrigger` 变化做观察（`onChange` 或初始化时 Observation 订阅），变化为非 nil 时调 `requestTrigger`。

### 2.9 in-flight 保护（R9）

- `UpsellSheet` 读 `viewModel.isInFlight`，绑 `.interactiveDismissDisabled(isInFlight)`
- 右上角 close button 在 `isInFlight` 时置灰 disabled
- 仅 `.purchasing` / `.restoring` 视为 in-flight；`.pendingApproval` 不算（它马上要主动关 sheet）

### 2.10 成功态 UX（R8 / R29 修）

`.succeeded` 进入后：
1. 同步切到成功视图（大图 `checkmark.circle.fill` + 标题 "已解锁 Together Pro" + 副标 "感谢支持，继续使用吧"）
2. 展示 `1.2s`（0.3s fade-in + 0.9s hold）由 `PaywallViewModel.holdThenFinish()` 内部控制；测试 override `paywallSuccessHoldDuration = 0`
3. `onFinished(.purchasedOrRestored)` → 合并器 `dismissCurrent()` 关 sheet
4. **不做 pending-action 重放**：用户要再点一次 "+" 按钮重新创建被拦对象。Session A 副标不承诺"自动继续"；要做重放是 Session B/C 的增强

`.pendingApproval` 无成功视图，直接 finished 关 sheet。Session A 在 **Profile Pro 状态行子标题** 显示 "等待家长审批" 做简单反馈，OSLog 同步打点；正式 banner / toast 样式留 Session B。

### 2.11 合规占位（R10 / R46 修 / v8 落定措辞）

`PaywallLegalFooter` 结构 + Apple 标准模板变量插值版：

```swift
VStack(spacing: 6) {
    Text(legalBodyText(for: selectedPackage))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    HStack(spacing: 12) {
        Link("隐私政策", destination: privacyURL)
        Text("·").foregroundStyle(.tertiary)
        Link("使用条款", destination: termsURL)
    }
}

// UpsellCopy.swift
func legalBodyText(for pkg: PaywallPackage?) -> String {
    guard let p = pkg else {
        return "订阅将自动续费；可在 Apple ID 设置中随时管理或取消订阅。"
    }
    return """
    订阅 \(p.localizedTitle) · \(formatPriceLine(p))
    订阅将自动续费；可在 Apple ID 设置中随时管理或取消订阅，至少在当前周期结束前 24 小时取消。
    """
}
```

**v8 决策**：沿用 Apple 指南 3.1.2(a) 推荐模板（Duolingo / Notion / Bear / Day One 同款）；变量由 VM 的 `selectedPackage` 填。Session A 仅落结构 + 占位 URL（`https://example.com/placeholder`），Session B 部署 `docs/legal/` 为公网 URL 后替换（只改 2 个 `URL(string:)` 常量，不动 layout）。

### 2.12 Free override 下付费墙行为（R58 细化）

Phase 2 DEBUG `overrideStatus` picker 允许强制 `.free`。付费墙可打开（正是要测撞墙路径）；`purchaseSelected()` 走 RC sandbox 也能真买——但 `overrideStatus != nil` 压住 `isPremium`，refresh 后仍返回 false。

**VM 状态判断**（DEBUG only）：

```swift
if outcome == .success {
    await premiumGate.refresh()
    #if DEBUG
    if premiumGate.overrideStatus != nil {
        state = .failed(.debugOverrideMasksPro)   // inline warning "购买成功但 override 在拦，请关 override 验证"
        return
    }
    #endif
    if premiumGate.isPremium { ... .succeeded ... }
    else { state = .failed(.entitlementNotReady) }
}
```

Release build 无 `debugOverrideMasksPro` 分支（`PaywallError` 该 case 也可 `#if DEBUG`）。

**restore 路径同等对称**（v8.1 补）：restore 成功不再做 `isPremium` 严格校验——RC 的 `.success` outcome 已在生产实现里检查了 `entitlement.isActive`，延迟传播不应误导用户。但 **DEBUG override** 分支保持：`restore` 成功 + `overrideStatus != nil` → `state = .failed(.debugOverrideMasksPro)`，开发者反馈一致。

### 2.13 i18n（R18）

Session A 沿用项目现状——中文硬编码，不引入 Localizable.strings。所有文案集中到 `UpsellCopy.swift` 常量，将来 i18n 只需换此一处。

### 2.14 Preview（R14）

每个新 View 文件底部加 `#Preview`，注入 `StubPaywallPurchasing`（静态 3 package 样本 + 无错误）+ `PremiumGate.preview`（新增 convenience factory）。所有 Preview 跑得动，不需要真 RC SDK。

### 2.15 View / VM 生命周期（R37）

- `UpsellSheet` 在合并器 `presenting` 变化时由 SwiftUI `.sheet(item:)` 创建；**每次展示创建新 `PaywallViewModel` 实例**（通过 `@State` + init-time injection）
- VM 构造函数里注入 `purchasing` / `premiumGate` / `onFinished` closure
- sheet 关 → SwiftUI 销毁 `UpsellSheet` → VM 随 `@State` 释放；in-flight Task 被 `Task { }` 结构化取消
- 并发安全：VM 是 `@MainActor`，所有 async 方法都在 main actor 上跑；`Task.sleep` 取消由 `try?` 吞

### 2.16 Kill-App 期间购买（R39）

用户在 `.purchasing` 过程中 kill App：RC SDK 的 purchase transaction 由 StoreKit 持久化；下次冷启动 `PremiumGate.bootstrap()` 自然拿到新 entitlement；付费墙不需要恢复"上次 in-flight 状态"。无需额外代码。

### 2.17 OSLog（R15）

`PaywallViewModel` 持有 `premiumLogger`（复用 Phase 2 的 subsystem），打点：

| 事件 | level | fields |
|---|---|---|
| `paywall.offerings.loaded` | info | offeringID, packageCount |
| `paywall.offerings.failed` | error | errorCode |
| `paywall.purchase.start` | info | packageID |
| `paywall.purchase.succeeded` | info | packageID |
| `paywall.purchase.cancelled` | info | packageID |
| `paywall.purchase.pending` | info | packageID |
| `paywall.purchase.failed` | error | packageID, errorCode |
| `paywall.restore.start / succeeded / failed` | info/error | — |
| `paywall.refresh.postPurchase` | info | isPremium |
| `paywall.refresh.postRestore` | info | isPremium |
| `paywall.lapse.requested` | info | expiredAt, dedupKey |
| `paywall.lapse.deduped` | info | dedupKey |

---

## § 3. UI 规格

### 3.1 `UpsellContent` 主体结构（上到下）

1. Hero（按 `UpsellDisplayKind` 切；`.lapse` 顶部多一行黄色 banner "订阅已到期"；`.generic` 走 fallback hero）
2. Benefits 4 行 + checkmark
3. Packages（`offerings.current.availablePackages`，单选卡片）
4. 主 CTA（loading → ProgressView；disabled 条件 = `selectedPackageID == nil || isInFlight`）
5. Inline error（`.failed` 态时红字 + "重试"）
6. 恢复购买（tertiary 文字按钮；isInFlight 时 disabled）
7. `PaywallLegalFooter`（占位）

### 3.2 `UpsellSheet` 包装（R26 修）

```swift
struct UpsellSheet: View {
    let displayKind: UpsellDisplayKind      // 由调用方把 RootPaywallPresentation.Kind 映射过来
    @State private var viewModel: PaywallViewModel

    init(displayKind: UpsellDisplayKind,
         purchasing: PaywallPurchasingProtocol,
         gate: PremiumGate,
         onFinished: @escaping (PaywallFinishReason) -> Void) {
        self.displayKind = displayKind
        _viewModel = State(initialValue: PaywallViewModel(
            purchasing: purchasing, premiumGate: gate, onFinished: onFinished
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            UpsellContent(displayKind: displayKind, viewModel: viewModel)
            Button { viewModel.requestClose() }
                label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                .disabled(viewModel.isInFlight)
                .padding()
        }
        .interactiveDismissDisabled(viewModel.isInFlight)
        .task { await viewModel.load() }
        .overlay {
            if case .succeeded = viewModel.state { SuccessOverlay() }
        }
    }
}
```

不使用 `NavigationStack`（付费墙无导航需求，NavigationStack 引入额外 bar 高度会与 hero 冲突）。close 按钮 `Image(systemName: "xmark.circle.fill")` 满足 Apple HIG 对 sheet 关闭的最低要求。

### 3.3 错误态

所有非 cancel / pending 错误统一走 `.failed(PaywallError)` inline 卡片，不弹 alert：

| 场景 | UI |
|---|---|
| 用户取消 | state 回 `.ready`，无提示 |
| 网络错误 | inline 红字 + "重试"按钮（→ ready） |
| `entitlementNotReady` | inline "购买已提交，正在同步；请稍后回 Profile 确认" + 关闭按钮 |
| `nothingToRestore` | inline "未找到已购买的订阅；请确认使用购买时的 Apple ID" + 关闭按钮 |
| `noOfferings` | 代替 packages 列表的"付费墙暂时不可用 · 重试" 空态 |
| `debugOverrideMasksPro`（DEBUG only）| inline 紫色 "DEBUG: 购买成功但 override 拦着，请关 override 验证" |
| Ask to Buy pending | 关 sheet + OSLog；RC 自动在后台 observe customerInfo，PremiumGate 下次 refresh 生效；Profile Pro 状态行显示 "等待家长审批" 子标题 |

---

## § 4. 接入现有 3 处占位

### 4.1 `ImportantDatesManagementView`（纪念日配额）

```swift
// 删除整个 .alert(...) 块
// 不挂 .sheet；配额超出由 VM set pendingUpsellTrigger，AppContext 观察层转给 rootPaywallPresentation
```

### 4.2 `AppRootView`（项目配额）

```swift
// 删除现有 .alert(...)
// 唯一 .sheet(item: rootPaywallPresentation.presenting) 见 § 2.8
```

### 4.3 `AppContext.handlePremiumStatusChange`

见 § 2.5 代码。

### 4.4 Profile 入口（R56 修）

保持现有 `NavigationLink` 跳 `ProfileSubscriptionView`。SubscriptionView 内部按 `premiumGate.status` 分支：

```swift
switch appContext.premiumGate.status {
case .free, .unknown:
    UpsellContent(displayKind: .generic, viewModel: makeLocalPaywallViewModel())
        // onFinished(.purchasedOrRestored) → dismiss() pop nav
case .pro, .gracePeriod:
    ProSubscriptionPlaceholder()   // Session B 充实
}
```

`UpsellDisplayKind.generic` → fallback hero（"升级 Together Pro · 解锁全部 Pro 功能"）+ 固定 benefit 顺序。不涉及 `rootPaywallPresentation`。

---

## § 5. View 层触发 + Sheet 合并器（R20 / R21 / R30 修）

不在 AppContext 层手搓 Observation 订阅（过度工程）；用 SwiftUI `.onChange` 原生触发：

### 5.1 Trigger 入 queue（View 层）

```swift
// ImportantDatesManagementView
.onChange(of: viewModel.pendingUpsellTrigger) { _, new in
    if let t = new { appContext.rootPaywallPresentation.requestTrigger(t) }
}

// AppRootView 同样挂在 projectsViewModel 上
.onChange(of: appContext.projectsViewModel.pendingUpsellTrigger) { _, new in
    if let t = new { appContext.rootPaywallPresentation.requestTrigger(t) }
}
```

### 5.2 Sheet 关闭 → 清理（AppContext 统一入口，R51 修）

`RootPaywallPresentation` 不持有 VM / store 引用。View 层观察 `presenting` 变为 nil 时调 AppContext 统一入口：

```swift
// AppRootView
.onChange(of: appContext.rootPaywallPresentation.presenting) { oldKind, newKind in
    guard newKind == nil, let dismissed = oldKind else { return }
    appContext.paywallDidDismiss(kind: dismissed)
}
```

```swift
// AppContext
func paywallDidDismiss(kind: RootPaywallPresentation.Kind) {
    switch kind {
    case .quota(.projectQuota):
        projectsViewModel.dismissUpsell()
    case .quota(.anniversaryQuota):
        importantDatesViewModel.dismissUpsell()
    case .lapse(let notice):
        lapseAcknowledgedStore.insert(notice.dedupKey)
    case .quota(.logbookHistory), .quota(.crossDeviceSync):
        break  // Session B/C 接入 VM 源后补
    }
}
```

`logbookHistory` / `crossDeviceSync` trigger 暂无 VM 源（Session B/C 接入）。Session A 只接纪念日 + 项目两条 quota 线。

---

## § 6. 测试策略

### 6.1 Swift Testing 新增

| 文件 | 覆盖 |
|---|---|
| `PaywallViewModelTests` | 全部 state 转换路径；`.success` 严格读 PremiumGate.isPremium；cancel / pending / noOfferings / network / entitlementNotReady / nothingToRestore 分支；成功后 `onFinished(.purchasedOrRestored)` 被调（`paywallSuccessHoldDuration = 0` override）；in-flight 期间 `isInFlight == true` |
| `UpsellCopyTests` | 每个 trigger 的 hero + benefit 顺序；nil trigger fallback；价格格式化（`PaywallPeriod` → "/月" "/年"）；免费试用徽章文本 |
| `PaywallErrorTests` | RC 错误码（`purchaseCancelledError` / `networkError` / `paymentPendingError` / 未知 code）→ PaywallError case 翻译表 |
| `RootPaywallPresentationTests` | 空态请求 → 立即 presenting；已 presenting 时请求 → 入队；dismiss → 出队；优先级（lapse 插队）；去重（同 trigger 连续请求不重复入队） |
| `PremiumGateRefreshTests`（还债 / R44） | **先审计** `PremiumGateLifecycleTests` 现有 6 个覆盖面；补齐缺口：连续 refresh race 保留最后一次、refresh 期间 logOut 作废、refresh 失败保留上次 status、`latestEntitlementExpiration` 在失败分支不被 overwrite |

**Stub**：`actor StubPaywallPurchasing: PaywallPurchasingProtocol`（R23）——用 actor 避开 `Sendable` class 的 mutable state 问题。提供 offerings 固定样本 + 可配置的 outcome/error 列表；放 `TogetherTests/Stubs/`，同套路 Phase 2 StubRCClient。

### 6.2 Sandbox 真机 smoke runbook

新增 `docs/superpowers/runbooks/phase-3-paywall-smoke.md`，场景：

1. Free override → 建第 4 个纪念日 → sheet 弹 → 选年 → 买成功 → sheet 自动 1.2s 后关 → 再建不拦
2. Free override → 建第 4 个项目 → 同上
3. 购买中途取消 → sheet 不关，state 回 ready
4. 关网 → 买 → inline 错误 → 联网 → 重试通过
5. Free 用户 Profile → 点 Together Pro → nav push ProfileSubscriptionView → 内嵌 UpsellContent（kind == nil fallback hero）
6. 卸载重装 → Profile → 恢复购买 → 恢复 Pro
7a. **DEBUG 模拟 lapse**：ProfileDebugSection → 点 "模拟 Pro→Free lapse sheet" → sheet 弹 → 关 → 再点 → 再弹（绕 dedup）
7b. **override 拨动不骚扰**：Pro override → 切 Free override → lapse sheet **不自动弹**（但 stopSoloSync 数据面生效，OSLog 有 `lapsed at runtime`）；再切回 Pro override → 切 Free → 仍不弹
8. `offerings.current == nil` 模拟（RC Dashboard 把 current 撤下）→ 付费墙空态 + 重试
9. Ask to Buy（Sandbox 家庭账号）→ 买 → sheet 关 → Profile 显示"等待家长审批"→ 审批后自动解锁
10. in-flight 下尝试下滑关 sheet → 被阻止

### 6.3 不做

- Sandbox 订阅续期（1w=3min / 1y=1h）→ Session C
- 深度 a11y / Dynamic Type 极限 → Session C

---

## § 7. 风险 & Mitigation

| 风险 | Mitigation |
|---|---|
| RC Dashboard 未 mark current offering | `noOfferings` 空态可见；运营 checklist 列为上线前必项（§ 10） |
| `purchase()` success 但 entitlement propagate 延迟 | `entitlementNotReady` 错误分支 + 关 sheet + 用户看 Profile |
| 同层多 sheet 冲突 | § 2.8 合并器：整个 App 唯一 `.sheet` 挂点在 AppRootView |
| lapse sheet 反复弹扰民 | § 2.5 dedupKey + UserDefaults 持久化 |
| in-flight 被下滑关 sheet 导致 UI 丢进度 | § 2.9 `interactiveDismissDisabled` + close 按钮禁用 |
| DEBUG override 下买了但 UI 看不出来 | § 2.12 DEBUG-only warning |
| Ask to Buy 用户以为买失败 | § 3.3 关 sheet + Profile 子标题提示 |
| Free override + RC sandbox 可能混乱开发测试 | smoke runbook 明确 override / 真 RC 两条路径 |
| Phase 2 follow-up #2 `staleBootstrapResultIsDiscarded` CI flaky | Session A 不解决此测试本身，只保证新增 `PremiumGateRefreshTests` 不引入 sleep 依赖（用 AsyncStream 信号） |

---

## § 8. 部署 / 运营前置条件

Session A 代码合并前**不**要求下列，但 Sandbox 真机 smoke 跑前需要：

- RC Dashboard → Offerings 至少 1 个 offering + mark current
- RC Dashboard → 该 offering 含至少 1 个 package（月/年/终身都行）
- RC Dashboard → Entitlement `pro` attach 到所有 package
- ASC → Product ID 与 RC Dashboard 一致（或先在 RC test store 挂 sandbox 条目跑通）
- Sandbox Apple ID 在真机登录（Settings → App Store → Sandbox Account）

Release 发版前额外：

- RC Dashboard → Apps → iOS App → API Key 复制 → 替换 `RevenueCatConfig.publicSDKKey` 的 production 占位
- 运行时 `assertProductionKeyConfigured()` 守卫此项

---

## § 9. Accessibility 基线（Session A 落地，Session C 审计）

- `UpsellContent` 整体 `accessibilityScrollAction`（VoiceOver 滚动）
- 每张 `PaywallPackageCard`：`accessibilityLabel` "年度套餐，¥198/年，含 7 天免费试用"；`accessibilityAddTraits(.isButton)`；选中态 `accessibilityAddTraits(.isSelected)`
- 主 CTA：`accessibilityLabel("开始免费试用并订阅")` / `accessibilityHint("订阅 Together Pro 年度套餐")`
- close button：`accessibilityLabel("关闭付费墙")`
- 成功 checkmark：`accessibilityLabel("已解锁 Together Pro")`，VoiceOver 立刻读
- 合规 footer 的 Link：SwiftUI `Link` 原生 a11y 可用
- Dynamic Type：使用 `AppTheme.typography.textStyle(...)`（跟随系统 scale），不用硬编码 `sized(N)`

深度审计（VoiceOver 全流程 / RTL / 极限 Dynamic Type）留 Session C。

---

## § 10. 决策摘要（v8 全部落定）

| # | 议题 | 决策 | 理由 |
|---|---|---|---|
| 1 | RC Dashboard 资产 vs 代码合并时序 | **代码先合**，资产并行准备 | Phase 2 已有 sandbox key + release key 守卫；行业（Netflix / Notion）均解耦 |
| 2 | lapse dedupKey 粒度 + ack 策略 | **精确到 expiredAt 秒**；**任意方式关闭都记 ack** | 年度订阅低频 lapse；反复弹负向收益；挽回走 Profile 长期入口 |
| 3 | Ask to Buy "等待家长审批" 反馈 | **Session A 做**，Profile Pro 状态行加 `.pendingApproval` 子标题态 | 低成本高差评防御；`ProSubscriptionStatus` 多态已支持 |
| 4 | Pro→Free 数据面 vs UI 层 | **Session A 仅加 UI**，不动 Phase 2 已跑通的 `stopSoloSync` | 严格 scope 控制，避免回归 |
| 5 | 合规 footer 最低措辞 | **Apple 标准模板 + 变量插值**（见 § 2.11 `legalBodyText(for:)`） | 行业通用；Session B 只换 2 个 URL 常量 |

技术决策（协议分层、状态机、合并器、VM 生命周期、清理入口、dedup 持久化、display kind、DEBUG override 分支）在 v1–v7 自 review 中已全部收敛。

本 spec 准备就绪，可进入 writing-plans 阶段拆 task 级 TDD plan。

---

## § 11. Commit 计划（R45 拆 commit 9）

| # | Commit | 依赖 |
|---|---|---|
| 1 | `feat(paywall): add PaywallPurchasingProtocol + models + PaywallError` | — |
| 2 | `feat(paywall): add RevenueCatPaywallPurchasing production impl` | 1 |
| 3 | `feat(paywall): add UpsellCopy + tests (format price / trial)` | 1 |
| 4 | `feat(paywall): add PaywallViewModel + tests (stub purchasing actor)` | 1, 3 |
| 5 | `feat(paywall): add RootPaywallPresentation + tests` | — |
| 6 | `feat(paywall): add UpsellContent + UpsellSheet + PaywallPackageCard + PaywallLegalFooter + previews` | 3, 4 |
| 7 | `feat(premium): expose PremiumGate.latestEntitlementExpiration` | — |
| 8 | `test(premium): audit + extend PremiumGateRefreshTests (Phase 2 debt)` | 7 |
| 9a | `feat(paywall): mount rootPaywallPresentation + single .sheet on AppRootView` | 5, 6 |
| 9b | `feat(paywall): replace quota alerts with paywall sheet (Anniversaries + Projects)` | 9a |
| 9c | `feat(paywall): wire Profile manual entry` | 9a |
| 9d | `feat(paywall): surface Pro→Free lapse + DEBUG simulator button + dedup` | 7, 9a |
| 10 | `docs(paywall): phase-3-session-a smoke runbook` | 9d |

13 个 commit（1-8 + 9a-9d + 10）。每个独立通过测试后再下一步；Phase 2 全 suite 在 commit 7 后和 9d 后各跑一次回归。

---

## § 12. 自 review 记录

- **v1**: 初稿
- **v1 → v2**: 打掉 R1–R19（硬错误 2、内部矛盾 4、UX 打脸 3、遗漏 10）
- **v2 → v3**: 打掉 R20–R47 中 16 条（实现可行性：Observation 订阅改 View onChange、Stub 用 actor、NavigationStack 去掉；机制具体化：latestEntitlementExpiration / VM 生命周期 / 1.2s 计时；调试体验：override 不推 lapse + ProfileDebugSection 按钮；边界：Kill-App；commit 粒度：9 拆 4；测试策略：审计 + 补齐）
- **v3 → v4**: 打掉 R48–R58 共 11 条（笔误：requestClose；状态机：failed 路径统一 inline，PaywallFinishReason 精简到 3；清理入口：AppContext.paywallDidDismiss 统一；DEBUG：PremiumLapseNotice.debugSample UUID dedup；合并器：lapse 插队不 preempt、删 manual kind；Profile 入口：保留 nav push + UpsellContent kind:nil；生产实现：RevenueCatPaywallPurchasing 缓存 Package；DEBUG override 购买成功 warning）
- **v4 → v5**: 打掉 R59–R61 共 3 条（succeeded hold 期间的双 finish race：isInFlight 包含 succeeded + `finishOnce` 闸门；RevenueCatPaywallPurchasing.restore 逻辑骨架；LapseAcknowledgedStore 持久化类定义）
- **v5 → v6**: 打掉 R62 共 1 条（UpsellContent 的 kind 类型跨语境不兼容 → 新增 `UpsellDisplayKind` 作为 View 层统一契约）
- **v6 → v7**: 打掉 R63 共 1 条（v6 引入 UpsellDisplayKind 的 ripple：§ 3.1 / 3.2 / 4.4 / 2.8 合并器示例里多处旧 `kind:` 参数统一到 UpsellDisplayKind + `Kind.toDisplayKind()` 映射）
- **v7 → v8**: § 10 剩余 5 条运营 / 产品决策按行业最佳实践 + Together 契合度逐条决策落定；ripple 到 § 2.5（lapse 粒度 + ack 策略）与 § 2.11（Apple 标准模板 legalBodyText）
- **v8 收敛判定**：
  - 每轮自 review 问题数：19 → 16 → 11 → 3 → 1 → 1 → 0
  - 5 条非技术决策已落地，无悬挂项
  - 可进入 writing-plans 阶段
