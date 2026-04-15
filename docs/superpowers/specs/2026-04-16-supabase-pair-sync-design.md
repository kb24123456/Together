# Together iOS App — Supabase 双人同步架构完整设计

> 创建日期: 2026-04-16
> 状态: 已批准，待实施
> 范围: 双人模式后端迁移（CloudKit → Supabase）+ UX 功能增强

## Context

Together 是一个 iOS 待办/协作 app（SwiftUI + SwiftData + CloudKit）。当前双人模式使用 CloudKit 公共库做同步，真机测试暴露根本性体验问题（5-30s 轮询延迟、双系统冲突、限流）。决策：保留 CKSyncEngine 做单人多端同步，用 Supabase 替换 CloudKit 公共库做双人同步。

本设计覆盖两个维度：
1. **UX 功能设计**：已读状态、任务消息流（留言+协商+催促+RPS）、活动时间线、每周回顾、纪念日倒计时
2. **后端架构设计**：Supabase 数据库 Schema、RLS 安全策略、Realtime 同步、APNs 推送、数据生命周期管理

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Together iOS App                          │
│                                                             │
│  SwiftData (本地)  ←→  CKSyncEngine (单人多端, 保持不变)     │
│       ↕                                                     │
│  LocalSyncCoordinator (变更队列, 复用)                       │
│       ↕                                                     │
│  SupabaseSyncService (新, 替代 PairSyncService)              │
│       ↕                        ↕                            │
│  Supabase REST API        Supabase Realtime WebSocket       │
└─────┬──────────────────────────┬────────────────────────────┘
      ↓                          ↓
┌─────────────────── Supabase Cloud ──────────────────────────┐
│  PostgreSQL (8张业务表 + 3张系统表)                           │
│  Row Level Security (space 成员隔离)                         │
│  Realtime (postgres_changes 广播)                            │
│  Database Webhook → Edge Function → APNs 推送               │
│  Supabase Storage (头像文件)                                 │
│  Supabase Auth (Sign in with Apple → JWT)                   │
└─────────────────────────────────────────────────────────────┘
```

### 关键设计原则
1. **单一数据流**：本地变更 → PersistentSyncChange 队列 → Supabase push → Realtime/APNs 通知对方
2. **保留复用**：LocalSyncCoordinator、PersistentSyncChange 队列机制不变
3. **双通道通知**：前台 WebSocket（毫秒级）+ 后台 APNs（秒级），互补不重复
4. **权限双保险**：客户端 PairPermissionService 做 UI 层拦截，RLS 做数据库层兜底
5. **完全数据隔离**：个人空间 → CKSyncEngine，共享空间 → Supabase，互不干扰

### 代码变更概览
**删除 ~2083 行**：PairSyncService、8个 Pair*RecordCodec、PairSyncCodecRegistry、PairSchemaSeeder、CloudKitSubscriptionManager、CloudKitInviteGateway、PairSyncPoller

**新增模块**：
| 模块 | 预估行数 | 职责 |
|------|---------|------|
| SupabaseSyncService | ~400 | push/pull + Realtime 订阅 |
| SupabaseAuthService | ~100 | Sign in with Apple → Supabase JWT |
| SupabaseInviteGateway | ~80 | 6 位码配对 |
| Edge Function: send-push-notification | ~120 | APNs 推送 |
| 客户端推送注册 | ~50 | device token 管理 |

---

## 2. 核心产品决策

| 决策项 | 结论 |
|--------|------|
| 用户场景 | 情侣/夫妻共同管理生活 |
| UX 调性 | 温暖、亲密、轻松 |
| 架构模式 | 直写 DB + Realtime + Edge Function(APNs) |
| 规模起步 | Supabase Free Plan，架构可平滑升级 Pro |
| 数据迁移 | 无需（测试数据，全新开始） |
| 离线策略 | SwiftData + PersistentSyncChange 天然支持，Supabase 做好重连补推 |
| 解绑处理 | 共享数据全部软删除，退出双人模式 |
| 重新配对 | 允许，从零开始（旧数据不可恢复） |
| 数据隔离 | 个人/共享完全隔离，UI 模式切换按钮 |
| 配对约束 | 严格一对一 |
| 认证时机 | App 首次启动即 Sign in with Apple |
| 推送 | APNs 必须支持，后台通知保证体验 |

---

## 3. 数据库 Schema（11 张表）

### 3.1 系统表

**`device_tokens`** — APNs 推送令牌
```sql
CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  token text NOT NULL,
  platform text DEFAULT 'ios',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, token)
);
```

**`pair_invites`** — 配对邀请
```sql
CREATE TABLE pair_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  inviter_id uuid REFERENCES auth.users NOT NULL,
  invite_code text NOT NULL,
  status text DEFAULT 'pending', -- pending/accepted/expired/cancelled
  accepted_by uuid REFERENCES auth.users,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '24 hours'),
  responded_at timestamptz
);
```

### 3.2 业务表

**`spaces`** — 共享空间
```sql
CREATE TABLE spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid REFERENCES auth.users NOT NULL,
  type text DEFAULT 'pair',
  display_name text NOT NULL,
  status text DEFAULT 'active', -- active/archived
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**`space_members`** — 空间成员
```sql
CREATE TABLE space_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  display_name text NOT NULL,
  avatar_url text,
  avatar_version int DEFAULT 0,
  role text DEFAULT 'member', -- owner/member
  joined_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(space_id, user_id)
);
```

