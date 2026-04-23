# Phase 3 · Session A — 付费墙真机 Smoke Runbook

- **Date**: 2026-04-24
- **Tag**: `phase-3-session-a`（Task 10 后打）
- **Base**: main `b758aa4` 及之后
- **用途**: sandbox 真机验证 Session A 落地功能；Apple 审核 / TestFlight 前的最后一道自测

---

## § 0. 前置准备

### 运营侧

- [ ] RC Dashboard → Offerings 至少 1 个 offering + **mark current**
- [ ] 该 offering 含 ≥ 1 个 package（月/年/终身均可）
- [ ] Entitlement `pro` attach 到所有 package
- [ ] ASC Product ID 与 RC Dashboard 一致（或 RC test store 可代替）

### 测试设备

- [ ] 真机 iPhone + iPad（至少一台，两台更好）
- [ ] Settings → App Store → Sandbox Account 登录 Sandbox Apple ID
- [ ] 设备时间未手动调过（StoreKit 对时间扰动敏感）
- [ ] 连上 Console.app，subsystem 过滤 `com.pigdog.Together` category `Premium`

### Build 准备

- DEBUG build 用 `test_vSgWSmgUqnLiCKZvjDshWoFySiT` sandbox key（`RevenueCatConfig.swift`）
- Release build **不要** 跑本 runbook：production key 未替换前 `assertProductionKeyConfigured()` 会 precondition 失败

---

## § 1. 核心路径

### 场景 1 — 纪念日配额 → 买成功

1. ProfileDebugSection → Override 选 **Free** → 立即重新计算
2. 进"纪念日" → 连续新建 5 个
3. 点新建第 6 个 → **UpsellSheet 弹出**，hero "记录所有重要的日子 · 免费版最多 5 个纪念日"
4. benefits 首位 "无限纪念日"
5. 选年度套餐 → CTA "开始前 7 天免费 · ¥198 / 年"
6. 点 CTA → Sandbox 购买弹窗 → **Subscribe**
7. 预期：progress spinner → 1.2s checkmark + "已解锁 Together Pro" → sheet 自动关
8. 回到纪念日列表 → 再点 + → 不拦（Override 要切回 None 才生效；见 7a/7b）

OSLog 应出现：
- `paywall.offerings.loaded`
- `paywall.purchase.start packageID=...`
- `paywall.purchase.succeeded`
- `paywall.refresh.postPurchase isPremium=true`（override=None 时）

### 场景 2 — 项目配额

同场景 1，触发路径：Free Override → 项目页 → 连续新建 3 个 → 第 4 个弹 sheet
hero "让每个项目都有位置"，benefits 首位 "无限项目"。

### 场景 3 — 购买中途取消

1. Free override → 触发 sheet（场景 1 步骤 1-3）
2. 点 CTA → 系统弹窗 → **Cancel**
3. 预期：sheet 不关；state 回 ready；选中 package 保持；无 error 提示

### 场景 4 — 网络错误

1. 关飞行模式 / wifi → sheet 打开；已 loaded offerings 可展示
2. 点 CTA → 预期 inline 红字 "网络连接异常 · 请检查网络后重试"
3. 点 "重试" → 再次调 load；或 "关闭" 回 ready
4. 恢复网络 → 点 CTA → 成功

### 场景 5 — Profile 主动入口

1. Free override → Profile → 点 Together Pro 行
2. **nav push** 到 ProfileSubscriptionView（不是 sheet）
3. 页面显示 UpsellContent `.generic` hero："升级 Together Pro · 解锁全部 Pro 功能"
4. Benefits 固定顺序
5. 购买流同场景 1；成功后 pop nav 回 Profile

### 场景 6 — 卸载重装 → 恢复购买

**前置**：需先通过场景 1 或 5 完成一次 Sandbox 购买。

1. 卸载 App → 重装（或从 Xcode Clean Build + Run）
2. 登录 Supabase 账号 + Sandbox Apple ID 仍为同一个
3. 触发付费墙（Free override 下任意路径）→ 点 **恢复购买**
4. 预期：1.2s checkmark → sheet 关 → Pro 激活

### 场景 7a — DEBUG 模拟 lapse sheet

1. ProfileDebugSection → Override **任何状态**（包括 None）
2. 点 **🧪 模拟 Pro → Free lapse sheet**
3. 预期：立即弹 UpsellSheet，顶部黄色 banner "订阅已到期 · 升级恢复同步"
4. 关闭（下滑 / 点 ×）→ sheet 消失
5. **再点一次按钮 → 再弹**（dedupKey 带 UUID 绕 store）

### 场景 7b — override 驱动 Pro→Free 不骚扰

1. Override **Pro (订阅)** → 立即重新计算 → 状态 Pro
2. Override **Free** → 立即重新计算 → 状态 Free
3. 预期：Console 看到 `Premium lapsed at runtime — stopping solo sync`
4. 预期：**无** `paywall.lapse.requested`（被 override 分支 skip）
5. 预期：**无** sheet 弹出；数据面 CKSync 已停

