# Together Pro 全量上线 Roadmap

> **For agentic workers:** 这是一份 **Roadmap 级** 推进计划，不是代码级 TDD plan。源 spec 是纯产品决策，Phase 2/3 作为独立子系统需要各自走 brainstorming → spec → plan → code 循环。本 Roadmap 负责统筹排序、识别并行/串行依赖、列出外部非代码待办。执行方式：用户在准备好启动某个 Track 时，对应调用 `superpowers-brainstorming` 或 `superpowers-writing-plans` skill，**不要直接用 subagent-driven-development 或 executing-plans 跑本 Roadmap**。

**Goal:** 从"产品决策 spec Final"推进到"Together Pro 在 App Store 正式开售"，把所有中间子工作分解、排序、标注依赖、识别关键路径。

**Architecture:** 4 条工作流 —— 一条关键路径 (Track A)，一条紧跟路径 (Track B)，一条可并行设计 (Track C)，一条外部运营 (Track D)。每条各自产出独立 spec + plan + 执行。

**Tech Stack Context:**
- 现有：SwiftUI + SwiftData + CloudKit + `CKSyncEngine` + Supabase + `ProfileSubscriptionView` 占位 UI
- 待引入：RevenueCat SDK、StoreKit 2 Subscription Products、Supabase `premium_grants` 表 + Edge Function
- 外部服务：Apple Developer Portal (IAP 配置)、RevenueCat Dashboard、Supabase Dashboard、App Store Connect

---

## 源 Spec

`docs/superpowers/specs/2026-04-22-premium-tier-split-design.md` (Final, rev 3)

14 条核心决策全部在该 spec 的"决策溯源"章节索引。本 Roadmap 的所有 Track 都可以回溯到其中具体章节。

---

## Track A — Phase 2 基础设施（关键路径）

**为什么是关键路径**：
- Phase 3 付费墙 UI 依赖 `PremiumGate` API 存在
- Track D2 IAP 产品配置需要 entitlement key 命名统一
- Track D4 老用户 grandfather 执行需要 `premium_grants` 表存在

**待产出 spec**：`docs/superpowers/specs/<YYYY-MM-DD>-premium-infrastructure-design.md`

### Task A1: Phase 2 基础设施 brainstorming

**依赖前置**：本产品 spec 已 Final ✅

- [ ] **Step 1: 启动 brainstorming skill**

  ```
  运行：superpowers-brainstorming
  话题：Premium Infrastructure — RevenueCat + Supabase + PremiumGate
  ```

- [ ] **Step 2: brainstorming 必讨论的 8 个锚点**

  （直接对应产品 spec 相关章节，不要漏）

  1. `premium_grants` 表结构 — 字段：`user_id` / `category` (`developer` / `friend` / `grandfather` / `testflight`) / `granted_at` / `expires_at` (nullable) / `reason`
  2. Edge Function 逻辑 — 合并 StoreKit 订阅收据 + `premium_grants` 表 → 返回 `isPremium` + `entitlementSource`
  3. 客户端 `PremiumGate` API 形态 — `EnvironmentValue` vs `@Observable` 单例 vs Protocol + Mock
  4. RevenueCat SDK 接入点 — initialization 位置、entitlement key 命名（建议 `pro`）、offerings 配置模式
  5. **`createdByUserID` 字段迁移** — SwiftData schema version bump + CloudKit record type migration + 回填脚本（对应源 spec § 2.5.1 "数据迁移原则"）
  6. 各模块门禁改造点清单 — `SyncEngineCoordinator.startSoloSync()` / `ImportantDatesViewModel` 新建路径 / `ProjectsViewModel` 新建路径 / `CompletedHistoryViewModel` 窗口过滤
  7. 白名单运维流程 — 开发者如何通过 Supabase Dashboard insert、亲友如何被批准（操作手册写哪里）
  8. 离线创建 + 同步冲突处理 — 对应源 spec § 2.5.6 "仅客户端执行"原则

- [ ] **Step 3: 等 brainstorming 产出 spec，用户批准后进入 A2**

  产出文件：`docs/superpowers/specs/<YYYY-MM-DD>-premium-infrastructure-design.md`

### Task A2: Phase 2 基础设施 writing-plans

**依赖前置**：Task A1 输出的 spec 已 Final