**`tasks`** — 任务
```sql
CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  list_id uuid REFERENCES task_lists,
  project_id uuid REFERENCES projects,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  notes text,
  assignee_mode text DEFAULT 'self', -- self/partner/both
  status text DEFAULT 'pending', -- pending/inProgress/completed/declined
  due_at timestamptz,
  has_explicit_time bool DEFAULT false,
  remind_at timestamptz,
  is_pinned bool DEFAULT false,
  is_draft bool DEFAULT false,
  is_read_by_partner bool DEFAULT false,
  read_at timestamptz,
  repeat_rule jsonb,
  occurrence_completions jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  is_archived bool DEFAULT false,
  archived_at timestamptz,
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);
```

**`task_messages`** — 任务消息流（留言+催促+RPS）
```sql
CREATE TABLE task_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid REFERENCES tasks NOT NULL,
  sender_id uuid REFERENCES auth.users NOT NULL,
  type text NOT NULL, -- comment/nudge/rps_result
  content text,
  emoji text,
  rps_result jsonb, -- {winner_id, loser_choice, winner_choice}
  created_at timestamptz DEFAULT now()
);
```

**`task_lists`** — 列表
```sql
CREATE TABLE task_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  name text NOT NULL,
  kind text DEFAULT 'custom', -- custom/systemInbox
  color_token text,
  sort_order float8 DEFAULT 0,
  is_archived bool DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);
```

**`projects`** — 项目
```sql
CREATE TABLE projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  name text NOT NULL,
  notes text,
  color_token text,
  status text DEFAULT 'active', -- active/onHold/completed/archived
  target_date timestamptz,
  remind_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);
```

**`project_subtasks`** — 项目子任务
```sql
CREATE TABLE project_subtasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES projects NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  is_completed bool DEFAULT false,
  sort_order int DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false
);
```

**`periodic_tasks`** — 例行事务
```sql
CREATE TABLE periodic_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  notes text,
  cycle text NOT NULL, -- weekly/monthly/quarterly/yearly
  reminder_rules jsonb DEFAULT '[]',
  completions jsonb DEFAULT '{}',
  sort_order float8 DEFAULT 0,
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);
```