### 场景 8 — noOfferings 空态

需 RC Dashboard 侧操作：暂时把 current offering 的 flag 取消。

1. Free override → 触发 sheet
2. 预期：替代 packages 列表显示 "付费墙暂时不可用 · 请稍后再试" + **重试** 按钮
3. RC Dashboard 恢复 current → 点重试 → 正常加载

### 场景 9 — Ask to Buy（选做，需 Sandbox 家庭账号）

1. Sandbox 家庭账号中把测试账号标记为儿童 + 开启 Ask to Buy
2. Free override → 触发 sheet → 选 package → 点 CTA
3. 系统弹出 "请家长批准" 弹窗 → OK
4. 预期：sheet 关闭（无 alert，无 error）
5. Profile Pro 行子标题显示 "等待家长审批 · 批准后自动生效"
6. 家长设备批准后再启动 App → customerInfo 更新 → PremiumGate refresh → Pro 激活

### 场景 10 — In-flight 防下滑

1. 触发 sheet → 选 package → 点 CTA
2. 点击过程中立即下滑 sheet
3. 预期：sheet **不能关闭**（interactiveDismissDisabled），close `×` 按钮灰色禁用
4. 购买完成后 sheet 正常关闭

---

## § 2. OSLog Checklist（Console.app）

subsystem: `com.pigdog.Together` / category: `Premium`

预期事件（按场景触发顺序）：

- [ ] `paywall.offerings.loaded offeringID=... count=N`
- [ ] `paywall.offerings.failed ...`（场景 8）
- [ ] `paywall.purchase.start packageID=...`
- [ ] `paywall.purchase.succeeded packageID=...`
- [ ] `paywall.purchase.cancelled packageID=...`（场景 3）
- [ ] `paywall.purchase.pending packageID=...`（场景 9）
- [ ] `paywall.purchase.failed packageID=... error=...`（场景 4）
- [ ] `paywall.refresh.postPurchase isPremium=...`
- [ ] `paywall.refresh.postRestore isPremium=...`
- [ ] `paywall.restore.succeeded`
- [ ] `paywall.restore.nothingToRestore`
- [ ] `paywall.lapse.requested dedupKey=...`（场景 7a）
- [ ] `paywall.lapse.deduped dedupKey=...`（重复场景 7a，先点 × 再点按钮）
- [ ] `paywall.lapse.skippedForOverride`（场景 7b）
- [ ] `paywall.lapse.acknowledged dedupKey=...`（sheet 关闭后）

---

## § 3. 已知不在 Session A Scope（留 B/C）

- 订阅管理（续费日期 / "在 App Store 管理订阅" 链接）— Session B
- Grace Period 专用 UI（Logbook 顶部横幅）— Session B
- 真实 Privacy / ToS URL（当前指 example.com/placeholder）— Session B
- VoiceOver / Dynamic Type 深度审计 — Session C
- StoreKit Configuration `.storekit` 本地测试 — Session C
- Sentry / Crashlytics — Session C
- 新设备首次打开的 `.crossDeviceSync` 一次性引导 — Session B / C

---

## § 4. 排障

| 症状 | 可能原因 | 处置 |
|---|---|---|
| Sheet 空白（"付费墙暂时不可用"） | RC Dashboard 未 mark current offering | Dashboard → Offerings → 设 current |
| 点 CTA 后 inline "出错了" | RC SDK 未知错误 | 看 OSLog `paywall.purchase.failed` 取 code；常见是 sandbox account 未登录 |
| 买完 UpsellSheet 不关 | 可能 onFinished 未触发合并器 dismiss | 检查 AppRootView sheet binding + `.onChange(of: presenting)` |
| "购买已提交，正在同步" inline | RC 最终一致延迟 `entitlementNotReady` | 关 sheet 回 Profile 观察 `paywall.refresh.postPurchase` isPremium 变化 |
| Override 切换后 lapse sheet 反复弹 | override 分支 skip 失效 | 检查 `container.premiumGate.overrideStatus != nil` 判断 |
| dedup 未生效（sheet 反复弹） | `LapseAcknowledgedStore` 未 insert | 检查 `AppContext.paywallDidDismiss(kind: .lapse)` 路径 |

---

## § 5. 完成标记

- [ ] 场景 1-8 + 10 全部 PASS
- [ ] 场景 9 PASS 或标记 "Session B/C 验证"（无家庭账号时）
- [ ] OSLog § 2 中至少 10/15 事件出现过（覆盖跑过的场景）
- [ ] Phase 2 功能未回归（pair / sync / solo sync / Logbook 等）
- [ ] 真机 iPhone + iPad 同 Sandbox Apple ID 均 Pass

全部勾选后打 tag：

```bash
git tag phase-3-session-a
git push origin phase-3-session-a
```