- [ ] **Step 1: 启动 writing-plans skill**

  ```
  运行：superpowers-writing-plans
  输入：刚完成的 premium-infrastructure-design.md
  ```

- [ ] **Step 2: 预计产出的代码级 plan 会覆盖**

  - RevenueCat SDK 加依赖 + init 代码（TDD）
  - Supabase migration SQL（`premium_grants` 表）
  - Edge Function TS 代码
  - 客户端 `PremiumGate` 实现（TDD）
  - 4 个模块门禁改造（每个都要 TDD）
  - `createdByUserID` 迁移脚本 + schema bump

### Task A3: Phase 2 实现

**依赖前置**：Task A2 plan 已产出

- [ ] **Step 1: 按 Track A 的 code plan 启动实现**

  推荐方式：`superpowers-subagent-driven-development`（逐任务独立 subagent + 两阶段 review）

- [ ] **Step 2: 每完成一个模块跑 build + smoke test**

  ```bash
  xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' build
  ```

- [ ] **Step 3: 全部完成后 4 类身份回归测试**

  - 开发者账号 → `isPremium = true`（category = `developer`）
  - 亲友白名单账号 → `isPremium = true`（category = `friend`）
  - 老用户账号 → `isPremium = true`（category = `grandfather`）
  - 全新普通账号 → `isPremium = false`，触发配额限制

---

## Track B — Phase 3 付费墙 UI（紧跟 Track A）

**依赖前置**：
- brainstorming 可在 Task A1 产出 `PremiumGate` API 草案后启动（不必等代码落地）
- 实际代码实现需等 Task A3 Phase 2 落地（或 A2 plan 已定死 API）

**待产出 spec**：`docs/superpowers/specs/<YYYY-MM-DD>-paywall-ui-design.md`

### Task B1: Phase 3 付费墙 UI brainstorming

**可与 Task A1 部分并行**（A1 讨论完 PremiumGate API 部分后即可启动 B1）

- [ ] **Step 1: 启动 brainstorming skill**

  ```
  运行：superpowers-brainstorming
  话题：Paywall UI & App Store Compliance
  ```

- [ ] **Step 2: brainstorming 必讨论的 6 个锚点**

  1. 4 个触发场景的视觉呈现（对应源 spec § 3 表格）：
     - 新建第 6 个纪念日 → modal sheet
     - 新建第 4 个项目 → modal sheet
     - Logbook 滚到 31 天前 → inline card
     - 新设备首次打开且本机无数据 → modal sheet
  2. Profile 常驻入口 — 当前已有 `ProfileProEntryRow.swift`，需根据真实状态（free / trial / active / grandfather）动态切换
  3. 付费墙主视图 — 是重写 `ProfileSubscriptionView.swift`（当前是占位 UI）还是新建，视觉规范怎么定
  4. Apple 3.1.1 / 3.1.2 合规六件套：ToS 链接 · Privacy 链接 · Restore Purchases 按钮 · 可见 dismiss · 价格透明 · auto-renew 条款
  5. 降级宽限期的横幅 UI（对应源 spec § 5.2 "14 天 Logbook 宽限"）
  6. 沾光模式的文案（对应源 spec § 2.5.5 "升级 Pro 后，你的私人日程和清单也将同步到你的所有设备"）

- [ ] **Step 3: 产出 spec**

  `docs/superpowers/specs/<YYYY-MM-DD>-paywall-ui-design.md`

### Task B2: Phase 3 writing-plans

**依赖前置**：Task B1 spec Final + Task A2 plan 已定死 `PremiumGate` API

- [ ] **Step 1: 启动 writing-plans skill**

  ```
  运行：superpowers-writing-plans
  输入：paywall-ui-design.md
  ```

- [ ] **Step 2: 预计产出的代码级 plan 会覆盖**

  - 付费墙 SwiftUI 主视图（TDD with Previews）
  - 4 个触发点集成（每个场景都要 UI test）
  - 合规文案集成 + 本地化
  - `ProfileSubscriptionView.swift` 重写（替换当前占位）
  - `ProSubscriptionStatus` enum 扩展（新增 grandfather / testflight 展示形态）

### Task B3: Phase 3 实现

**依赖前置**：Task B2 plan 已产出 + Task A3 Phase 2 基础设施已完成

