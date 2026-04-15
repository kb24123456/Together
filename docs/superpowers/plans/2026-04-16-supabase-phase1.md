# Supabase 双人同步 Phase 1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将双人模式从 CloudKit 公共库迁移到 Supabase，实现毫秒级实时同步 + APNs 推送 + 已读状态。

**Architecture:** 保留 CKSyncEngine 做单人多端同步（不动），新建 SupabaseSyncService 替代 PairSyncService。通过 LocalSyncCoordinator 的 spaceID 路由，将共享空间变更导向 Supabase REST API + Realtime WebSocket。APNs 推送由 Supabase Edge Function 处理。

**Tech Stack:** Supabase (PostgreSQL + Realtime + Auth + Storage + Edge Functions), supabase-swift SDK, Sign in with Apple, APNs HTTP/2

**Design Spec:** `docs/superpowers/specs/2026-04-16-supabase-pair-sync-design.md`

---

## 文件结构总览

### 新建文件
| 文件路径 | 职责 |
|---------|------|
| `Together/Services/Auth/SupabaseAuthService.swift` | Sign in with Apple → Supabase JWT |
| `Together/Services/Auth/SupabaseClient.swift` | Supabase 客户端单例 |
| `Together/Sync/SupabaseSyncService.swift` | Push/Pull + Realtime 订阅 |
| `Together/Services/Pairing/SupabaseInviteGateway.swift` | 6 位码配对 REST 操作 |
| `Together/Services/Push/DeviceTokenService.swift` | APNs token 注册 |
| `supabase/migrations/001_initial_schema.sql` | 建表 + 索引 + RLS |
| `supabase/functions/send-push-notification/index.ts` | APNs 推送 Edge Function |

### 修改文件
| 文件路径 | 修改内容 |
|---------|---------|
| `Together/App/AppContext.swift:178-383` | 替换 startPairSyncEngineIfNeeded / teardownPairSync / syncAfterMutation |
| `Together/Sync/LocalSyncCoordinator.swift:9-40` | 添加 Supabase 同步路由 |
| `Together/App/SessionStore.swift` | 适配 Supabase 配对状态 |
| `Together/Domain/Entities/TaskList.swift` | 添加 Codable 协议 |
| `Together/Domain/Entities/Project.swift` | 添加 Codable 协议 |
| `Together/Domain/Entities/ProjectSubtask.swift` | 添加 Codable 协议 |
| `Together/Domain/Entities/Space.swift` | 添加 Codable 协议 |
| `Together/Services/Pairing/LocalPairingService.swift` | 适配 Supabase 配对流程 |

### 删除文件
| 文件路径 | 行数 |
|---------|------|
| `Together/Sync/PairSyncService.swift` | 826 |
| `Together/Sync/Codecs/PairTaskRecordCodec.swift` | 150 |
| `Together/Sync/Codecs/PairTaskListRecordCodec.swift` | 68 |
| `Together/Sync/Codecs/PairProjectRecordCodec.swift` | 73 |
| `Together/Sync/Codecs/PairProjectSubtaskRecordCodec.swift` | 65 |
| `Together/Sync/Codecs/PairPeriodicTaskRecordCodec.swift` | 73 |
| `Together/Sync/Codecs/PairSpaceRecordCodec.swift` | 48 |
| `Together/Sync/Codecs/PairMemberProfileRecordCodec.swift` | 47 |
| `Together/Sync/Codecs/PairAvatarAssetRecordCodec.swift` | 53 |
| `Together/Sync/Codecs/PairSyncCodecRegistry.swift` | 113 |
| `Together/Sync/PairSchemaSeeder.swift` | 255 |
| `Together/Sync/CloudKitSubscriptionManager.swift` | 114 |
| `Together/Sync/CloudKitInviteGateway.swift` | 198 |
| `Together/Sync/PairSyncPoller.swift` | 133 |

---

## Task 1: Supabase 项目搭建 + 数据库 Schema

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`

- [ ] **Step 1: 创建 Supabase 项目**

在 Supabase Dashboard (https://supabase.com/dashboard) 创建新项目：
- 项目名: `together-pair`
- 区域: 选择离你最近的（如 `ap-northeast-1` 东京）
- 数据库密码: 生成强密码并安全保存

等待项目初始化完成（约 2 分钟）。

- [ ] **Step 2: 配置 Sign in with Apple**

在 Supabase Dashboard → Authentication → Providers → Apple：
- 启用 Apple provider
- 填入 Service ID（从 Apple Developer Portal 获取）
- 填入 Team ID 和 Key ID
- 上传 .p8 私钥文件

参考文档: https://supabase.com/docs/guides/auth/social-login/auth-apple

- [ ] **Step 3: 创建数据库迁移文件**

在项目根目录创建 `supabase/migrations/001_initial_schema.sql`，包含完整的建表、索引、RLS 策略：

```sql
-- =============================================================
-- Together Supabase Schema - Phase 1
-- =============================================================

-- 1. spaces（共享空间）
CREATE TABLE spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid REFERENCES auth.users NOT NULL,
  type text DEFAULT 'pair',
  display_name text NOT NULL,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. space_members（空间成员）
CREATE TABLE space_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  display_name text NOT NULL,
  avatar_url text,
  avatar_version int DEFAULT 0,
  role text DEFAULT 'member',
  joined_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(space_id, user_id)
);

-- 3. pair_invites（配对邀请）
CREATE TABLE pair_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces ON DELETE CASCADE NOT NULL,
  inviter_id uuid REFERENCES auth.users NOT NULL,
  invite_code text NOT NULL,
  status text DEFAULT 'pending',
  accepted_by uuid REFERENCES auth.users,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '24 hours'),
  responded_at timestamptz
);

-- 4. task_lists（列表）
CREATE TABLE task_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  name text NOT NULL,
  kind text DEFAULT 'custom',
  color_token text,
  sort_order float8 DEFAULT 0,
  is_archived bool DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 5. projects（项目）
CREATE TABLE projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  name text NOT NULL,
  notes text,
  color_token text,
  status text DEFAULT 'active',
  target_date timestamptz,
  remind_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 6. tasks（任务）
CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  list_id uuid REFERENCES task_lists,
  project_id uuid REFERENCES projects,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  notes text,
  assignee_mode text DEFAULT 'self',
  status text DEFAULT 'pending',
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

-- 7. task_messages（任务消息流）
CREATE TABLE task_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid REFERENCES tasks ON DELETE CASCADE NOT NULL,
  sender_id uuid REFERENCES auth.users NOT NULL,
  type text NOT NULL,
  content text,
  emoji text,
  rps_result jsonb,
  created_at timestamptz DEFAULT now()
);

