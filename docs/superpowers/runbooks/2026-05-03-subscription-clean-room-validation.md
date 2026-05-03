# Subscription Clean-room Validation Runbook

目标：在不混用历史购买、旧 entitlement、DEBUG override、旧 TestFlight build 的前提下，重新验证 Together Pro 的真实订阅链路。

本 runbook 只用于 **TestFlight / Sandbox / 测试账号**。不要对真实生产用户执行清理 SQL。

## 0. 当前结论

- 不建议继续在已有脏状态上反复点购买和恢复购买。
- 建议先做 clean-room：Apple Sandbox、RevenueCat、Supabase、本地 App 状态逐层归零或显式确认。
- 最稳测试路径：使用一个全新的 Sandbox Apple Account。Apple 提供清除 sandbox 购买历史能力，但对于订阅/恢复购买/RevenueCat alias 测试，新账号更可控。
- 清空 Supabase 只能清空本 app 后端状态，不能清空 Apple 的订阅事实；Apple 仍认为已订阅时，再点购买会弹“你目前已订阅此项目”。

## 1. 角色和测试账号

本轮至少准备两个身份：

| 角色 | 用途 | 要求 |
|---|---|---|
| App 用户 A | 测试购买者 | Supabase auth 用户固定，可记录 `auth.users.id` |
| Sandbox Apple Account A | 测试月订阅新购 | 优先新建；如复用，必须先清除购买历史 |

建议额外准备：

| 角色 | 用途 | 要求 |
|---|---|---|
| Sandbox Apple Account B | 恢复购买/账号切换测试 | 不与新购测试混用 |
| App 用户 B | 双人功能回归 | 不参与订阅清理，除非明确测试家庭/多账号 |

## 2. Clean-room 前置冻结

开始清理前先冻结变量：

- [ ] 当前测试 build 号已确认，且包含所有已修复问题。
- [ ] 当前 App 是 TestFlight Release，不是本地 Debug。
- [ ] Profile 里没有开发者 DEBUG 会员状态覆盖入口；若有，视为阻塞。
- [ ] RevenueCat Dashboard 中 entitlement 名称为 `pro`。
- [ ] App 内 `RevenueCatConfig.entitlementIdentifier == "pro"`。
- [ ] RevenueCat app user id 必须等于 Supabase `auth.uid()`，大小写一致性需在日志或 RevenueCat customer 中确认。
- [ ] Supabase webhook function 已部署，RevenueCat webhook 已指向同一 URL。
- [ ] webhook secret 在 RevenueCat 和 Supabase Edge Function 环境中一致。

阻塞判定：

- 如果 build 不是最新，先打新 build，不进入购买测试。
- 如果 DEBUG override 仍出现在 TestFlight，先移除或编译条件隔离，不进入购买测试。
- 如果 RevenueCat customer id 与 Supabase `auth.uid()` 不一致，先修身份链路。

## 3. 后端状态审查 SQL

将 `<USER_ID>` 替换为 Supabase `auth.users.id`。

### 3.1 用户身份

```sql
select id, email, created_at, last_sign_in_at, raw_user_meta_data
from auth.users
where id = '<USER_ID>'::uuid;
```

通过标准：

- [ ] 只返回 1 行。
- [ ] `last_sign_in_at` 接近当前测试时间。
- [ ] 该用户就是当前 App 登录用户。

### 3.2 Supabase grants

```sql
select user_id, category, reason, granted_at, expires_at, revoked_at
from public.premium_grants
where user_id = '<USER_ID>'::uuid
order by granted_at desc;
```

通过标准：

- [ ] 新购测试前不应存在 `revoked_at is null` 的 developer/friend/grandfather/testflight grant。

### 3.3 Supabase RevenueCat entitlements

```sql
select
  id,
  user_id,
  entitlement_id,
  product_id,
  original_transaction_id,
  transaction_id,
  store,
  environment,
  purchased_at,
  expires_at,
  revoked_at,
  last_event_type,
  last_event_at,
  updated_at
from public.premium_entitlements
where user_id = '<USER_ID>'::uuid
order by updated_at desc;
```

通过标准：

- [ ] 新购测试前不应存在 `entitlement_id = 'pro' and revoked_at is null and (expires_at is null or expires_at > now())`。
- [ ] 如存在有效行，App 应显示 Pro；若 App 显示 Free，则是前端状态刷新/读取问题，不应继续购买。