- [ ] **Step 1: 按 plan 实现**

  推荐 `superpowers-subagent-driven-development`

- [ ] **Step 2: Apple 合规六件套自查清单**

  - [ ] 付费墙有明确的 `[X]` dismiss 按钮（非隐藏）
  - [ ] 价格显示清晰（含币种、周期、自动续订文案）
  - [ ] ToS 链接可点击，指向真实可访问 URL
  - [ ] Privacy Policy 链接可点击，指向真实可访问 URL
  - [ ] Restore Purchases 按钮存在且可工作
  - [ ] 如有免费试用，明确写 "X 天免费，随后 ¥Y/年自动续订"

---

## Track C — 定价 spec（可独立并行）

**不依赖 Track A/B 代码**，但 IAP 产品 ID 配置（Track D2）和付费墙 UI 文案（Track B）会用到它。

**待产出 spec**：`docs/superpowers/specs/<YYYY-MM-DD>-pricing-strategy-design.md`

### Task C1: 定价 brainstorming

**建议时机**：和 Task A1 并行，或 Task A1 完成后立即启动

- [ ] **Step 1: 启动 brainstorming skill**

  ```
  运行：superpowers-brainstorming
  话题：Pricing Strategy
  ```

- [ ] **Step 2: brainstorming 必讨论的 6 个锚点**

  1. 三档价格具体数字（我之前的建议：¥18/月、¥98/年、¥268 终身，需用户拍板）
  2. 免费试用策略（7 天 trial on yearly 是建议）
  3. 国际定价 tier 映射（依赖 Apple 价格模板）
  4. 节日促销机制（情人节 / 七夕 / 双 11 / 年终，StoreKit 2 Introductory Offers）
  5. StoreKit 2 Subscription Group 结构（月度 + 年度同组，终身单独）
  6. 二次确认："一人订阅情侣受益"产品 spec 已定 1.0 不做，是否坚持

- [ ] **Step 3: 产出 spec**

  `docs/superpowers/specs/<YYYY-MM-DD>-pricing-strategy-design.md`

### Task C2: 定价不需要单独 writing-plans

**理由**：定价是**配置**工作而非代码工作。IAP 产品在 App Store Connect 配置（Track D2），价格数字在付费墙 UI 集成（Track B2 plan 里自然覆盖）。

- [ ] **Step 1: Task C1 spec Final 后跳过 writing-plans，直接合并进 Track B2 + Track D2**

---

## Track D — 外部 / 运营工作（非代码）

每一项不依赖代码，可随时启动。但某些必须在 App Store 送审前完成。

### Task D1: RevenueCat 账号与 Project 配置

**时机**：**越早越好**，不用等任何 Track，本周就可以做

- [ ] **Step 1: 注册 RevenueCat 账号**（免费档 10k MTR 以下不收费）
- [ ] **Step 2: Dashboard 创建 Project = "Together"**
- [ ] **Step 3: 连接 Apple App Store**（需要从 Apple Developer Portal 生成 P8 Key）
- [ ] **Step 4: 创建 Entitlement key = `pro`**
- [ ] **Step 5: 暂缓 Offerings 和 Products 配置**（等 Track C 定价 Final、Track D2 IAP 产品创建完毕再做）

### Task D2: Apple Developer IAP 产品配置

**依赖前置**：Track C 定价 spec Final

- [ ] **Step 1: App Store Connect 创建 3 个订阅产品**

  - `together_pro_monthly` 月度 auto-renewable subscription
  - `together_pro_yearly` 年度 auto-renewable subscription（加 7 天 introductory offer）
  - `together_pro_lifetime` 终身 non-consumable

- [ ] **Step 2: 把 monthly / yearly 放入同一个 Subscription Group**
- [ ] **Step 3: RevenueCat Dashboard 把 3 个产品 Link 到 `pro` entitlement**
- [ ] **Step 4: 配置 RevenueCat Offerings**（Default offering = 3 packages）

### Task D3: ToS 与隐私政策页面托管

**依赖前置**：无，可立即启动