-- 8. project_subtasks（项目子任务）
CREATE TABLE project_subtasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES projects ON DELETE CASCADE NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  is_completed bool DEFAULT false,
  sort_order int DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false
);

-- 9. periodic_tasks（例行事务）
CREATE TABLE periodic_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  notes text,
  cycle text NOT NULL,
  reminder_rules jsonb DEFAULT '[]',
  completions jsonb DEFAULT '{}',
  sort_order float8 DEFAULT 0,
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 10. important_dates（纪念日）— Phase 3 使用，提前建表
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

-- 11. device_tokens（APNs 推送令牌）
CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  token text NOT NULL,
  platform text DEFAULT 'ios',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, token)
);

-- =============================================================
-- 索引
-- =============================================================

CREATE INDEX idx_space_members_user ON space_members(user_id);
CREATE INDEX idx_space_members_space ON space_members(space_id);
CREATE INDEX idx_tasks_space ON tasks(space_id);
CREATE INDEX idx_tasks_space_active ON tasks(space_id, is_archived) WHERE is_deleted = false;
CREATE INDEX idx_task_lists_space ON task_lists(space_id) WHERE is_deleted = false;
CREATE INDEX idx_projects_space ON projects(space_id) WHERE is_deleted = false;
CREATE INDEX idx_periodic_tasks_space ON periodic_tasks(space_id) WHERE is_deleted = false;
CREATE INDEX idx_important_dates_space ON important_dates(space_id) WHERE is_deleted = false;
CREATE INDEX idx_task_messages_task ON task_messages(task_id, created_at DESC);
CREATE INDEX idx_pair_invites_code ON pair_invites(invite_code) WHERE status = 'pending';
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX idx_project_subtasks_project ON project_subtasks(project_id) WHERE is_deleted = false;

-- =============================================================
-- RLS 辅助函数
-- =============================================================

CREATE OR REPLACE FUNCTION is_space_member(check_space_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM space_members
    WHERE space_id = check_space_id
    AND user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- =============================================================
-- RLS 策略
-- =============================================================

-- spaces
ALTER TABLE spaces ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read spaces" ON spaces FOR SELECT USING (is_space_member(id));
CREATE POLICY "authenticated can create spaces" ON spaces FOR INSERT WITH CHECK (owner_user_id = auth.uid());
CREATE POLICY "owner can update space" ON spaces FOR UPDATE USING (owner_user_id = auth.uid());

-- space_members
ALTER TABLE space_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read members" ON space_members FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can insert members" ON space_members FOR INSERT WITH CHECK (is_space_member(space_id) OR user_id = auth.uid());
CREATE POLICY "members can update own profile" ON space_members FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "space members can delete members" ON space_members FOR DELETE USING (is_space_member(space_id));

-- pair_invites
ALTER TABLE pair_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "inviter can read own invites" ON pair_invites FOR SELECT USING (inviter_id = auth.uid());
CREATE POLICY "anyone can lookup pending invite" ON pair_invites FOR SELECT USING (status = 'pending' AND expires_at > now());
CREATE POLICY "authenticated can create invite" ON pair_invites FOR INSERT WITH CHECK (inviter_id = auth.uid());
CREATE POLICY "anyone can accept pending invite" ON pair_invites FOR UPDATE USING (status = 'pending' AND expires_at > now());

-- tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read tasks" ON tasks FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create tasks" ON tasks FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update tasks" ON tasks FOR UPDATE USING (is_space_member(space_id));

-- task_messages
ALTER TABLE task_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "can read messages of accessible tasks" ON task_messages FOR SELECT
  USING (EXISTS (SELECT 1 FROM tasks WHERE tasks.id = task_messages.task_id AND is_space_member(tasks.space_id)));
CREATE POLICY "can create messages on accessible tasks" ON task_messages FOR INSERT
  WITH CHECK (sender_id = auth.uid() AND EXISTS (SELECT 1 FROM tasks WHERE tasks.id = task_messages.task_id AND is_space_member(tasks.space_id)));

-- task_lists
ALTER TABLE task_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read lists" ON task_lists FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create lists" ON task_lists FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update lists" ON task_lists FOR UPDATE USING (is_space_member(space_id));

-- projects
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read projects" ON projects FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create projects" ON projects FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update projects" ON projects FOR UPDATE USING (is_space_member(space_id));

-- project_subtasks
ALTER TABLE project_subtasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "can read subtasks of accessible projects" ON project_subtasks FOR SELECT
  USING (EXISTS (SELECT 1 FROM projects WHERE projects.id = project_subtasks.project_id AND is_space_member(projects.space_id)));
CREATE POLICY "can create subtasks on accessible projects" ON project_subtasks FOR INSERT
  WITH CHECK (creator_id = auth.uid() AND EXISTS (SELECT 1 FROM projects WHERE projects.id = project_subtasks.project_id AND is_space_member(projects.space_id)));
CREATE POLICY "can update subtasks of accessible projects" ON project_subtasks FOR UPDATE
  USING (EXISTS (SELECT 1 FROM projects WHERE projects.id = project_subtasks.project_id AND is_space_member(projects.space_id)));

-- periodic_tasks
ALTER TABLE periodic_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read periodic" ON periodic_tasks FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create periodic" ON periodic_tasks FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update periodic" ON periodic_tasks FOR UPDATE USING (is_space_member(space_id));

-- important_dates
ALTER TABLE important_dates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read dates" ON important_dates FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create dates" ON important_dates FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update dates" ON important_dates FOR UPDATE USING (is_space_member(space_id));

-- device_tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own tokens" ON device_tokens FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users create own tokens" ON device_tokens FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users update own tokens" ON device_tokens FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users delete own tokens" ON device_tokens FOR DELETE USING (user_id = auth.uid());

-- =============================================================
-- updated_at 自动更新触发器
-- =============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at BEFORE UPDATE ON spaces FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON space_members FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON task_lists FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON periodic_tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON important_dates FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON device_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- Realtime 启用
-- =============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE spaces;
ALTER PUBLICATION supabase_realtime ADD TABLE space_members;
ALTER PUBLICATION supabase_realtime ADD TABLE tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE task_lists;
ALTER PUBLICATION supabase_realtime ADD TABLE projects;
ALTER PUBLICATION supabase_realtime ADD TABLE project_subtasks;
ALTER PUBLICATION supabase_realtime ADD TABLE periodic_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE task_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE important_dates;
```

- [ ] **Step 4: 在 Supabase SQL Editor 中执行迁移**

打开 Supabase Dashboard → SQL Editor → 粘贴上述 SQL → 执行。
验证：Table Editor 中应看到 11 张表，每张表都有 RLS 图标。

- [ ] **Step 5: 启用 Realtime**

Supabase Dashboard → Database → Replication：确认上述表都在 `supabase_realtime` publication 中。

- [ ] **Step 6: 配置 Storage**

Supabase Dashboard → Storage → 创建 bucket `avatars`（Public bucket）。

- [ ] **Step 7: Commit**

```bash
git add supabase/
git commit -m "feat: 添加 Supabase 数据库迁移脚本（11张表+索引+RLS+Realtime）"
```

---

## Task 2: 集成 Supabase Swift SDK + 创建客户端单例

**Files:**
- Create: `Together/Services/Auth/SupabaseClient.swift`
- Modify: Xcode project (SPM dependency)

- [ ] **Step 1: 添加 Supabase Swift SDK**

在 Xcode 中：File → Add Package Dependencies → 输入：
```
https://github.com/supabase/supabase-swift
```
版本选择: Up to Next Major (2.0.0+)

添加以下 product targets 到 Together app target：
- `Supabase`（主模块，包含 Auth + PostgREST + Realtime + Storage）

- [ ] **Step 2: 创建 Supabase 客户端单例**

```swift
// Together/Services/Auth/SupabaseClient.swift

import Foundation
import Supabase

enum SupabaseClientProvider {
    
    // 从 Supabase Dashboard → Settings → API 获取
    private static let projectURL = URL(string: "https://YOUR_PROJECT_ID.supabase.co")!
    private static let anonKey = "YOUR_ANON_KEY"
    
    static let shared = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey
    )
}
```

> **注意**: 实际项目中 URL 和 Key 应从 Info.plist 或 xcconfig 读取，避免硬编码。anonKey 是公开的（通过 RLS 保护数据），不需要保密。

- [ ] **Step 3: 验证编译**

Build 项目（Cmd+B），确认 `import Supabase` 无编译错误。

- [ ] **Step 4: Commit**

```bash
git add Together/Services/Auth/SupabaseClient.swift Together.xcodeproj/
git commit -m "feat: 集成 supabase-swift SDK 并创建客户端单例"
```

---

## Task 3: SupabaseAuthService（Sign in with Apple）

**Files:**
- Create: `Together/Services/Auth/SupabaseAuthService.swift`

- [ ] **Step 1: 实现 SupabaseAuthService**

```swift
// Together/Services/Auth/SupabaseAuthService.swift

