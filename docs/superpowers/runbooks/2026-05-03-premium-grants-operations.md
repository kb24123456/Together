# Together Pro 开发者赠权 Runbook

适用范围：开发者、亲友、TestFlight 测试、问题补偿、客服支持。此流程不是 App 外部销售、公开兑换码或绕过 App Store 内购的付费渠道。

## 前置原则

- 只按 Supabase `auth.users.id` 授权，不按昵称、邮箱或设备猜测用户。
- 只由开发者在 Supabase Dashboard SQL Editor、Supabase CLI、受控后台或 service role 环境执行。
- 不把 service role key、RevenueCat key、webhook secret 写入仓库、聊天记录或项目记忆。
- 授权原因必须可审计，`notes` 中写清楚来源，例如 `developer test`、`friend grant`、`support compensation`。

## 查询用户当前权益

```sql
select
  id,
  category,
  starts_at,
  ends_at,
  revoked_at,
  notes,
  created_at
from public.premium_grants
where user_id = '<AUTH_USER_ID>'::uuid
order by created_at desc;

select
  user_id,
  product_id,
  entitlement_id,
  store,
  purchased_at,
  expires_at,
  revoked_at,
  raw_event_type,
  updated_at
from public.premium_entitlements
where user_id = '<AUTH_USER_ID>'::uuid
order by updated_at desc;
```

## 添加临时赠权

```sql
insert into public.premium_grants (
  user_id,
  category,
  starts_at,
  ends_at,
  notes
) values (
  '<AUTH_USER_ID>'::uuid,
  'developer',
  now(),
  now() + interval '30 days',
  'developer grant: manual test or support compensation'
);
```

## 添加永久赠权

仅用于明确的开发者、亲友或早期用户白名单。不要用于公开销售或公开兑换。

```sql
insert into public.premium_grants (
  user_id,
  category,
  starts_at,
  ends_at,
  notes
) values (
  '<AUTH_USER_ID>'::uuid,
  'friend',
  now(),
  null,
  'friend grant: permanent whitelist'
);
```

## 撤销赠权

软撤销，不物理删除历史记录。

```sql
update public.premium_grants
set revoked_at = now()
where user_id = '<AUTH_USER_ID>'::uuid
  and revoked_at is null
  and (ends_at is null or ends_at > now());
```

## 真机验收

1. App 登录该 Supabase 用户。
2. Profile 进入会员页前刷新状态。
3. 预期：赠权有效时显示 Pro；撤销后刷新应回到 Free，除非该用户仍有 App Store / RevenueCat active entitlement。
4. 若撤销后仍是 Pro，先查 `premium_entitlements` 和 RevenueCat customer；不要只看 `premium_grants`。

## App Store 合规边界

- 公开付费能力必须走 Apple IAP / App Store。
- 开发者赠权只用于非公开补偿、测试、亲友或运营支持。
- App 内不提供公开兑换入口，不引导用户绕过 IAP 支付。