- [ ] **Step 1: 起草 Terms of Service 文本**（至少覆盖：订阅条款、自动续订、退款政策、服务可用性）
- [ ] **Step 2: 起草 Privacy Policy 文本**（明确：订阅状态数据、白名单机制、CloudKit 数据去向、Supabase 数据去向、Apple Sign in With Apple 隐私承诺）
- [ ] **Step 3: 选择托管方案**

  候选：自建域名（最专业）/ GitHub Pages（免费且 Apple 接受）/ Notion 公开页（最简单但不够正式）

- [ ] **Step 4: 托管并记录 URL 到 `docs/` 文档**（Track B 付费墙 UI 会读这两个 URL）

### Task D4: 老用户 grandfather 批量 insert 流程

**依赖前置**：Task A3 Phase 2 代码落地 + Task D3 公告内容准备好

- [ ] **Step 1: Supabase `auth.users` 表完整备份**

  ```
  通过 Supabase Dashboard SQL Editor 导出 CSV，或 pg_dump 命令
  ```

- [ ] **Step 2: App 内投放"老用户永久会员"通知 banner**
- [ ] **Step 3: 社区 / 公众号 / 个人社媒发布公告**

  文案建议："感谢一路陪伴。老用户永久免费享有 Together Pro 全部功能。"

- [ ] **Step 4: 执行批量 insert 到 `premium_grants` 表**

  ```sql
  INSERT INTO premium_grants (user_id, category, expires_at, reason)
  SELECT id, 'grandfather', NULL, 'pro-launch-grandfather-2026-04-XX'
  FROM auth.users
  WHERE created_at < '<Pro 发版日期>';
  ```

- [ ] **Step 5: 抽检 5 个老用户账号**（随机选择，登录后确认 `isPremium = true` 且超额纪念日/项目可见）

### Task D5: TestFlight 测试员管理

**依赖前置**：Track A + Track B 代码全部落地

- [ ] **Step 1: 拉 TestFlight 邀请列表**，指定 20-50 人作为外测

  建议：至少包含 **5 对情侣**（配对场景测试） + 5 个单身用户 + 5 个多设备用户

- [ ] **Step 2: 告知测试员免费 Pro 期限**："TestFlight 期间 + 正式发布后 3 个月"
- [ ] **Step 3: Edge Function 自动识别 TestFlight Apple ID**

  （A1 brainstorming 需明确 Apple ID 到 Supabase user_id 的映射方法；通常走 Sign in with Apple 注册）

- [ ] **Step 4: TestFlight 跑 2-4 周**，每周收集反馈、记录 bug
- [ ] **Step 5: 外测数据达标后进入 App Store 正式送审**

---

## 推荐的时间顺序

```
Week 0  ─┬─ 本产品 spec Final ✅（当前位置）
        ├─ Track D1 RevenueCat 账号注册（最早启动）
        └─ Track D3 ToS / Privacy 文本起草

Week 1  ─┬─ Track A1 Phase 2 infra brainstorming
        ├─ Track C1 定价 brainstorming（并行）
        └─ Track D3 ToS / Privacy 托管上线

Week 2  ─┬─ Track A2 Phase 2 writing-plans
        ├─ Track B1 Phase 3 paywall brainstorming（参考 A1 的 PremiumGate 草案）
        ├─ Track C1 定价 spec Final
        └─ Track D2 App Store Connect IAP 配置（定价 Final 后）

Week 3-4 ─ Track A3 Phase 2 代码实现
        └─ Track B2 Phase 3 writing-plans（并行）

Week 5  ─┬─ Track B3 Phase 3 代码实现
        └─ Track D4 老用户 grandfather 批量 insert（Phase 2 落地后）

Week 6  ─ 内测（自己 + 2-3 位亲友）
Week 7  ─ Track D5 TestFlight 外测开启
Week 8+ ─ App Store 送审 + 正式上架
```

**总时长估算**：8 周左右（假设一人全职，不算审核等待时间）

**审核等待**：Apple IAP 审核 1-3 天，首次订阅配置 + App 送审合计 3-7 天

---

## 关键依赖图

```
本 spec (Final)
   │
   ├───────→ Track A1 → A2 → A3 ───────┐
   │            │                      │
   │            └─→ PremiumGate 草案 ───┼─→ Track B1 → B2 → B3 ──→ 送审上架
   │                                   │
   ├───────→ Track C1 ──┬──→ Track D2 ─┘
   │                    │
   ├───────→ Track D1 ──┤
   │                    │
   └───────→ Track D3 ──┘

   Track D4 老用户 grandfather：Track A3 完成后立即执行
   Track D5 TestFlight 测试：Track B3 完成后执行
```