### 3.4 RLS 策略

```sql
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('premium_entitlements', 'premium_grants')
order by tablename, policyname;
```

通过标准：

- [ ] `premium_entitlements` 和 `premium_grants` 只有 authenticated 用户可读自己的行。
- [ ] 不允许 anon 读取会员状态表。

## 4. 后端清理 SQL

只对测试用户执行。建议先 `begin`，查询确认，再 `commit`。

### 4.1 Dry-run

```sql
select 'premium_grants_active' as source, count(*) as count
from public.premium_grants
where user_id = '<USER_ID>'::uuid
  and revoked_at is null
union all
select 'premium_entitlements_active' as source, count(*) as count
from public.premium_entitlements
where user_id = '<USER_ID>'::uuid
  and revoked_at is null
  and entitlement_id = 'pro';
```

### 4.2 推荐清理：软撤销

```sql
begin;

update public.premium_grants
set revoked_at = coalesce(revoked_at, now())
where user_id = '<USER_ID>'::uuid
  and revoked_at is null;

update public.premium_entitlements
set
  revoked_at = coalesce(revoked_at, now()),
  updated_at = now()
where user_id = '<USER_ID>'::uuid
  and revoked_at is null
  and entitlement_id = 'pro';

select 'premium_grants_after' as source, count(*) as active_count
from public.premium_grants
where user_id = '<USER_ID>'::uuid
  and revoked_at is null
union all
select 'premium_entitlements_after' as source, count(*) as active_count
from public.premium_entitlements
where user_id = '<USER_ID>'::uuid
  and revoked_at is null
  and entitlement_id = 'pro';

commit;
```

通过标准：

- [ ] 两个 `active_count` 都是 0。
- [ ] 重新打开 App 后 Profile 显示 Free。

注意：

- 不建议物理删除 entitlement 行；保留审计历史更安全。
- 如果 RevenueCat 或 Apple 后续再次发送 active webhook，同一用户会重新变 Pro，这是正确行为。
- 如果 Apple Sandbox Account 仍有有效订阅，清理 Supabase 后再点购买仍可能出现“已订阅此项目”；这不是 Supabase 清理失败，而是 Apple 订阅事实仍存在。

## 5. RevenueCat 检查项

在 RevenueCat MCP / Dashboard 检查：

- [ ] Project 是 `Together`。
- [ ] Entitlement `pro` 存在。
- [ ] Offering 当前可用，并包含月订阅、年订阅、终身产品。
- [ ] Customer ID 等于 Supabase `auth.uid()`。
- [ ] 新购前，Customer active entitlements 为空。
- [ ] 新购成功后，Customer active entitlements 出现 `pro`。
- [ ] 新购成功后，webhook event 能到 Supabase，`premium_entitlements` 出现对应行。
- [ ] 如果 RevenueCat v2 customer active entitlements 为空，但 Apple 弹窗提示已订阅，需要用 Dashboard / v1 subscriber / webhook history 交叉确认，不直接继续购买。

阻塞判定：

- RevenueCat Customer ID 不等于 Supabase `auth.uid()`：阻塞。
- RevenueCat 有 active `pro`，Supabase 没有 active entitlement：webhook 阻塞。
- Supabase 有 active entitlement，App 仍显示 Free：前端 PremiumGate 刷新/读取阻塞。
- Apple 提示已订阅，但 RevenueCat 和 Supabase 都没有 active：sandbox Apple 账号历史或 receipt 归属阻塞，换全新 Sandbox Apple Account。

## 6. 前端阻塞点清单

购买测试前必须审阅这些点：