**`activity_log`** — 活动时间线（分区表）
```sql
CREATE TABLE activity_log (
  id uuid DEFAULT gen_random_uuid(),
  space_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  action text NOT NULL, -- created/completed/assigned/nudged/commented/...
  entity_type text NOT NULL, -- task/project/periodic_task/...
  entity_id uuid NOT NULL,
  entity_title text NOT NULL,
  metadata jsonb,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
```

**`important_dates`** — 纪念日
```sql
CREATE TABLE important_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  date date NOT NULL,
  is_recurring bool DEFAULT true,
  remind_days_before int,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false
);
```

### 3.3 核心索引
```sql
-- RLS 依赖索引（必须）
CREATE INDEX idx_space_members_user ON space_members(user_id);
CREATE INDEX idx_space_members_space ON space_members(space_id);

-- 业务表 space_id 索引
CREATE INDEX idx_tasks_space ON tasks(space_id);
CREATE INDEX idx_tasks_space_active ON tasks(space_id, is_archived) WHERE is_deleted = false;
CREATE INDEX idx_task_lists_space ON task_lists(space_id) WHERE is_deleted = false;
CREATE INDEX idx_projects_space ON projects(space_id) WHERE is_deleted = false;
CREATE INDEX idx_periodic_tasks_space ON periodic_tasks(space_id) WHERE is_deleted = false;
CREATE INDEX idx_important_dates_space ON important_dates(space_id) WHERE is_deleted = false;

-- 消息查询索引
CREATE INDEX idx_task_messages_task ON task_messages(task_id, created_at DESC);

-- 活动日志索引
CREATE INDEX idx_activity_log_space_time ON activity_log(space_id, created_at DESC);

-- 配对码查询索引
CREATE INDEX idx_pair_invites_code ON pair_invites(invite_code) WHERE status = 'pending';

-- 推送令牌索引
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
```

---

## 4. RLS 安全策略

### 辅助函数
```sql
CREATE FUNCTION is_space_member(check_space_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM space_members
    WHERE space_id = check_space_id
    AND user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;
```

### 统一策略模式（tasks/task_lists/projects/periodic_tasks/important_dates 通用）
```sql
-- 读：space 成员可读
FOR SELECT USING (is_space_member(space_id));

-- 写：space 成员可创建，creator_id 必须是自己
FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());

-- 更新：space 成员可更新
FOR UPDATE USING (is_space_member(space_id));
```

### 特殊策略
- **spaces**: 只有 owner 可 UPDATE
- **space_members**: 成员可读，只能 UPDATE 自己的记录（改昵称/头像）
- **task_messages**: sender_id 必须是自己
- **activity_log**: 只读（由 Database Trigger 写入）
- **pair_invites**: 任何已登录用户可通过 invite_code 查询 pending 邀请
- **device_tokens**: 只能读写自己的 token
- **project_subtasks**: 通过 project 的 space_id 间接验证

---

## 5. 认证 + 配对流程

### 认证
```
App 首次启动 → Sign in with Apple → identityToken
→ supabase.auth.signInWithIdToken(provider: .apple, idToken: token)
→ Supabase session (access_token + refresh_token) → 本地持久化
→ 后续所有请求自动携带 JWT，Token 过期自动 refresh
```

### 配对流程
```
Device A（邀请方）               Supabase                  Device B（接受方）
1. 点击"邀请伴侣"
2. INSERT spaces (status: active)
3. INSERT space_members (role: owner)
4. INSERT pair_invites (6位码, 24h过期)
5. 显示邀请码
                                                         6. 输入邀请码
                                                         7. SELECT pair_invites WHERE code = X
                                                         8. UPDATE invite → accepted
                                                         9. INSERT space_members (role: member)
10. Realtime 收到 space_members 变更 → 配对完成
```

### 解绑流程
```
任一方点击"解除配对" → 二次确认弹窗
→ UPDATE spaces SET status = 'archived'
→ UPDATE 所有业务表 SET is_deleted = true WHERE space_id = X
→ DELETE space_members WHERE space_id = X
→ 对方 Realtime 收到 → 自动退出双人模式
→ 客户端清理本地共享数据
```