import Foundation
import AuthenticationServices
import Supabase

actor SupabaseAuthService {
    
    private let client = SupabaseClientProvider.shared
    
    /// 当前 Supabase 用户 ID（auth.uid()）
    var currentUserID: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }
    
    /// 是否已登录
    var isSignedIn: Bool {
        get async {
            (try? await client.auth.session) != nil
        }
    }
    
    /// 使用 Apple ID Token 登录 Supabase
    /// - Parameter idToken: ASAuthorizationAppleIDCredential.identityToken 的字符串形式
    /// - Returns: Supabase User ID
    @discardableResult
    func signInWithApple(idToken: String, nonce: String?) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        return session.user.id
    }
    
    /// 登出
    func signOut() async throws {
        try await client.auth.signOut()
    }
    
    /// 尝试恢复已有 session（App 启动时调用）
    func restoreSession() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: 验证编译**

Build 项目，确认无编译错误。

- [ ] **Step 3: Commit**

```bash
git add Together/Services/Auth/SupabaseAuthService.swift
git commit -m "feat: 实现 SupabaseAuthService（Sign in with Apple → Supabase JWT）"
```

---

## Task 4: 补充 Domain Entities 的 Codable 协议

**Files:**
- Modify: `Together/Domain/Entities/TaskList.swift`
- Modify: `Together/Domain/Entities/Project.swift`
- Modify: `Together/Domain/Entities/ProjectSubtask.swift`
- Modify: `Together/Domain/Entities/Space.swift`

- [ ] **Step 1: 为 TaskList 添加 Codable**

在 `TaskList.swift` 的 struct 声明中添加 `Codable`：

```swift
// 原: struct TaskList: Identifiable, Hashable, Sendable {
// 改: 
struct TaskList: Identifiable, Hashable, Sendable, Codable {
```

- [ ] **Step 2: 为 Project 添加 Codable**

```swift
struct Project: Identifiable, Hashable, Sendable, Codable {
```

- [ ] **Step 3: 为 ProjectSubtask 添加 Codable**

```swift
struct ProjectSubtask: Identifiable, Hashable, Sendable, Codable {
```

- [ ] **Step 4: 为 Space 添加 Codable**

```swift
struct Space: Identifiable, Hashable, Sendable, Codable {
```

> 这些 struct 的所有属性类型（UUID, String, Date?, Bool, 枚举）都已是 Codable，Swift 编译器会自动合成编解码方法。

- [ ] **Step 5: 验证编译**

Build 项目，确认无编译错误。所有枚举（SpaceType, SpaceStatus, ProjectStatus, TaskListKind 等）已经是 Codable。

- [ ] **Step 6: Commit**

```bash
git add Together/Domain/Entities/
git commit -m "feat: 为 TaskList/Project/ProjectSubtask/Space 补充 Codable 协议"
```

---

## Task 5: 删除旧的 CloudKit 双人同步代码

**Files:**
- Delete: 14 个文件（~2083 行）

- [ ] **Step 1: 删除 Pair*RecordCodec 文件**

```bash
rm Together/Sync/Codecs/PairTaskRecordCodec.swift
rm Together/Sync/Codecs/PairTaskListRecordCodec.swift
rm Together/Sync/Codecs/PairProjectRecordCodec.swift
rm Together/Sync/Codecs/PairProjectSubtaskRecordCodec.swift
rm Together/Sync/Codecs/PairPeriodicTaskRecordCodec.swift
rm Together/Sync/Codecs/PairSpaceRecordCodec.swift
rm Together/Sync/Codecs/PairMemberProfileRecordCodec.swift
rm Together/Sync/Codecs/PairAvatarAssetRecordCodec.swift
rm Together/Sync/Codecs/PairSyncCodecRegistry.swift
```

- [ ] **Step 2: 删除 PairSync 服务文件**

```bash
rm Together/Sync/PairSyncService.swift
rm Together/Sync/PairSyncPoller.swift
rm Together/Sync/PairSchemaSeeder.swift
rm Together/Sync/CloudKitSubscriptionManager.swift
rm Together/Sync/CloudKitInviteGateway.swift
```