- [ ] 冷启动 / 登录成功后必须调用 `configurePremiumGate()`。
- [ ] `configurePremiumGate()` 必须先恢复 Supabase session，再 `RevenueCat.logIn(appUserID: auth.uid())`。
- [ ] `PremiumGate` 必须合并三类来源：RevenueCat SDK、`premium_grants`、`premium_entitlements`。
- [ ] 进入会员页 Free 分支前，必须强制刷新一次 PremiumGate；若后端已有有效 entitlement，不应显示 Paywall。
- [ ] 购买成功或 pending 后，应短时间等待 PremiumGate 转 Pro；不能立刻把用户留在可再次购买的 Paywall。
- [ ] 恢复购买成功后，应刷新 PremiumGate 并退出 Paywall。
- [ ] Paywall CTA 在 `purchasing/restoring/succeeded` 期间必须禁用。
- [ ] `entitlementNotReady` 只能用于短暂最终一致延迟，不能长期作为正常结果。
- [ ] logout 必须清理本地 PremiumGate cache，但重新 login 后必须能从 Supabase `premium_entitlements` 恢复 Pro。
- [ ] TestFlight Release 中不得展示 DEBUG 会员 override。

## 7. Clean-room 真机验收流程

### 7.1 安装和登录

- [ ] 安装最新 TestFlight build。
- [ ] 登录 App 用户 A。
- [ ] Profile 显示 Free。
- [ ] Supabase dry-run 确认无 active grant / entitlement。
- [ ] RevenueCat customer active entitlements 为空。

### 7.2 新购月订阅

- [ ] 打开会员页。
- [ ] 选择月订阅。
- [ ] 点击购买。
- [ ] Apple 系统购买弹窗出现。
- [ ] 确认购买。
- [ ] App 显示成功，退出 Paywall 或会员页变为 Pro。
- [ ] Supabase `premium_entitlements` 出现 `pro` active 行。
- [ ] RevenueCat active entitlements 出现 `pro`。

失败阻塞：

- 不弹 Apple 系统购买弹窗，直接变 Pro：先查是否仍有后端 active entitlement 或 Apple 已订阅历史。
- Apple 购买成功但 Paywall 仍显示购买选项：前端状态刷新阻塞。
- Apple 提示已订阅此项目：当前 Sandbox Apple Account 不再适合新购测试，换新账号或清除 Apple sandbox 历史。

### 7.3 退出重登

- [ ] 退出登录。
- [ ] 杀掉 App。
- [ ] 重新打开并登录同一 App 用户 A。
- [ ] Profile 仍显示 Pro。
- [ ] 如果显示 Free，立刻检查 Supabase active entitlement；若存在，则前端登录后 PremiumGate 启动阻塞。

### 7.4 恢复购买

恢复购买不要和“当前已 Pro”混在一起测试。

推荐路径：

1. 使用同一 Sandbox Apple Account 保留订阅。
2. 清空 App 本地状态或重新安装。
3. 登录同一 App 用户 A。
4. 如果后端 entitlement 已存在，App 应自动显示 Pro，不需要点恢复购买。
5. 若后端无 entitlement，但 Apple/RevenueCat 有购买历史，进入 Paywall 点恢复购买。

通过标准：

- [ ] 恢复后 App 显示 Pro。
- [ ] Supabase entitlement 被补写或保持 active。

### 7.5 过期/续订

Sandbox 订阅会加速续订和过期。此项单独测试，不与新购混用。

- [ ] 等待 sandbox 月订阅自动续订。
- [ ] RevenueCat webhook 收到续订事件。
- [ ] Supabase entitlement `expires_at` 更新。
- [ ] App 前台刷新后仍显示 Pro。
- [ ] 订阅过期后，App 进入 Free 或 Grace 规则，且不错误保留完整 Pro 权益。

## 8. 本轮不做的事

- 不在真实生产用户上清理订阅。
- 不用 Debug override 验证真实支付。
- 不用旧 build 验证新修复。
- 不把 Apple Sandbox、RevenueCat、Supabase 三层状态混为一个状态。
- 不在 Apple 仍提示“已订阅此项目”的账号上继续做新购测试。

## 9. 最终通过标准

以下全部满足，才允许打包进入下一轮 TestFlight 验收：

- [ ] 新购：Free → Apple 弹窗 → 购买成功 → App Pro → Supabase active entitlement → RevenueCat active entitlement。
- [ ] 退出重登：仍 Pro。
- [ ] 重新安装：仍 Pro 或可恢复为 Pro。
- [ ] 后端清理 active entitlement 后：App 变 Free。
- [ ] Apple 已订阅场景：App 不展示可再次购买的普通 Paywall。
- [ ] RevenueCat / Supabase / App 三方状态不一致时，有明确日志和 UI fallback，不让用户无限重复购买。

