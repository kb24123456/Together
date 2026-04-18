# 头像跨设备同步 — 设计

## 背景

配对成功后，双方设备看不到对方的头像；自己修改头像后对端也收不到。根因：
1. Supabase 端 `space_members` 只存 `avatar_url` (本地文件名) + `avatar_version`，没有 `avatar_asset_id` / `avatar_system_name`。
2. `pushUpsert(.avatarAsset)` 是 no-op，头像字节**从未真正上传过云端**。
3. `pullSpaceMembers` 即使读到字段也没下载字节到本地缓存目录。
4. `acceptInviteByCode` 成功后缺少"首次 catchUp 拉取伴侣已有头像"的动作。

设计目标：一次性修完上述 4 处漏洞，让头像在配对后首次可见、修改后自动同步，且仅配对双方可见。

## 1. 范围

- 覆盖"仅两台配对设备"的同步场景（solo 模式不受影响，继续走 CloudKit）。
- 头像既可以是用户相册中的照片（JPEG），也可以是 SF Symbol 名称（不上传字节）。
- 不引入"供第三方访问"或"集中审核"的能力。

## 2. 数据模型

### 2.1 Supabase 端（migration 011）

- `space_members.avatar_asset_id text NULL` — 头像资产 ID（与 `PersistentUserProfile.avatarAssetID` 对齐）。
- `space_members.avatar_system_name text NULL` — SF Symbol 名称（当用户选 SF Symbol 作为头像时）。
- `space_members.avatar_url` 的语义收窄为"Storage 签名 URL"（之前是本地文件名，语义含糊）。新旧字段含义变更**通过迁移覆盖旧值**（现有 NULL 或本地文件名 string 都清掉）。
- 创建 Storage bucket `avatars`（private）+ 允许 anon INSERT/UPDATE 的 RLS policy（不允许 anon SELECT —— 依赖签名 URL 下载）。

### 2.2 客户端 `PersistentPairMembership`

新增字段（SwiftData 增量迁移，可为空）：
- `avatarAssetID: String?`
- `avatarSystemName: String?`

原有 `avatarPhotoFileName` 字段语义改为"Storage 签名 URL"（pull 存的就是这个 URL），命名保持不变避免迁移风暴。

### 2.3 Storage 路径约定

```
avatars/{space_id}/{user_id}/{avatar_version}.jpg
```

- `space_id` 确保路径按空间隔离（便于后续加 RLS）。
- `avatar_version` 放在文件名里 → 每次改头像生成新路径，天然支持版本化 + 缓存失效。

## 3. 同步流程

### 3.1 Push（本机改头像 → Supabase）

`EditProfileViewModel` 保存后：
1. 本地写入 `PersistentUserProfile` + `LocalUserAvatarMediaStore`（现状已有，不动）
2. `AppContext.syncProfileToPartner` 记录两条 SyncChange：
   - `.avatarAsset`（如果带照片）
   - `.memberProfile`
3. Push worker 顺序处理：
   - **先**处理 `.avatarAsset`：读取本地字节 → 上传 `avatars/{space_id}/{user_id}/{version}.jpg` → 生成 1 年 signed URL → 暂存到 `pendingAvatarURL`
   - **再**处理 `.memberProfile`：把 `pendingAvatarURL`（若有）连同 `avatar_asset_id` / `avatar_system_name` / `avatar_version` / `display_name` upsert 到 `space_members`

顺序保证：先有 URL 才写 members 表；若 URL 上传失败，memberProfile 退回到 `avatar_asset_id = null, avatar_url = null, avatar_system_name = systemName` 这种仅 symbol 的状态。

### 3.2 Pull（伴侣改头像 → 本机）

`pullSpaceMembers` 读取 `space_members` 后：
1. 若远端 `avatar_version > 本地 avatarVersion`：
   - 将 `avatar_url` / `avatar_asset_id` / `avatar_system_name` / `avatar_version` 写入 `PersistentPairMembership`
   - 如果 `avatar_url` 非空，异步下载字节到 `LocalUserAvatarMediaStore`（目的文件 `asset-{remoteAssetID}.jpg`）
   - 下载失败不阻塞其他成员处理，只记日志
2. 若远端 version <= 本地 version，跳过（dedup）

### 3.3 初次配对（Bug 1 的关键）

`CloudPairingService.acceptInviteByCode` / `checkAndFinalizeIfAccepted` 成功 return 前，新增一次立即 `supabaseSyncService.catchUp()`，确保进入主界面时伴侣已有头像就已拉到本地。

### 3.4 Realtime

已有的 `handleMemberChange` 在 `space_members UPDATE` 时触发 `catchUp` + post `.supabaseRealtimeChanged`，不需要改动——增强后的 `pullSpaceMembers` 会自动下载新字节。

## 4. 隐私与安全

- Bucket `avatars` 私有，web 公开访问禁止。
- 读取只能通过 signed URL。URL 随机不可猜测，有效期 1 年。
- 更换头像时生成新路径（含新 `avatar_version`）+ 新 signed URL；旧文件留在 bucket（后续可清理策略），旧 URL 停止被引用。
- RLS 当前仅限制 SELECT（必须走 signed URL），INSERT / UPDATE 对 anon 开放（项目整体走 anon key + 本地 UUID 的认证模式；已在 memory `project_identity_model.md` 里记录）。后续如果统一身份模型，可以再收紧。

## 5. UI / UX

不改现有 UI。验证指标：
- A 设备改头像后 10 秒内 B 设备主页伴侣头像 strip 刷新。
- 新配对后立即进入主页时已显示伴侣现有头像（而非默认图）。
- 离线改头像 → 联网后自动 push 成功。

## 6. 压缩策略

保持现有的 512×512 JPEG @ 0.88（~80-120 KB），业界主流 app（WhatsApp / Telegram / Signal）均在同一范围内。新增 300 KB 软上限 guard（`os.Logger.warning`），触发则记日志但仍发送。

## 7. 错误处理

- Storage 上传失败：重试 1 次，仍失败则记日志、memberProfile 退回到无 URL 状态（伴侣看到 SF Symbol fallback）。
- Signed URL 过期（1 年外场景）：pull 侧 HTTP 下载 403 → 只记日志，触发一次 realtime catchUp 等下次对方 push。
- 本地字节读取失败（文件被清）：跳过 avatarAsset push，仅 push memberProfile 的 systemName fallback。

## 8. 测试

- `AvatarPushDTOTests`：`SpaceMemberUpdateDTO` 序列化新字段正确
- `AvatarUploadTests`：mock Supabase Storage，验证上传路径 + signed URL 写回
- `SpaceMemberPullAvatarTests`：mock pull 路径，版本号 > 本地时下载字节，版本号 ≤ 本地时跳过
- `PairSpaceSummaryResolverAvatarTests`：`PersistentPairMembership.avatarAssetID` 正确传到 `User.avatarAssetID`
- `AcceptInviteTriggersCatchUpTests`：验证 pair 成功后有 catchUp 调用
- E2E：双真机验证 3 场景（首次 pair 即显示 / 改头像对端收到 / SF Symbol 头像同步）