---

## 6. 实时同步设计

### SupabaseSyncService 三大职责
1. **PUSH**：读取 PersistentSyncChange 队列 → Supabase REST upsert
2. **LISTEN**：Realtime WebSocket 订阅 → 收到变更 → 过滤回声 → 写入 SwiftData
3. **CATCH-UP**：断线重连后 SELECT WHERE updated_at > lastSyncedAt 补拉

### 同步路由
```
LocalSyncCoordinator.recordLocalChange(change)
  → change.spaceID == sharedSpaceID ? SupabaseSyncService : SyncEngineCoordinator
```

### Realtime 频道策略
单一频道 `space:{space_id}` 监听所有相关表的 postgres_changes。只有 2 个用户，单频道完全够用。

### Query first, Subscribe second
启动时先 catchUp() 拉取最新数据，再开启 Realtime 订阅，避免数据缺口。

---

## 7. APNs 推送设计

### 架构
```
DB 变更 → Database Webhook → Edge Function → 查找对方 device token → APNs HTTP/2 → Apple → 对方设备
```

### Edge Function: send-push-notification (~120 行 Deno)
- 接收 webhook payload（table, type, record）
- 查找对方 user_id 和 device_token
- 过滤：不给操作者自己发推送
- 构造推送内容（按操作类型）
- APNs 认证：.p8 密钥（token-based），存为 Supabase Secret

### 推送内容
| 操作 | 推送 |
|-----|------|
| 新任务指派 | "{伴侣名} 给你分配了「{任务名}」" |
| 完成任务 | "{伴侣名} 完成了「{任务名}」" |
| 催促 | "{伴侣名} 催你完成「{任务名}」" |
| 留言 | "{伴侣名} 在「{任务名}」留了言" |
| RPS | "{伴侣名} 发起了石头剪刀布！" |
| 纪念日 | "距离「{日子名}」还有 {N} 天" |

### 防重复
- 前台收到 Realtime 事件 → 标记已处理
- 推送到达时检查 → 避免用户看到两次
- 非关键操作（已读变更）发静默推送

---

## 8. UX 功能设计

### 8.1 已读状态
- tasks 表 `is_read_by_partner` + `read_at`
- 打开任务详情时自动标记已读
- 列表中未读任务有小蓝点，详情底部显示"已读 14:32"
- 任务被编辑后重置为未读

### 8.2 任务消息流（留言 + 协商 + 催促 + RPS 统一）
- `task_messages` 表统一承载所有任务内互动
- type: comment（留言）、nudge（催促）、rps_result（随机决定）
- 协商不是独立状态机，而是在留言中自然发生
- "转给对方"按钮直接改 assignee_mode
- "让命运决定"触发系统随机 + 趣味动画，结果写入 rps_result
- 催促：同一任务 24h 限一次
- UI：任务详情页底部迷你消息流

### 8.3 活动时间线
- `activity_log` 分区表，Database Trigger 自动写入
- 展示双方操作的动态流（创建、完成、催促、留言等）
- entity_title 快照避免联表查询
- 客户端只拉最近 7 天，下拉加载更多

### 8.4 每周回顾
- 完全本地计算，不需要后端
- 每周日本地通知推送
- 卡片展示：本周完成总数、各自完成数、最活跃分类

### 8.5 纪念日倒计时
- `important_dates` 表
- 支持每年重复 + 提前 N 天提醒
- 首页/仪表盘展示倒计时卡片
- 两人都能创建和查看

---

## 9. 数据生命周期管理

### 三级数据生命周期
| 级别 | 时间范围 | 处理 |
|------|---------|------|
| Hot（活跃） | 最近 90 天 | 正常查询 |
| Warm（归档） | 90天-1年 | is_archived = true，需主动翻阅 |
| Cold（清除） | 超过 1 年 | 定期硬删除 |