---

## 关键风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| RevenueCat 学习曲线超预期 | Track A 延期 | 提早做 D1 账号 + Demo 试装，不要等 A1 brainstorming |
| Apple IAP 审核被拒（付费墙不合规） | 上架阻塞 | Phase 3 spec 严守 3.1.1 / 3.1.2，付费墙必带六件套 |
| 老用户 grandfather 批量 insert 失败 | 投诉 + 差评 | D4 前 Supabase 完整备份 + 分批执行 + 人工抽检 |
| CloudKit record type 迁移失败 | Phase 2 阻塞 | A1 brainstorming 必须专门讨论 schema version bump 策略 + 开发版沙箱先跑通 |
| 定价和 IAP 产品 ID 不一致 | 送审反复 | Track C spec 必须在 Track D2 开始前 Final |
| TestFlight 测试员真实反馈不足 | 上架后一堆已知 bug | 外测至少 4 周 + 外测必含 ≥ 5 对情侣 |

---

## Self-Review Coverage Check

（每条对应源 spec 的某节，确认 Roadmap 都有承接）

- [x] § 1 核心分档模型 → **Track A** Phase 2 基础设施承接
- [x] § 2 Pro 功能 4 项 → **Track A** 各模块门禁改造 + **Track B** 付费墙展示
- [x] § 2.5.1 authored-by 模型 + 数据迁移 → **Track A1 锚点 5** 专项讨论
- [x] § 2.5.3 沾光模式 → **Track A** 无需特殊代码（CKShare 天然），但 **Track B** 付费墙文案要说明
- [x] § 2.5.4 解除配对处理 → **Track A1** 应作为边界场景讨论
- [x] § 2.5.5 CKShare 体验差异 → **Track B1 锚点 6** 付费墙文案
- [x] § 2.5.6 仅客户端执行 → **Track A1 锚点 8** 明确原则
- [x] § 3 四个触发场景 → **Track B1 锚点 1** 完整对应
- [x] § 4 白名单 4 类 → **Track A1 锚点 1** 表结构 + **Track D4/D5** 运维流程
- [x] § 4 TestFlight ④ 宽限叠加 → **Track D5** 执行 + **Track A** Edge Function 处理
- [x] § 5.1 老用户 grandfather → **Track D4** 专项任务
- [x] § 5.2 温和降级 + 14 天宽限 → **Track A** Edge Function + **Track B** 横幅 UI
- [x] § 5.3 状态切换时序 → **Track A** Edge Function 逻辑实现
- [x] § 6 超出范围清单（附件/AI/导出/家庭共享）→ 全部不出现在本 Roadmap，符合预期
- [x] § 7 成功指标 → 上架后观察，不在 Roadmap 内，正常

**完整覆盖确认** ✅ — 源 spec 所有正式章节都在本 Roadmap 找到承接任务。

---

## 执行方式说明

本 Roadmap 的"执行"**不是跑代码**，而是在用户决定启动某个 Track 时，调用相应的 skill 进行下一轮的 brainstorming 或 writing-plans。

| Track | 下一步动作 | 调用的 skill |
|---|---|---|
| Track A1 | 启动 Phase 2 Infra 的 brainstorming | `superpowers-brainstorming` |
| Track A2 | 启动 Phase 2 Infra 的 writing-plans | `superpowers-writing-plans` |
| Track A3 | 启动 Phase 2 Infra 的代码实现 | `superpowers-subagent-driven-development` |
| Track B1 | 启动 Phase 3 UI 的 brainstorming | `superpowers-brainstorming` |
| Track B2 | 启动 Phase 3 UI 的 writing-plans | `superpowers-writing-plans` |
| Track B3 | 启动 Phase 3 UI 的代码实现 | `superpowers-subagent-driven-development` |
| Track C1 | 启动定价 spec 的 brainstorming | `superpowers-brainstorming` |
| Track D1-D5 | 非代码运营工作，用户手工执行 | — |

**标准 Subagent-Driven / Inline Execution 选项在本 Roadmap 不适用**，因为本 Roadmap 的任务不是代码任务，而是"启动下游 skill"的决策任务。