- [ ] **Step 3: 清理 AppContext.swift 中对已删除类的引用**

在 `AppContext.swift` 中，将所有引用已删除类的代码注释或替换为占位符。具体来说：
- 移除 `pairSyncService` 属性（类型 PairSyncService）
- 移除 `pairSyncPoller` 属性（类型 PairSyncPoller）
- 移除 `pairSubscriptionManager` 属性（类型 CloudKitSubscriptionManager）
- 将 `startPairSyncEngineIfNeeded()` 方法体暂时清空（Task 9 中实现替代）
- 将 `teardownPairSync()` 方法体暂时清空（Task 9 中实现替代）
- 移除 `syncAfterMutation()` 中的 `pairSyncPoller?.nudge()` 调用

- [ ] **Step 4: 清理 CloudPairingService.swift 中的 CloudKit 引用**

移除 `CloudPairingService` 中对 `CloudKitInviteGateway` 的依赖。暂时保留文件结构，Task 8 中用 SupabaseInviteGateway 替换。

- [ ] **Step 5: 验证编译**

Build 项目。预期：可能有编译错误在 AppContext 和 CloudPairingService 中，需要在后续 Task 中修复。如果编译错误过多，先用 `// TODO: Supabase migration` 注释标记。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: 删除 CloudKit 双人同步代码（~2083 行，14 个文件）

移除 PairSyncService、8个 PairRecordCodec、PairSyncCodecRegistry、
PairSchemaSeeder、CloudKitSubscriptionManager、CloudKitInviteGateway、
PairSyncPoller。AppContext 中的引用暂时清空，后续 Task 实现替代。"
```

---

## Task 6: SupabaseSyncService — 核心 Push/Pull

**Files:**
- Create: `Together/Sync/SupabaseSyncService.swift`

- [ ] **Step 1: 实现 SupabaseSyncService 核心结构**

```swift
// Together/Sync/SupabaseSyncService.swift

import Foundation
import Supabase
import SwiftData
import os