### 实现机制
- **pg_cron** 定时任务：每周检查完成超过 90 天的任务 → 自动标记归档
- **activity_log 分区**：按月分区，超过 1 年的分区 DROP
- **客户端默认查询**：WHERE is_archived = false，减少查询量
- **Storage 清理**：pg_cron 定期清理 7 天前的旧头像文件

### 索引策略
- 所有 RLS 依赖列必须有索引
- RLS 函数用 SELECT 包裹启用查询计划缓存
- 用 pg_stat_statements 监控慢查询

---

## 10. 分 Phase 实施计划

| Phase | 内容 | 依赖 |
|-------|------|------|
| **Phase 1** | Supabase 项目搭建 + DB Schema + RLS + Auth + SupabaseSyncService（push/pull/realtime）+ 配对流程 + 解绑流程 + 已读状态 + APNs 推送 + 删除旧 CloudKit 双人同步代码 | 无 |
| **Phase 2** | 任务消息流（留言+催促+RPS）+ 消息流 UI | Phase 1 |
| **Phase 3** | 活动时间线 + 每周回顾 + 纪念日倒计时 | Phase 1 |

每个 Phase 可独立上线。Phase 2 和 Phase 3 互不依赖，可并行开发。

---

## 11. 验证方案

### Phase 1 验证
1. 两台真机分别 Sign in with Apple → 确认 Supabase Auth 正常
2. 设备 A 生成邀请码 → 设备 B 输入 → 配对成功
3. 设备 A 创建任务 → 设备 B 毫秒级收到 → 确认 Realtime 正常
4. 设备 B 打开任务 → 设备 A 看到"已读"标记
5. 设备 A 杀掉 App → 设备 B 创建任务 → 设备 A 收到 APNs 推送
6. 断网 → 创建任务 → 恢复网络 → 确认数据补推成功
7. 单人模式创建任务 → 确认只走 CKSyncEngine，不触碰 Supabase
8. 解除配对 → 确认共享数据清除，双方回到单人模式
9. 重新配对 → 确认从空白开始

### Phase 2 验证
1. 在任务上发送留言 → 对方实时收到
2. 转给对方 → 对方再转回 → 来回协商
3. 触发 RPS → 动画播放 → assignee_mode 自动更新
4. 催促 → APNs 推送 → 24h 内再催被拦截

### Phase 3 验证
1. 创建/完成任务 → activity_log 自动记录
2. 活动时间线页面展示正确
3. 每周日本地通知 → 回顾卡片数据正确
4. 创建纪念日 → 倒计时显示正确 → 提前 N 天收到提醒

---

## 关键文件路径（将被修改）

| 文件 | 变更类型 |
|------|---------|
| Together/Sync/PairSyncService.swift | 删除 |
| Together/Sync/Codecs/Pair*.swift (8个) | 删除 |
| Together/Sync/PairSyncCodecRegistry.swift | 删除 |
| Together/Sync/PairSchemaSeeder.swift | 删除 |
| Together/Sync/PairSyncPoller.swift | 删除 |
| Together/Sync/CloudKitSubscriptionManager.swift | 删除 |
| Together/Sync/CloudKitInviteGateway.swift | 删除 |
| Together/App/AppContext.swift | 修改（接入 SupabaseSyncService） |
| Together/Sync/LocalSyncCoordinator.swift | 修改（添加同步路由） |
| Together/Services/Pairing/CloudPairingService.swift | 替换为 SupabaseInviteGateway |
| 新增: Together/Sync/SupabaseSyncService.swift | 新建 |
| 新增: Together/Services/Auth/SupabaseAuthService.swift | 新建 |
| 新增: Together/Services/Pairing/SupabaseInviteGateway.swift | 新建 |
| 新增: supabase/functions/send-push-notification/ | 新建 Edge Function |
| 新增: supabase/migrations/*.sql | 新建 DB 迁移脚本 |
