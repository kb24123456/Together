# Solo Recovery + Pro Multi-Device Sync Design

- **Date**: 2026-04-29
- **Status**: Self-reviewed draft for user review
- **Scope**: 单人模式稳定换机恢复、Pro 多端同步边界、Supabase 权威源改造
- **Upstream context**:
  - `PRODUCT_SPEC.md`: V1 以单人 Todo 为核心
  - `DEVELOPMENT_GUIDELINES.md`: 当前使用 SwiftData，本地数据与未来 CloudKit/Supabase 边界需清晰
  - `docs/superpowers/specs/2026-04-16-supabase-pair-sync-design.md`: 旧边界为「单人 CloudKit，双人 Supabase」，本设计修正该边界

## Goal

让用户在单人模式下获得稳定的数据安全承诺：

1. 删除 App、重装、换到另一台 iPhone 后，只要使用同一个 Apple/Supabase 身份登录，应能稳定拉回单人任务、清单、项目等核心数据。
2. 第二台 iPhone 登录同一 Apple ID 时，产品上按「换机恢复」处理，不要求 Pro。
3. iPad 和 Mac 登录并同步同一账号数据时，属于「多端同步」，需要 Pro。
4. 本地 SwiftData 继续作为离线缓存和 UI 性能层，不再作为唯一权威存储。
5. Supabase 成为单人任务数据的云端权威源；CloudKit 只作为可选迁移/兜底层，不再承担唯一恢复责任。

## Non-Goals

- 不在本设计里实现 UI。
- 不重新设计付费墙。
- 不承诺恢复已经没有本地副本且从未成功上传到任何云端的数据。
- 不把多人工作组做进当前版本。
- 不引入新的后端平台；继续使用现有 Supabase 项目。
- 不要求第一阶段支持 Android/Web。

## Product Decisions

| Decision | Result |
| --- | --- |
| 单人数据权威源 | Supabase |
| 本地数据库定位 | SwiftData 离线缓存 |
| 同一 Apple ID 的第二台 iPhone | 换机恢复，允许拉回数据 |
| iPad / Mac 同账号同步 | Pro 功能 |
| 同时多台 iPhone 活跃同步 | 第一阶段不拦截，避免误伤换机恢复；后续再基于活跃设备策略决定是否纳入 Pro |
| CloudKit | 可选兜底/迁移层，不作为唯一数据安全承诺 |
| 登录身份锚点 | Supabase `auth.uid()` |
| 用户可见 Space 概念 | V1 不暴露，内部仍使用 `single` space |

## Architecture

```
┌───────────────────────────────────────────────┐
│ Together Client                                │
│                                               │
│ SwiftData local cache                          │
│ - fast launch                                  │
│ - offline read/write                           │
│ - UI query source                              │
│                                               │
│ Local Outbox / PersistentSyncChange            │
│ - pending / sending / synced / failed          │
│ - retry with backoff                           │
│ - per entity mutation lifecycle                │
│                                               │
│ SupabaseSoloSyncService                        │
│ - push local mutations                         │
│ - pull remote deltas                           │
│ - hydrate empty install                        │
│ - apply conflict policy                        │
└───────────────────────┬───────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────┐
│ Supabase                                      │
│                                               │
│ auth.users                                    │
│ spaces / space_members                        │
│ tasks / task_lists / projects / ...           │
│ device_installations                          │
│ RLS by auth.uid() and space membership         │
└───────────────────────────────────────────────┘
```

Core rule: local writes may appear immediately, but the product only treats data as safely recoverable after the mutation is confirmed by Supabase.

Sync cursors are local client state, not a required Supabase table for MVP. If later server-side diagnostics need global auditability, add a separate `sync_events` table as a follow-up.

## Data Model

The existing Supabase project already contains these relevant tables:

- `spaces`
- `space_members`
- `tasks`
- `task_lists`
- `projects`
- `project_subtasks`
- `periodic_tasks`
- `important_dates`
- `device_tokens`
- `premium_grants`
- `user_profiles`

The implementation should extend this schema instead of creating a parallel solo backend.

### Spaces

Use the existing `spaces` table for both solo and pair modes.

Required semantics:

- `spaces.type = 'single'` for the user's personal workspace.
- One active single space per `owner_user_id`.
- `spaces.owner_user_id = auth.uid()` for single spaces.
- `space_members` contains the owner as a member to allow shared membership-based queries.