actor SupabaseSyncService {
    
    private let client = SupabaseClientProvider.shared
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "SupabaseSync")
    private let modelContainer: ModelContainer
    
    private var spaceID: UUID?
    private var myUserID: UUID?
    private var realtimeChannel: RealtimeChannelV2?
    private var lastSyncedAt: Date?
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    /// 配置同步目标
    func configure(spaceID: UUID, myUserID: UUID) {
        self.spaceID = spaceID
        self.myUserID = myUserID
    }
    
    /// 清理资源
    func teardown() async {
        await realtimeChannel?.unsubscribe()
        realtimeChannel = nil
        spaceID = nil
        myUserID = nil
        lastSyncedAt = nil
    }
    
    // MARK: - Push（本地 → Supabase）
    
    /// 推送待同步的本地变更到 Supabase
    func push() async {
        guard let spaceID, let myUserID else { return }
        
        let context = ModelContext(modelContainer)
        
        // 查询 pending 状态的变更
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate {
                $0.spaceID == spaceID &&
                $0.lifecycleStateRawValue == "pending"
            },
            sortBy: [SortDescriptor(\.changedAt)]
        )
        
        guard let changes = try? context.fetch(descriptor), !changes.isEmpty else { return }
        
        for change in changes {
            do {
                change.lifecycleStateRawValue = SyncMutationLifecycleState.sending.rawValue
                change.lastAttemptedAt = Date()
                try context.save()
                
                let entityKind = SyncEntityKind(rawValue: change.entityKindRawValue) ?? .task
                let operation = SyncOperationKind(rawValue: change.operationRawValue) ?? .upsert
                
                if operation == .delete {
                    try await pushDelete(entityKind: entityKind, recordID: change.recordID, context: context)
                } else {
                    try await pushUpsert(entityKind: entityKind, recordID: change.recordID, spaceID: spaceID, context: context)
                }
                
                // 标记成功
                change.lifecycleStateRawValue = SyncMutationLifecycleState.confirmed.rawValue
                change.confirmedAt = Date()
                try context.save()
                
                logger.info("[Push] ✅ \(entityKind.rawValue) \(operation.rawValue) \(change.recordID)")
                
            } catch {
                change.lifecycleStateRawValue = SyncMutationLifecycleState.failed.rawValue
                change.lastError = error.localizedDescription
                try? context.save()
                logger.error("[Push] ❌ \(error.localizedDescription)")
            }
        }
        
        // 清理已确认的变更
        purgeConfirmedChanges(context: context)
    }
    
    // MARK: - Pull（Supabase → 本地）
    
    /// 从 Supabase 拉取最新数据（catch-up 用）
    func catchUp() async {
        guard let spaceID else { return }
        let since = lastSyncedAt ?? Date.distantPast
        
        do {
            try await pullTable("tasks", spaceID: spaceID, since: since, type: Item.self)
            try await pullTable("task_lists", spaceID: spaceID, since: since, type: TaskList.self)
            try await pullTable("projects", spaceID: spaceID, since: since, type: Project.self)
            try await pullTable("periodic_tasks", spaceID: spaceID, since: since, type: PeriodicTask.self)
            // project_subtasks 和 task_messages 通过父表的 space_id 间接拉取
            
            lastSyncedAt = Date()
            logger.info("[CatchUp] ✅ 完成补拉，since: \(since)")
        } catch {
            logger.error("[CatchUp] ❌ \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func pushUpsert(entityKind: SyncEntityKind, recordID: UUID, spaceID: UUID, context: ModelContext) async throws {
        let tableName = entityKind.supabaseTableName
        
        switch entityKind {
        case .task:
            guard let persistent = try? fetchPersistentItem(id: recordID, context: context) else { return }
            let domain = persistent.domainModel()
            try await client.from(tableName).upsert(domain, onConflict: "id").execute()
            
        case .taskList:
            guard let persistent = try? fetchPersistentTaskList(id: recordID, context: context) else { return }
            let domain = persistent.domainModel(taskCount: 0)
            try await client.from(tableName).upsert(domain, onConflict: "id").execute()
            
        case .project:
            guard let persistent = try? fetchPersistentProject(id: recordID, context: context) else { return }
            let domain = persistent.domainModel(taskCount: 0)
            try await client.from(tableName).upsert(domain, onConflict: "id").execute()
            
        case .projectSubtask:
            guard let persistent = try? fetchPersistentProjectSubtask(id: recordID, context: context) else { return }
            let domain = persistent.domainModel()
            try await client.from(tableName).upsert(domain, onConflict: "id").execute()
            
        case .periodicTask:
            guard let persistent = try? fetchPersistentPeriodicTask(id: recordID, context: context) else { return }
            let domain = persistent.domainModel()
            try await client.from(tableName).upsert(domain, onConflict: "id").execute()
            
        case .space:
            guard let persistent = try? fetchPersistentSpace(id: recordID, context: context) else { return }
            let domain = persistent.domainModel
            try await client.from(tableName).upsert(domain, onConflict: "id").execute()
            
        case .memberProfile, .avatarAsset:
            break // space_members 通过配对流程管理，avatarAsset 用 Storage
        }
    }
    
    private func pushDelete(entityKind: SyncEntityKind, recordID: UUID, context: ModelContext) async throws {
        let tableName = entityKind.supabaseTableName
        // 软删除：更新 is_deleted = true
        try await client.from(tableName)
            .update(["is_deleted": true, "deleted_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: recordID.uuidString)
            .execute()
    }
    
    private func pullTable<T: Codable>(_ tableName: String, spaceID: UUID, since: Date, type: T.Type) async throws {
        let rows: [T] = try await client.from(tableName)
            .select()
            .eq("space_id", value: spaceID.uuidString)
            .gte("updated_at", value: ISO8601DateFormatter().string(from: since))
            .execute()
            .value
        
        if !rows.isEmpty {
            let context = ModelContext(modelContainer)
            for row in rows {
                applyRemoteEntity(row, to: context)
            }
            try context.save()
        }
    }
    
    private func applyRemoteEntity<T>(_ entity: T, to context: ModelContext) {
        // 实现：根据 T 的类型，upsert 到对应的 Persistent* 模型
        // 具体实现依赖于每个 Persistent* 模型的 fromDomain() 方法
        // 此处为框架，具体逻辑在集成时补充
    }
    
    private func purgeConfirmedChanges(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistentSyncChange>(
            predicate: #Predicate { $0.lifecycleStateRawValue == "confirmed" }
        )
        if let confirmed = try? context.fetch(descriptor) {
            for change in confirmed {
                context.delete(change)
            }
            try? context.save()
        }
    }
}

// MARK: - SyncEntityKind Supabase 扩展

extension SyncEntityKind {
    var supabaseTableName: String {
        switch self {
        case .task: return "tasks"
        case .taskList: return "task_lists"
        case .project: return "projects"
        case .projectSubtask: return "project_subtasks"
        case .periodicTask: return "periodic_tasks"
        case .space: return "spaces"
        case .memberProfile: return "space_members"
        case .avatarAsset: return "avatars"
        }
    }
}
```

> **注意**: `applyRemoteEntity` 和 `fetchPersistent*` 辅助方法的完整实现需要在集成时根据现有 Persistent 模型的 API 补充。这里提供了框架结构。

- [ ] **Step 2: 验证编译**

Build 项目，确认框架代码无编译错误。

- [ ] **Step 3: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "feat: 实现 SupabaseSyncService 核心 Push/Pull 逻辑"
```

---

## Task 7: SupabaseSyncService — Realtime 订阅

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`

- [ ] **Step 1: 添加 Realtime 订阅方法**

在 `SupabaseSyncService` 中添加以下方法：

```swift
// MARK: - Realtime 订阅

/// 开始监听 Realtime 变更
func startListening() async {
    guard let spaceID else { return }
    
    // Query first, Subscribe second
    await catchUp()
    
    let channel = client.realtimeV2.channel("space-\(spaceID.uuidString)")
    
    // 监听 tasks 表
    let tasksChanges = channel.postgresChange(
        AnyAction.self,
        schema: "public",
        table: "tasks",
        filter: "space_id=eq.\(spaceID.uuidString)"
    )
    
    // 监听 task_lists 表
    let listsChanges = channel.postgresChange(
        AnyAction.self,
        schema: "public",
        table: "task_lists",
        filter: "space_id=eq.\(spaceID.uuidString)"
    )
    
    // 监听 projects 表
    let projectsChanges = channel.postgresChange(
        AnyAction.self,
        schema: "public",
        table: "projects",
        filter: "space_id=eq.\(spaceID.uuidString)"
    )
    
    // 监听 periodic_tasks 表
    let periodicChanges = channel.postgresChange(
        AnyAction.self,
        schema: "public",
        table: "periodic_tasks",
        filter: "space_id=eq.\(spaceID.uuidString)"
    )
    
    // 监听 space_members 表（配对/解绑检测）
    let membersChanges = channel.postgresChange(
        AnyAction.self,
        schema: "public",
        table: "space_members",
        filter: "space_id=eq.\(spaceID.uuidString)"
    )
    
    await channel.subscribe()
    self.realtimeChannel = channel
    
    // 启动监听任务
    Task {
        for await change in tasksChanges {
            await handleRealtimeChange(change, entityKind: .task)
        }
    }
    Task {
        for await change in listsChanges {
            await handleRealtimeChange(change, entityKind: .taskList)
        }
    }
    Task {
        for await change in projectsChanges {
            await handleRealtimeChange(change, entityKind: .project)
        }
    }
    Task {
        for await change in periodicChanges {
            await handleRealtimeChange(change, entityKind: .periodicTask)
        }
    }
    Task {
        for await change in membersChanges {
            await handleMemberChange(change)
        }
    }
    
    logger.info("[Realtime] ✅ 已订阅 space: \(spaceID)")
}

private func handleRealtimeChange(_ change: AnyAction, entityKind: SyncEntityKind) async {
    // 回声过滤：如果是自己触发的变更，跳过
    // Supabase Realtime 的 record 中包含操作者信息
    // 具体过滤逻辑需要检查 record 的 creator_id 或 updated_by
    
    let context = ModelContext(modelContainer)
    
    switch change {
    case .insert(let action):
        if let record = action.record as? [String: Any] {
            await applyRemoteRecord(record, entityKind: entityKind, context: context)
        }
    case .update(let action):
        if let record = action.record as? [String: Any] {
            await applyRemoteRecord(record, entityKind: entityKind, context: context)
        }
    case .delete(let action):
        if let oldRecord = action.oldRecord as? [String: Any],
           let idString = oldRecord["id"] as? String,
           let id = UUID(uuidString: idString) {
            deleteLocalEntity(id: id, entityKind: entityKind, context: context)
        }
    default:
        break
    }
    
    try? context.save()
    lastSyncedAt = Date()
}

private func handleMemberChange(_ change: AnyAction) async {
    // 检测对方加入（配对完成）或成员被删除（解绑）
    // 通过 NotificationCenter 发送事件，让 AppContext 处理
    switch change {
    case .insert:
        NotificationCenter.default.post(name: .pairMemberJoined, object: nil)
    case .delete:
        NotificationCenter.default.post(name: .pairMemberRemoved, object: nil)
    default:
        break
    }
}

private func applyRemoteRecord(_ record: [String: Any], entityKind: SyncEntityKind, context: ModelContext) async {
    // 将 Supabase JSON record 解码为 Domain entity，再写入 Persistent model
    // 具体实现依赖 JSONDecoder + Domain Codable + Persistent.fromDomain()
}

private func deleteLocalEntity(id: UUID, entityKind: SyncEntityKind, context: ModelContext) {
    // 根据 entityKind 查找并删除本地 Persistent model
}
```

- [ ] **Step 2: 添加通知名称扩展**

```swift
// 可以放在 SupabaseSyncService.swift 底部或单独文件

extension Notification.Name {
    static let pairMemberJoined = Notification.Name("pairMemberJoined")
    static let pairMemberRemoved = Notification.Name("pairMemberRemoved")
}
```

- [ ] **Step 3: 验证编译**

Build 项目。

- [ ] **Step 4: Commit**

```bash
git add Together/Sync/SupabaseSyncService.swift
git commit -m "feat: 实现 SupabaseSyncService Realtime 订阅（postgres_changes）"
```

---

## Task 8: SupabaseInviteGateway（配对流程）

**Files:**
- Create: `Together/Services/Pairing/SupabaseInviteGateway.swift`

- [ ] **Step 1: 实现 SupabaseInviteGateway**

```swift
// Together/Services/Pairing/SupabaseInviteGateway.swift

import Foundation
import Supabase

actor SupabaseInviteGateway {
    
    private let client = SupabaseClientProvider.shared
    
    struct InviteRecord: Codable {
        let id: UUID
        let spaceId: UUID
        let inviterId: UUID
        let inviteCode: String
        let status: String
        let acceptedBy: UUID?
        let createdAt: Date
        let expiresAt: Date
        let respondedAt: Date?
        
        enum CodingKeys: String, CodingKey {
            case id
            case spaceId = "space_id"
            case inviterId = "inviter_id"
            case inviteCode = "invite_code"
            case status
            case acceptedBy = "accepted_by"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
            case respondedAt = "responded_at"
        }
    }
    
    /// 创建配对邀请（Device A）
    func createInvite(spaceID: UUID, inviterID: UUID) async throws -> InviteRecord {
        let code = generateNumericCode(digits: 6)
        
        let invite: InviteRecord = try await client.from("pair_invites")
            .insert([
                "space_id": spaceID.uuidString,
                "inviter_id": inviterID.uuidString,
                "invite_code": code,
                "status": "pending"
            ])
            .select()
            .single()
            .execute()
            .value
        
        return invite
    }
    
    /// 通过邀请码查询待处理的邀请（Device B）
    func lookupInvite(code: String) async throws -> InviteRecord? {
        let invites: [InviteRecord] = try await client.from("pair_invites")
            .select()
            .eq("invite_code", value: code)
            .eq("status", value: "pending")
            .gte("expires_at", value: ISO8601DateFormatter().string(from: Date()))
            .execute()
            .value
        
        return invites.first
    }
    
    /// 接受邀请（Device B）
    func acceptInvite(inviteID: UUID, acceptedBy: UUID) async throws -> InviteRecord {
        let invite: InviteRecord = try await client.from("pair_invites")
            .update([
                "status": "accepted",
                "accepted_by": acceptedBy.uuidString,
                "responded_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: inviteID.uuidString)
            .select()
            .single()
            .execute()
            .value
        
        return invite
    }
    
    /// 取消邀请（Device A）
    func cancelInvite(inviteID: UUID) async throws {
        try await client.from("pair_invites")
            .update(["status": "cancelled"])
            .eq("id", value: inviteID.uuidString)
            .execute()
    }
    
    /// 生成 6 位数字邀请码
    private func generateNumericCode(digits: Int) -> String {
        let max = Int(pow(10.0, Double(digits))) - 1
        let code = Int.random(in: 0...max)
        return String(format: "%0\(digits)d", code)
    }
}
```

- [ ] **Step 2: 验证编译**

- [ ] **Step 3: Commit**

```bash
git add Together/Services/Pairing/SupabaseInviteGateway.swift
git commit -m "feat: 实现 SupabaseInviteGateway（6 位码配对 REST 操作）"
```

---

## Task 9: 修改 AppContext + LocalSyncCoordinator 接入 Supabase

**Files:**
- Modify: `Together/App/AppContext.swift:178-383`
- Modify: `Together/Sync/LocalSyncCoordinator.swift:9-40`

- [ ] **Step 1: 在 AppContext 中添加 Supabase 属性**

替换之前删除的 PairSync 属性：

```swift
// AppContext.swift — 属性区域

private var supabaseSyncService: SupabaseSyncService?
private let supabaseAuth = SupabaseAuthService()
private let supabaseInviteGateway = SupabaseInviteGateway()
```

- [ ] **Step 2: 实现 startSupabaseSyncIfNeeded()**

替换原来的 `startPairSyncEngineIfNeeded()`：

```swift
func startSupabaseSyncIfNeeded() async {
    guard let summary = sessionStore.pairSpaceSummary,
          summary.pairSpace.status == .active,
          let sharedSpaceID = summary.sharedSpace?.id else { return }
    
    guard let myUserID = await supabaseAuth.currentUserID else {
        logger.warning("[Supabase] 未登录，跳过双人同步")
        return
    }
    
    let service = SupabaseSyncService(modelContainer: modelContainer)
    service.configure(spaceID: sharedSpaceID, myUserID: myUserID)
    
    // Query first, then Subscribe
    await service.startListening()
    
    self.supabaseSyncService = service
    sessionStore.updateSharedSyncStatus(.syncing)
    
    logger.info("[Supabase] ✅ 双人同步已启动 space: \(sharedSpaceID)")
}
```

- [ ] **Step 3: 实现 teardownSupabaseSync()**

替换原来的 `teardownPairSync()`：

```swift
func teardownSupabaseSync() async {
    await supabaseSyncService?.teardown()
    supabaseSyncService = nil
    sessionStore.updateSharedSyncStatus(.idle)
    logger.info("[Supabase] 双人同步已停止")
}
```

- [ ] **Step 4: 修改 syncAfterMutation() 添加路由**

```swift
func syncAfterMutation(spaceID: UUID) {
    // Solo 路径：CKSyncEngine
    if let soloSpaceID = sessionStore.soloSpace?.id, spaceID == soloSpaceID {
        syncEngineCoordinator.sendChanges(for: spaceID)
    }
    
    // Pair 路径：Supabase
    if let sharedSpaceID = sessionStore.pairSpaceSummary?.sharedSpace?.id,
       spaceID == sharedSpaceID {
        Task {
            await supabaseSyncService?.push()
        }
    }
}
```

- [ ] **Step 5: 修改 performPostLaunchWorkIfNeeded()**

替换对 PairSchemaSeeder 和 startPairSyncEngineIfNeeded 的调用：

```swift
// 原来的：
// await PairSchemaSeeder.seedIfNeeded(...)  ← 删除
// await startPairSyncEngineIfNeeded()  ← 替换

// 新的：
// 恢复 Supabase session
await supabaseAuth.restoreSession()
// 启动双人同步（如果已配对）
await startSupabaseSyncIfNeeded()
```

- [ ] **Step 6: 修改 LocalSyncCoordinator 支持双路由**

在 `LocalSyncCoordinator.swift` 中，添加第二个回调用于 Supabase 路径：

```swift
// LocalSyncCoordinator.swift

private var onChangeRecorded: (@Sendable (SyncChange) async -> Void)?
private var onSharedChangeRecorded: (@Sendable (SyncChange) async -> Void)?  // 新增

func setOnSharedChangeRecorded(_ callback: @escaping @Sendable (SyncChange) async -> Void) {
    onSharedChangeRecorded = callback
}

func recordLocalChange(_ change: SyncChange) async {
    // ... 现有的持久化逻辑 ...
    
    // 转发给 CKSyncEngine（Solo）
    await onChangeRecorded?(change)
    
    // 转发给 SupabaseSyncService（Shared）— 新增
    await onSharedChangeRecorded?(change)
}
```

- [ ] **Step 7: 验证编译并修复所有引用错误**

Build 项目，逐一修复编译错误。

- [ ] **Step 8: Commit**

```bash
git add Together/App/AppContext.swift Together/Sync/LocalSyncCoordinator.swift
git commit -m "feat: AppContext 和 LocalSyncCoordinator 接入 Supabase 同步路由"
```

---

## Task 10: 已读状态实现

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Modify: 任务详情 UI（读取时标记已读）

- [ ] **Step 1: 在 SupabaseSyncService 中添加标记已读方法**

```swift
// SupabaseSyncService.swift 中添加

/// 标记任务为已读
func markTaskAsRead(taskID: UUID) async {
    do {
        try await client.from("tasks")
            .update([
                "is_read_by_partner": true,
                "read_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: taskID.uuidString)
            .execute()
    } catch {
        logger.error("[ReadStatus] ❌ \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: 在任务详情页打开时调用标记已读**

在任务详情 Sheet（如 `HomeItemDetailSheet`）的 `onAppear` 中：

```swift
.onAppear {
    // 如果是对方创建的任务且未读，标记为已读
    if item.creatorID != myUserID && !item.isReadByPartner {
        Task {
            await appContext.supabaseSyncService?.markTaskAsRead(taskID: item.id)
        }
    }
}
```

> **注意**: 需要在 PersistentItem 和 Item domain model 中添加 `isReadByPartner` 和 `readAt` 字段。

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: 实现任务已读状态（is_read_by_partner + 自动标记）"
```

---

## Task 11: APNs 推送 — Device Token 注册

**Files:**
- Create: `Together/Services/Push/DeviceTokenService.swift`
- Modify: `Together/App/AppDelegate.swift`

- [ ] **Step 1: 实现 DeviceTokenService**

```swift
// Together/Services/Push/DeviceTokenService.swift

import Foundation
import Supabase

actor DeviceTokenService {
    
    private let client = SupabaseClientProvider.shared
    
    /// 注册 APNs device token 到 Supabase
    func registerToken(_ tokenData: Data) async {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
        
        guard let userID = try? await client.auth.session.user.id else { return }
        
        do {
            try await client.from("device_tokens")
                .upsert([
                    "user_id": userID.uuidString,
                    "token": tokenString,
                    "platform": "ios"
                ], onConflict: "user_id,token")
                .execute()
        } catch {
            print("[DeviceToken] 注册失败: \(error)")
        }
    }
    
    /// 注销 token（登出时调用）
    func unregisterToken(_ tokenData: Data) async {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
        
        do {
            try await client.from("device_tokens")
                .delete()
                .eq("token", value: tokenString)
                .execute()
        } catch {
            print("[DeviceToken] 注销失败: \(error)")
        }
    }
}
```

- [ ] **Step 2: 在 AppDelegate 中注册推送**

```swift
// AppDelegate.swift 中添加

import UserNotifications

// 在 application(_:didFinishLaunchingWithOptions:) 中添加:
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
    if granted {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}

// 添加代理方法:
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task {
        await DeviceTokenService().registerToken(deviceToken)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Together/Services/Push/DeviceTokenService.swift Together/App/AppDelegate.swift
git commit -m "feat: 实现 APNs device token 注册到 Supabase"
```

---

## Task 12: APNs 推送 — Edge Function

**Files:**
- Create: `supabase/functions/send-push-notification/index.ts`

- [ ] **Step 1: 实现 Edge Function**

```typescript
// supabase/functions/send-push-notification/index.ts

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const apnsKeyId = Deno.env.get("APNS_KEY_ID")!;
const apnsTeamId = Deno.env.get("APNS_TEAM_ID")!;
const apnsPrivateKey = Deno.env.get("APNS_PRIVATE_KEY")!;
const appBundleId = "com.pigdog.Together";

const supabase = createClient(supabaseUrl, serviceRoleKey);

Deno.serve(async (req: Request) => {
  const payload = await req.json();
  const { type, table, record, old_record } = payload;

  // 确定操作者 ID（不给操作者自己发推送）
  const actorId = record?.creator_id || record?.sender_id;
  if (!actorId) return new Response("No actor", { status: 200 });

  // 确定 space_id
  let spaceId = record?.space_id;
  if (!spaceId && table === "task_messages") {
    // task_messages 没有直接的 space_id，需要通过 task 查询
    const { data: task } = await supabase
      .from("tasks")
      .select("space_id")
      .eq("id", record.task_id)
      .single();
    spaceId = task?.space_id;
  }
  if (!spaceId) return new Response("No space", { status: 200 });

  // 查找对方的 device tokens
  const { data: members } = await supabase
    .from("space_members")
    .select("user_id")
    .eq("space_id", spaceId)
    .neq("user_id", actorId);

  if (!members || members.length === 0) {
    return new Response("No partner", { status: 200 });
  }

  const partnerId = members[0].user_id;

  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", partnerId);

  if (!tokens || tokens.length === 0) {
    return new Response("No tokens", { status: 200 });
  }

  // 查找操作者的昵称
  const { data: actor } = await supabase
    .from("space_members")
    .select("display_name")
    .eq("space_id", spaceId)
    .eq("user_id", actorId)
    .single();

  const actorName = actor?.display_name || "伴侣";

  // 构造推送内容
  const notification = buildNotification(table, type, record, actorName);
  if (!notification) return new Response("Skip", { status: 200 });

  // 发送 APNs（简化版，实际需要 JWT 签名）
  for (const { token } of tokens) {
    await sendAPNs(token, notification);
  }

  return new Response(JSON.stringify({ sent: tokens.length }), {
    headers: { "Content-Type": "application/json" },
  });
});

function buildNotification(
  table: string,
  type: string,
  record: Record<string, unknown>,
  actorName: string
): { title: string; body: string } | null {
  if (table === "tasks" && type === "INSERT") {
    if (record.assignee_mode === "partner") {
      return { title: "新任务", body: `${actorName} 给你分配了「${record.title}」` };
    }
    return null;
  }
  if (table === "tasks" && type === "UPDATE") {
    if (record.status === "completed") {
      return { title: "任务完成", body: `${actorName} 完成了「${record.title}」` };
    }
    if (record.is_read_by_partner === true) {
      return null; // 已读不发推送
    }
    return null;
  }
  if (table === "task_messages") {
    if (record.type === "nudge") {
      return { title: "催一下", body: `${actorName} 催你完成任务` };
    }
    if (record.type === "comment") {
      return { title: "留言", body: `${actorName} 给你留了言` };
    }
    if (record.type === "rps_result") {
      return { title: "✊✌️✋", body: `${actorName} 发起了石头剪刀布！` };
    }
  }
  return null;
}

async function sendAPNs(
  deviceToken: string,
  notification: { title: string; body: string }
) {
  // APNs HTTP/2 推送
  // 需要使用 .p8 私钥生成 JWT token
  // 实际实现需要 jose 库做 JWT 签名
  const apnsPayload = {
    aps: {
      alert: { title: notification.title, body: notification.body },
      sound: "default",
      badge: 1,
    },
  };

  const url = `https://api.push.apple.com/3/device/${deviceToken}`;

  try {
    // JWT token 生成和 HTTP/2 请求的完整实现
    // 需要在部署时补充 JWT 签名逻辑
    console.log(`[APNs] Sending to ${deviceToken.substring(0, 8)}...`);
  } catch (error) {
    console.error(`[APNs] Error: ${error}`);
  }
}
```

> **注意**: APNs JWT 签名的完整实现需要使用 jose 库。部署时需要配置 Supabase Secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`。

- [ ] **Step 2: 配置 Database Webhook**

在 Supabase Dashboard → Database → Webhooks：
- 创建 webhook，触发表: `tasks`, `task_messages`
- 触发事件: INSERT, UPDATE
- 目标: Edge Function `send-push-notification`

- [ ] **Step 3: 部署 Edge Function**

可通过 Supabase MCP 工具或 CLI 部署：

```bash
# 如果安装了 Supabase CLI:
supabase functions deploy send-push-notification
```

- [ ] **Step 4: 配置 Secrets**

```bash
supabase secrets set APNS_KEY_ID=YOUR_KEY_ID
supabase secrets set APNS_TEAM_ID=YOUR_TEAM_ID
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXXX.p8)"
```

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/
git commit -m "feat: 实现 APNs 推送 Edge Function（send-push-notification）"
```

---

## Task 13: 集成测试 + 修复编译

**Files:**
- 所有已修改文件

- [ ] **Step 1: 完整 Build 项目**

Cmd+B，修复所有剩余编译错误。常见问题：
- 未导入的模块（`import Supabase`）
- 已删除类的残留引用
- 属性访问权限（`private` → `internal`）

- [ ] **Step 2: 真机测试 — Sign in with Apple**

1. 在真机上运行 App
2. 确认 Sign in with Apple 弹窗出现
3. 授权后确认 Supabase Dashboard → Authentication → Users 中出现新用户

- [ ] **Step 3: 真机测试 — 配对流程**

1. 设备 A 创建邀请码
2. 设备 B 输入邀请码
3. 确认两台设备都进入双人模式
4. 确认 Supabase Dashboard → Table Editor → space_members 中有两条记录

- [ ] **Step 4: 真机测试 — 实时同步**

1. 设备 A 创建任务
2. 确认设备 B 毫秒级收到
3. 设备 B 修改任务
4. 确认设备 A 实时更新

- [ ] **Step 5: 真机测试 — APNs 推送**

1. 设备 A 杀掉 App
2. 设备 B 创建任务并指派给对方
3. 确认设备 A 收到系统推送通知

- [ ] **Step 6: 真机测试 — 数据隔离**

1. 在单人模式创建任务
2. 确认 Supabase Dashboard 中没有该任务（只走 CKSyncEngine）
3. 切换到双人模式创建任务
4. 确认 Supabase Dashboard 中有该任务

- [ ] **Step 7: 真机测试 — 解绑**

1. 任一设备点击解除配对
2. 确认双方都回到单人模式
3. 确认 Supabase 中 spaces.status = 'archived'，所有业务数据 is_deleted = true

- [ ] **Step 8: 真机测试 — 重新配对**

1. 解绑后重新创建邀请码
2. 对方重新输入
3. 确认从空白共享空间开始

- [ ] **Step 9: Final Commit**

```bash
git add -A
git commit -m "feat: Phase 1 完成 — Supabase 双人同步基础设施

- Supabase Auth (Sign in with Apple)
- SupabaseSyncService (Push/Pull/Realtime)
- SupabaseInviteGateway (6位码配对)
- APNs 推送 (Edge Function + Device Token)
- 已读状态
- 删除 CloudKit 双人同步代码 (~2083 行)
- 数据隔离（个人→CKSyncEngine / 共享→Supabase）"
```

---

## 依赖关系图

```
Task 1 (DB Schema)
  ↓
Task 2 (SDK 集成)
  ↓
Task 3 (Auth Service)  →  Task 4 (Codable 补充)
  ↓                              ↓
Task 5 (删除旧代码)  ←──────────┘
  ↓
Task 6 (Sync Push/Pull)
  ↓
Task 7 (Realtime 订阅)
  ↓
Task 8 (Invite Gateway)
  ↓
Task 9 (AppContext 集成)  →  Task 10 (已读状态)
  ↓
Task 11 (Device Token)  →  Task 12 (Edge Function)
  ↓
Task 13 (集成测试)
```