Recommended constraints/indexes:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_spaces_one_active_single_per_owner
ON spaces(owner_user_id)
WHERE type = 'single' AND status = 'active';
```

Before adding this index, the migration must run a preflight query for duplicate active single spaces per owner and merge or archive duplicates. Otherwise the index creation can fail on historical test data.

### Tasks and Related Entities

For solo records:

- `space_id` points to the user's single space.
- `creator_supabase_user_id` or equivalent auth-scoped column must use `auth.uid()`.
- Existing local UUIDs can remain as primary keys to support idempotent upsert from clients.
- Deletes remain soft deletes with `is_deleted` / `deleted_at`.
- `updated_at` is the primary high-water mark for incremental pull.

The first implementation should cover the data needed to make the current solo Todo product safe:

1. `tasks`
2. `task_lists`
3. `projects`
4. `project_subtasks`
5. `periodic_tasks` if the UI already allows users to create recurring tasks
6. `important_dates` if the UI treats them as user-owned solo data outside pair mode

Follow-up entities that are not required for the current solo task recovery promise:

1. `task_templates`
2. task messages if kept for solo mode

The implementation plan must inspect which solo-facing repositories are currently reachable from production UI before deciding the exact milestone split. The product promise is not "tasks table only"; it is user-owned solo productivity data that the current app exposes.

### Device Installations

Add a dedicated table instead of overloading APNs tokens:

```sql
CREATE TABLE device_installations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  platform text NOT NULL CHECK (platform IN ('iphone', 'ipad', 'mac')),
  device_name text,
  app_version text,
  build_number text,
  is_active boolean NOT NULL DEFAULT true,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  last_sync_at timestamptz,
  UNIQUE(user_id, installation_id)
);
```

Purpose:

- distinguish iPhone restore from iPad/Mac multi-device sync;
- observe active devices;
- support future Pro enforcement for simultaneous multi-iPhone active sync;
- debug user reports without reading private CloudKit data.

## Access Control

### RLS Principles

Solo data:

- user can read/write rows in spaces they own or belong to;
- for single spaces, `owner_user_id = auth.uid()` is mandatory;
- client cannot write data into another user's single space.

Pair data:

- keep membership-based RLS from existing Supabase pair sync.

Premium:

- `premium_grants` remains read-only to the user.
- Pro status is evaluated client-side from RevenueCat + Supabase grants.
- Server RLS may additionally restrict iPad/Mac access in a later phase, but MVP can enforce Pro in the client sync gate first.

## Sync Behavior

### Startup

Startup must branch before normal delta sync:

1. Resolve Supabase session.
2. Ensure local user profile is anchored to `auth.uid()`.
3. Ensure single space exists in Supabase.
4. Register or update `device_installations`.
5. Determine sync capability:
   - iPhone: allow restore pull.
   - iPad/Mac: require Pro before pulling data.
6. Classify local store state:
   - empty fresh install;
   - existing local data with no Supabase baseline;
   - existing local data with an established Supabase baseline.
7. Execute the correct branch:
   - fresh install: full pull from Supabase, then render restored cache;
   - existing local data with no baseline: fetch remote snapshot, merge local and remote records, push local winners, then write baseline;
   - established baseline: show local cache, push pending outbox, then pull deltas.

This ordering prevents a pre-migration local store from being treated as stale just because the Supabase baseline does not exist yet.

### Fresh Install / New iPhone Restore

For an empty local store on iPhone:

1. Login with Apple and Supabase.
2. Fetch active single space.
3. Full pull all non-deleted solo records.
4. Rebuild SwiftData cache.
5. Mark `lastPulledAt`.
6. Show sync status as complete.

This path is not Pro-gated.

### Existing Local Store Bootstrap

For a non-empty local store that has never been confirmed against Supabase:

1. Login with Apple and Supabase.
2. Ensure active single space.
3. Fetch the remote snapshot for the active single space without treating missing remote rows as deletions.
4. Merge local and remote rows by stable UUID:
   - if only local exists, push local;
   - if only remote exists, apply remote locally;
   - if both exist, compare `updated_at` / `deleted_at` and keep the newer winner;
   - if local has pending edits, do not overwrite it with older remote data.
5. Push local winners using idempotent upsert.
6. Only after remote confirmation, write local Supabase baseline metadata.
7. Mark local records as synced when remote confirmation is available.

This is the critical path for existing TestFlight users who still have data on-device.

### Local Mutation

1. User creates/updates/deletes task locally.
2. Repository writes SwiftData.
3. Repository records outbox mutation.
4. `SupabaseSoloSyncService` pushes mutation with idempotent upsert.
5. On success, mutation becomes synced.
6. On failure, mutation remains pending/failed and is retried.

### Pull

Pull uses high-water marks:

- local `lastPulledAt` per entity type;
- remote rows where `updated_at > lastPulledAt`;
- include soft-deleted rows so local cache can remove/archive them.

For the first milestone, a conservative full pull for the active single space is acceptable on fresh install because solo task volume is expected to be small.

### Conflict Policy

MVP policy:

- last write wins by server `updated_at`;
- local pending mutation should not be overwritten by older remote data;
- deletes win over stale updates when `deleted_at` is newer.

Future policy:

- add integer `revision`;
- record `updated_by_installation_id`;
- surface rare conflicts only for notes/long text if needed.

## Pro Gate

### Free Users

Allowed:

- use the app on iPhone;
- delete/reinstall and recover data on iPhone;
- move to another iPhone with same account;
- normal iPhone push/pull needed to make the recovery promise real.

Not allowed:

- iPad sync;
- Mac sync;
- future active multi-device continuous sync beyond iPhone restore rules.

### Pro Users

Allowed:

- iPhone + iPad + Mac active sync;
- background delta sync;
- Realtime or frequent polling if enabled;
- future richer backup controls.

### Device Rule

First milestone:

```text
platform == iphone  -> allow solo restore/sync
platform == ipad    -> require Pro
platform == mac     -> require Pro
```

Second milestone:

- track simultaneous active iPhones;
- if more than one iPhone is active within a defined window, decide whether to keep free or require Pro.

The user-approved product rule for now: second iPhone is treated as restore, not Pro-only multi-device sync.

Implementation consequence: the first milestone intentionally allows more than one iPhone to sync. This is acceptable because blocking a second iPhone would make reliable restore impossible and would be hard to distinguish from a legitimate device replacement.

## Migration Strategy

### Existing Users with Local Data

On first launch after migration:

1. Resolve Supabase auth.
2. Create/ensure single space.
3. Scan local SwiftData solo records.
4. Fetch remote snapshot for that single space.
5. Merge by stable UUID and timestamp rules.
6. Upload local winners to Supabase using their existing UUIDs.
7. Mark local sync baseline only after successful remote confirmation.
8. Keep CloudKit records untouched.

### Existing CloudKit Records

If CloudKit has records and SwiftData is empty:

1. Attempt CloudKit import as a best-effort one-time migration.
2. Convert imported records into SwiftData.
3. Upload imported records to Supabase.
4. After Supabase confirms, Supabase becomes the source of truth.

If neither local SwiftData nor CloudKit contains a record, it cannot be recovered.

### Migration Baseline

Add local metadata to distinguish "never synced to Supabase" from "synced and currently empty":

- `soloSupabaseMigrationCompletedAt`
- `soloSupabaseLastPulledAt` per entity or per space
- `soloSupabaseLastPushedAt`
- local app build that performed the migration

Without this baseline, an empty remote result can be misread as authoritative deletion.

## Observability

Add a diagnostic surface available in debug/TestFlight builds:

- Supabase auth user ID.
- local single space ID.
- remote single space ID.
- local task count.
- remote task count.
- pending outbox count by state.
- last successful push timestamp.
- last successful pull timestamp.
- last sync error code/message.
- current platform and Pro gate decision.

This is required because silent sync failures create data-loss perception.

## Error Handling

| Case | Behavior |
| --- | --- |
| No Supabase session | keep local mode, show sync unavailable state |
| Network unavailable | keep local writes in outbox, retry |
| RLS denied | log auth/space mismatch, do not discard local mutation |
| Pro required on iPad/Mac | block pull/push and show upgrade path |
| Fresh install pull fails | keep empty local state but show recoverable sync error |
| Push fails before App deletion | warn that data is not yet safely backed up |

## Testing Strategy

Unit tests:

- local mutation creates outbox row;
- solo rows map to Supabase DTOs with `auth.uid()` identity fields;
- remote rows apply into SwiftData idempotently;
- soft delete applies correctly;
- last-write-wins conflict policy;
- Pro gate allows iPhone restore and blocks iPad/Mac when free.

Integration tests:

- Supabase RLS permits owner CRUD for single space;
- RLS denies writing another user's single space;
- fresh install full pull rebuilds local cache;
- local data migration uploads existing SwiftData rows.

Manual TestFlight tests:

1. iPhone A creates tasks, wait for "synced".
2. Delete App on iPhone A, reinstall, verify tasks return.
3. iPhone B same Apple ID logs in, verify tasks return.
4. iPad same account without Pro, verify sync is gated.
5. Grant Pro, verify iPad sync works.
6. Mac same account without Pro, verify sync is gated.
7. Grant Pro, verify Mac sync works.

## Rollout Plan

1. Add Supabase schema extensions and RLS for solo spaces and device installations.
2. Add DTOs and Supabase solo sync service behind a local feature flag.
3. Add sync diagnostics before enabling destructive reinstall tests.
4. Add one-time local-to-Supabase bootstrap migration for existing local data.
5. Add fresh install full pull.
6. Add normal iPhone push/pull and retry handling.
7. Enable iPhone restore path in TestFlight only after diagnostics show confirmed remote writes.
8. Add iPad/Mac Pro gate when those targets are introduced.
9. Keep CloudKit import path temporarily.
10. Retire CloudKit as single-source recovery after confidence window.

## Risks

- Current Supabase tables were originally shaped for pair sync, so solo usage must avoid leaking pair-only fields into product logic.
- Existing rows may contain older local UUID identity fields; migration must consistently anchor new writes to Supabase `auth.uid()`.
- If users delete the app before first Supabase upload completes, data can still be lost. The UI must expose sync safety state.
- iPad/Mac product gating needs platform-specific implementation after those targets exist.
- If diagnostics are added after sync rollout instead of before, future TestFlight failures will remain hard to distinguish from data loss.

## Acceptance Criteria

- A solo task created on iPhone appears in Supabase `tasks` under the user's active single space.
- Existing on-device solo records are uploaded to Supabase before the app marks migration complete.
- Deleting and reinstalling the iPhone app restores the task from Supabase.
- A second iPhone with the same account restores the same data without Pro.
- Free iPad/Mac sync is blocked by `PremiumGate`.
- Pro iPad/Mac sync is allowed.
- Sync diagnostics can prove whether a task is local-only, pending, synced, or failed.
