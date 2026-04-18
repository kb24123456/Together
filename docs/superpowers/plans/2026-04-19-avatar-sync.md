# 头像跨设备同步 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two avatar sync bugs (首次 pair 看不到、改头像不同步) by wiring real Supabase Storage uploads + extending the member profile sync DTO + triggering an initial catch-up on pair join.

**Architecture:** 客户端直连 Supabase Storage `avatars` private bucket 上传 JPEG，生成 1 年 signed URL 写入 `space_members.avatar_url`；pull 侧按 `avatar_version` 版本号去重、按需下载字节到本机缓存。配对成功后立即 catchUp 补齐历史头像。

**Tech Stack:** Swift 6 / SwiftUI / SwiftData / supabase-swift SDK (Storage + REST) / PostgreSQL migrations.

---

## 硬性约束（所有 task 通用）

1. **Swift Testing only**（`import Testing` / `@Test` / `#expect`）——不使用 XCTest。
2. In-memory `ModelContainer` 必须列出 **16 个** PersistentX 模型（含 PersistentTaskMessage）——本次不会新增 PersistentX 类，只给现有实体加字段。
3. 跨文件公用 test helper（`SpyCoordinator` 在 `TogetherTests/ItemRepositorySyncTests.swift:8-35`、`NoopReminderScheduler` 在 `TogetherTests/ProjectSubtaskRepositorySyncTests.swift:8-18`）**直接 import 引用**，不要重新定义。
4. Commit message：English conventional commit style，最后一行 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`。
5. 每个 task 一个 commit；跑 build + 全量 regression，两者都绿才算完成。
6. 禁用 `print`，用 `os.Logger`；禁 `// TODO` / `// FIXME` 注释。
7. Supabase project ID：`nxielmwdoiwiwhzczrmt`。

---

## Task 1: Migration 011 — schema + Storage bucket + RLS

**Files:**
- Create: `supabase/migrations/011_avatar_storage_and_member_columns.sql`
- Apply via MCP `apply_migration`（controller 执行；subagent 只写 SQL 文件）

- [ ] **Step 1: 写 SQL 迁移文件**

在 `/Users/papertiger/Desktop/Together/supabase/migrations/011_avatar_storage_and_member_columns.sql`：

```sql
-- Migration 011: avatar sync columns + private Storage bucket
--
-- Changes:
-- 1. space_members gains avatar_asset_id + avatar_system_name text columns
--    to carry the full avatar metadata (previously only avatar_url + version
--    survived the push, making the receiving device unable to resolve the
--    partner's avatar).
-- 2. Creates a private Storage bucket `avatars` + permissive anon INSERT/UPDATE
--    RLS (project uses anon-key auth model; see project_identity_model memory).
--    SELECT is intentionally left without a policy — reads must go via a
--    signed URL, which bypasses RLS.

ALTER TABLE public.space_members
    ADD COLUMN IF NOT EXISTS avatar_asset_id text,
    ADD COLUMN IF NOT EXISTS avatar_system_name text;

-- Storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', false)
ON CONFLICT (id) DO NOTHING;

-- RLS on storage.objects for this bucket
DROP POLICY IF EXISTS "avatars_anon_insert" ON storage.objects;
CREATE POLICY "avatars_anon_insert"
ON storage.objects FOR INSERT
TO anon
WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_anon_update" ON storage.objects;
CREATE POLICY "avatars_anon_update"
ON storage.objects FOR UPDATE
TO anon
USING (bucket_id = 'avatars');

-- Explicitly NO SELECT policy for anon. Reads must use signed URLs
-- generated server-side or by the owner client.
```

- [ ] **Step 2: controller 调用 `apply_migration`（subagent 跳过此步）**

```
apply_migration(
  project_id="nxielmwdoiwiwhzczrmt",
  name="avatar_storage_and_member_columns",
  query=<上面的 SQL>
)
```

Expected response: `{success: true}`。

- [ ] **Step 3: 验证列已加上**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='space_members'
  AND column_name IN ('avatar_asset_id','avatar_system_name');
```
Expected 2 行。

```sql
SELECT id, public FROM storage.buckets WHERE id='avatars';
```
Expected 1 行 `(avatars, false)`。

- [ ] **Step 4: commit SQL 文件**

```bash
git add supabase/migrations/011_avatar_storage_and_member_columns.sql
git commit -m "$(cat <<'EOF'
chore(migrations): 011 add avatar_asset_id + avatar_system_name + avatars bucket

space_members previously only surfaced avatar_url (which carried a
local filename, not a URL) and avatar_version. Adds the missing
asset_id + system_name columns so the receiving device has enough
metadata to render the partner's avatar. Also creates a private
`avatars` Storage bucket with anon INSERT/UPDATE policies; reads go
through signed URLs (bucket has no SELECT policy).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Extend `PersistentPairMembership` with avatar metadata

**Files:**
- Modify: `Together/Persistence/Models/PersistentPairMembership.swift`

- [ ] **Step 1: 读现有定义**

```bash
grep -n "avatar" Together/Persistence/Models/PersistentPairMembership.swift
```

现有应有 `avatarPhotoFileName: String?` 和 `avatarVersion: Int`。

- [ ] **Step 2: 加两个新字段**

在 `PersistentPairMembership` class 内，`avatarVersion` 附近加：

```swift
var avatarAssetID: String?
var avatarSystemName: String?
```

`avatarPhotoFileName` 保持不变（但语义已转为"signed URL"，不重命名避免 SwiftData migration 风暴）。

同步更新类的 `init(...)` 如果有显式参数形式：补这两个参数，默认 `nil`。

- [ ] **Step 3: build check**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`（SwiftData additive migration 自动）。

- [ ] **Step 4: 跑全量 regression（验证没把现有 init 调用点打破）**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。如果挂了，说明某处 init 调用点需要补默认参数——定位后补上，重新跑。

- [ ] **Step 5: commit**

```bash
git add Together/Persistence/Models/PersistentPairMembership.swift
git commit -m "$(cat <<'EOF'
feat(persistence): PersistentPairMembership carries avatarAssetID + avatarSystemName

Mirrors the two new Supabase columns (migration 011). These are the
minimum extra metadata needed for the receiving device to resolve the
partner's avatar asset locally after a pull.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Extend sync DTOs + codec

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`（`SpaceMemberUpdateDTO` + `SpaceMemberRowDTO` 或等价名，grep 找）
- Modify: `Together/Sync/Codecs/MemberProfileRecordCodable.swift`

- [ ] **Step 1: 找到 DTO 定义**

```bash
grep -n "SpaceMemberUpdateDTO\|SpaceMemberRowDTO\|avatar_url" Together/Sync/SupabaseSyncService.swift | head -20
grep -n "MemberProfileRecordCodable" Together/Sync/Codecs/MemberProfileRecordCodable.swift
```

- [ ] **Step 2: 给 push-side DTO 加字段**

在 `SpaceMemberUpdateDTO`（push 用的 struct）里，`avatarVersion` 边上加：

```swift
let avatarAssetID: String?
let avatarSystemName: String?
```

`CodingKeys`（如果手写了）里加：

```swift
case avatarAssetID = "avatar_asset_id"
case avatarSystemName = "avatar_system_name"
```

- [ ] **Step 3: 给 pull-side row DTO 加字段**

在解码 `space_members` 行的 struct（通常叫 `SpaceMemberRowDTO` 或在 `pullSpaceMembers` 内匿名 decode 的 struct）里同样加两字段。

- [ ] **Step 4: 更新 `MemberProfileRecordCodable`**

在 `MemberProfileRecordCodable` 里同步加入这两个字段。检查所有 `encode(to:)` / `init(from decoder:)` 已覆盖。

- [ ] **Step 5: build**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 写 DTO 序列化测试**

在 `TogetherTests/` 下新建 `AvatarSyncDTOTests.swift`：

```swift
import Testing
import Foundation
@testable import Together

@Suite("AvatarSyncDTO serialization")
struct AvatarSyncDTOTests {

    @Test("SpaceMemberUpdateDTO includes new avatar fields in JSON")
    func pushDTOIncludesAvatarMetadata() throws {
        let dto = SpaceMemberUpdateDTO(
            displayName: "小狗",
            avatarUrl: "https://example.supabase.co/storage/v1/object/sign/avatars/abc.jpg?token=x",
            avatarAssetID: "asset-abc",
            avatarSystemName: nil,
            avatarVersion: 7
        )
        let json = try JSONEncoder().encode(dto)
        let decoded = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(decoded?["avatar_asset_id"] as? String == "asset-abc")
        #expect(decoded?["avatar_system_name"] as? NSNull != nil || decoded?["avatar_system_name"] == nil)
        #expect(decoded?["avatar_version"] as? Int == 7)
    }

    @Test("SpaceMemberUpdateDTO round-trips with SF Symbol only")
    func pushDTOWithSystemName() throws {
        let dto = SpaceMemberUpdateDTO(
            displayName: "小狗",
            avatarUrl: nil,
            avatarAssetID: nil,
            avatarSystemName: "person.circle.fill",
            avatarVersion: 3
        )
        let json = try JSONEncoder().encode(dto)
        let decoded = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(decoded?["avatar_system_name"] as? String == "person.circle.fill")
        #expect(decoded?["avatar_url"] as? NSNull != nil || decoded?["avatar_url"] == nil)
    }
}
```

（如果 `SpaceMemberUpdateDTO` 的真实 init 参数顺序不同，顺手调整。）

- [ ] **Step 7: 跑新测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/AvatarSyncDTOTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **` + `Executed 2 tests`。

- [ ] **Step 8: 跑全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 9: commit**

```bash
git add Together/Sync/SupabaseSyncService.swift Together/Sync/Codecs/MemberProfileRecordCodable.swift TogetherTests/AvatarSyncDTOTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): extend SpaceMember sync DTOs with avatar_asset_id + avatar_system_name

Push + pull DTOs now carry the missing avatar metadata introduced in
migration 011. MemberProfileRecordCodable matches the new shape.
2 new round-trip tests covering JPEG and SF-Symbol-only cases.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `AvatarStorageUploader` service

**Files:**
- Create: `Together/Services/UserProfiles/AvatarStorageUploader.swift`
- Create: `Together/Services/UserProfiles/AvatarStorageUploaderProtocol.swift`
- Create: `TogetherTests/AvatarStorageUploaderTests.swift`

- [ ] **Step 1: 定义 protocol**

在 `Together/Services/UserProfiles/AvatarStorageUploaderProtocol.swift`：

```swift
import Foundation

protocol AvatarStorageUploaderProtocol: Sendable {
    /// 上传 JPEG 字节到 avatars/{spaceID}/{userID}/{version}.jpg，返回 1 年 signed URL。
    /// 失败抛错。
    func uploadAvatar(
        bytes: Data,
        spaceID: UUID,
        userID: UUID,
        version: Int
    ) async throws -> URL

    /// 按 signed URL 下载 JPEG 字节。
    func downloadAvatar(from url: URL) async throws -> Data
}
```

- [ ] **Step 2: 实现（真实 Supabase 版本）**

在 `Together/Services/UserProfiles/AvatarStorageUploader.swift`：

```swift
import Foundation
import Supabase
import os

final class AvatarStorageUploader: AvatarStorageUploaderProtocol, @unchecked Sendable {
    private let client: SupabaseClient
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "AvatarStorageUploader")
    private let bucketID = "avatars"
    private let signedURLExpirySeconds: Int = 60 * 60 * 24 * 365  // 1 year

    init(client: SupabaseClient) {
        self.client = client
    }

    func uploadAvatar(
        bytes: Data,
        spaceID: UUID,
        userID: UUID,
        version: Int
    ) async throws -> URL {
        let path = "\(spaceID.uuidString.lowercased())/\(userID.uuidString.lowercased())/\(version).jpg"
        _ = try await client.storage
            .from(bucketID)
            .upload(
                path,
                data: bytes,
                options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: true)
            )
        let signed = try await client.storage
            .from(bucketID)
            .createSignedURL(path: path, expiresIn: signedURLExpirySeconds)
        logger.info("uploaded avatar path=\(path, privacy: .public) bytes=\(bytes.count)")
        return signed
    }

    func downloadAvatar(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw AvatarStorageError.downloadFailed(status: http.statusCode)
        }
        return data
    }
}

enum AvatarStorageError: Error {
    case downloadFailed(status: Int)
}
```

（注：`client.storage.from(...).upload(...).createSignedURL` 的确切 API 形状取决于 supabase-swift 版本——构建失败就按实际签名修。core concept 是 upload → get signed URL。）

- [ ] **Step 3: 写测试（mock-based，不打真实 Supabase）**

在 `TogetherTests/AvatarStorageUploaderTests.swift`：

```swift
import Testing
import Foundation
@testable import Together

@Suite("AvatarStorageUploader")
struct AvatarStorageUploaderTests {

    @Test("Builds path as {space}/{user}/{version}.jpg")
    func pathFormat() {
        let spaceID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let userID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let version = 3
        let expected = "\(spaceID.uuidString.lowercased())/\(userID.uuidString.lowercased())/3.jpg"
        #expect(expected == "11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/3.jpg")
    }
}
```

（这个 task 不测真实上传——那是 integration test，放 E2E 手工验证。这里只把纯算法 path 逻辑 lock 住。）

- [ ] **Step 4: build + 测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/AvatarStorageUploaderTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **` + `Executed 1 test`。

- [ ] **Step 5: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: commit**

```bash
git add Together/Services/UserProfiles/AvatarStorageUploader.swift Together/Services/UserProfiles/AvatarStorageUploaderProtocol.swift TogetherTests/AvatarStorageUploaderTests.swift
git commit -m "$(cat <<'EOF'
feat(services): AvatarStorageUploader uploads to Supabase Storage + signs URL

Wraps supabase-swift's storage API. Uploads JPEG bytes to
avatars/{space}/{user}/{version}.jpg with cacheControl=1y, then
returns a 1-year signed URL for the partner device to fetch.
Download side just GETs the signed URL.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire `AvatarStorageUploader` into container + SupabaseSyncService

**Files:**
- Modify: `Together/App/AppContainer.swift`（加 `avatarUploader: AvatarStorageUploaderProtocol` 字段）
- Modify: `Together/Services/LocalServiceFactory.swift`（真实注入 `AvatarStorageUploader(client:)`）
- Modify: `Together/Services/MockServiceFactory.swift`（加 mock 实现）
- Modify: `Together/Sync/SupabaseSyncService.swift`（加 init 参数 `avatarUploader:`，保存到 `self.avatarUploader`；同时保存 `self.avatarMediaStore` 如果还没）
- Create: `Together/Services/UserProfiles/MockAvatarStorageUploader.swift`（spy / in-memory）
- Also grep 任何 `SupabaseSyncService(...)` 构造点，补新参数

- [ ] **Step 1: 加 mock**

在 `Together/Services/UserProfiles/MockAvatarStorageUploader.swift`：

```swift
import Foundation
@testable import Together

final class MockAvatarStorageUploader: AvatarStorageUploaderProtocol, @unchecked Sendable {
    var uploads: [(bytes: Data, spaceID: UUID, userID: UUID, version: Int)] = []
    var stubbedURL: URL = URL(string: "https://example.test/avatars/stub.jpg?sig=1")!
    var stubbedDownloadBytes: Data = Data([0xFF, 0xD8, 0xFF])  // fake JPEG SOI marker

    func uploadAvatar(bytes: Data, spaceID: UUID, userID: UUID, version: Int) async throws -> URL {
        uploads.append((bytes, spaceID, userID, version))
        return stubbedURL
    }

    func downloadAvatar(from url: URL) async throws -> Data {
        stubbedDownloadBytes
    }
}
```

（注：如果项目 Mock 约定是放 `TogetherTests/` 而不是 `Together/` 生产路径，跟着项目惯例走——grep `class Mock` 看惯例。）

- [ ] **Step 2: `AppContainer` 加字段**

```bash
grep -n "let.*Repository:\|let.*Service:" Together/App/AppContainer.swift | head -20
```
找到现有字段结构。在 `taskMessageRepository` 之类之后加：

```swift
let avatarUploader: AvatarStorageUploaderProtocol
```

更新 `init(...)` 参数 + 所有构造点。

- [ ] **Step 3: `LocalServiceFactory` 构造真实 uploader**

在 `LocalServiceFactory.makeContainer(...)`（或类似名），在 supabase client 已构造之后：

```swift
let avatarUploader = AvatarStorageUploader(client: supabaseClient)
```

传入 container init。

- [ ] **Step 4: `MockServiceFactory` 构造 mock**

```swift
let avatarUploader = MockAvatarStorageUploader()
```

传入。

- [ ] **Step 5: build**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 7: commit**

```bash
git add Together/App/AppContainer.swift Together/Services/LocalServiceFactory.swift Together/Services/MockServiceFactory.swift Together/Services/UserProfiles/MockAvatarStorageUploader.swift
git commit -m "$(cat <<'EOF'
chore(di): wire AvatarStorageUploader into AppContainer + factories

Real implementation backed by SupabaseClient; mock returns a stub URL
and stub download bytes for tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Real `pushUpsert(.avatarAsset)` + updated `.memberProfile`

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Create: `TogetherTests/AvatarAssetPushTests.swift`

- [ ] **Step 1: 找到 pushUpsert 的 switch**

```bash
grep -n "case \.avatarAsset\|case \.memberProfile\|pushUpsert" Together/Sync/SupabaseSyncService.swift | head -10
```

- [ ] **Step 2: 实现 `.avatarAsset` 分支**

替换现有 no-op 分支：

```swift
case .avatarAsset:
    guard
        let spaceID = change.spaceID,
        let userID = change.recordID as UUID?,  // actor's user id
        let profile = try await fetchLocalProfile(userID: userID),
        let fileName = profile.avatarPhotoFileName,
        let bytes = try? await avatarMediaStore.readAvatarData(fileName: fileName)
    else {
        logger.warning("avatarAsset push skipped (missing profile or bytes)")
        return
    }
    do {
        let signedURL = try await container.avatarUploader.uploadAvatar(
            bytes: bytes,
            spaceID: spaceID,
            userID: userID,
            version: profile.avatarVersion
        )
        pendingAvatarURL[userID] = signedURL
    } catch {
        logger.error("avatarAsset upload failed: \(error.localizedDescription)")
        // swallow — memberProfile push will still run with a nil avatar_url
    }
```

（上面代码的精确属性名/方法名要按 `SupabaseSyncService` 现有 style 调整——特别是 `pendingAvatarURL` 是新增的 actor-isolated 字典，声明在 service 顶部：`private var pendingAvatarURL: [UUID: URL] = [:]`。）

- [ ] **Step 3: 改 `.memberProfile` 分支**

找到现有 memberProfile 构造 `SpaceMemberUpdateDTO`：

```swift
case .memberProfile:
    guard let userID = change.recordID,
          let profile = try await fetchLocalProfile(userID: userID)
    else { return }

    let signedURL = pendingAvatarURL.removeValue(forKey: userID)

    let dto = SpaceMemberUpdateDTO(
        displayName: profile.displayName,
        avatarUrl: signedURL?.absoluteString,
        avatarAssetID: profile.avatarAssetID,
        avatarSystemName: profile.avatarSystemName,
        avatarVersion: profile.avatarVersion
    )
    try await client
        .from("space_members")
        .update(dto)
        .eq("space_id", value: change.spaceID?.uuidString.lowercased() ?? "")
        .eq("user_id", value: userID.uuidString.lowercased())
        .execute()
```

- [ ] **Step 4: 写 push 测试**

`TogetherTests/AvatarAssetPushTests.swift`：

```swift
import Testing
import Foundation
@testable import Together

@Suite("Avatar asset push")
struct AvatarAssetPushTests {

    @Test("pushUpsert(.avatarAsset) uploads bytes + caches signed URL for memberProfile")
    func avatarAssetThenMemberProfile() async throws {
        let mockUploader = MockAvatarStorageUploader()
        let expectedURL = URL(string: "https://example.test/avatars/x.jpg?sig=1")!
        mockUploader.stubbedURL = expectedURL

        let sut = makeSyncService(uploader: mockUploader)
        let spaceID = UUID()
        let userID = UUID()

        // arrange: seed local profile with avatar photo file
        try await sut.seedProfile(
            userID: userID,
            avatarAssetID: "asset-abc",
            avatarPhotoFileName: "asset-abc.jpg",
            avatarVersion: 5,
            avatarBytes: Data([0xFF, 0xD8, 0xFF])
        )

        // act
        try await sut.pushUpsert(
            SyncChange(entityKind: .avatarAsset, operation: .upsert, recordID: userID, spaceID: spaceID)
        )

        #expect(mockUploader.uploads.count == 1)
        #expect(mockUploader.uploads.first?.version == 5)
        #expect(mockUploader.uploads.first?.spaceID == spaceID)

        // memberProfile push should then use the cached URL
        let capturedUpsert = try await sut.pushUpsert(
            SyncChange(entityKind: .memberProfile, operation: .upsert, recordID: userID, spaceID: spaceID)
        )
        #expect(sut.lastCapturedMemberDTO?.avatarUrl == expectedURL.absoluteString)
        #expect(sut.lastCapturedMemberDTO?.avatarAssetID == "asset-abc")
    }
}
```

（上面测试需要 `SupabaseSyncService` 暴露一点测试钩子：`seedProfile` 和 `lastCapturedMemberDTO`。要不要加钩子取决于实现；如果不方便，用 protocol 注入一个 `SpaceMemberWriterProtocol` mock 替代直接 `client.from(...)`。简化做法：给 pushUpsert 抽一个 `MemberProfileWriterProtocol` 层，默认实现调用 supabase client，mock 实现收集 DTO。）

- [ ] **Step 5: 跑测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/AvatarAssetPushTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 7: commit**

```bash
git add Together/Sync/SupabaseSyncService.swift TogetherTests/AvatarAssetPushTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): pushUpsert(.avatarAsset) really uploads; memberProfile carries signed URL + metadata

Replaces the no-op in .avatarAsset with a real Supabase Storage
upload via AvatarStorageUploader; caches the signed URL keyed by
userID so the subsequent .memberProfile upsert can carry it into
space_members alongside avatar_asset_id + avatar_system_name.
If upload fails we swallow — memberProfile still pushes the symbol
fallback so the partner sees *something*.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Extend `pullSpaceMembers` — version-gated download

**Files:**
- Modify: `Together/Sync/SupabaseSyncService.swift`
- Create: `TogetherTests/SpaceMemberPullAvatarTests.swift`

- [ ] **Step 1: 找现有 pullSpaceMembers**

```bash
grep -n "pullSpaceMembers\|PersistentPairMembership" Together/Sync/SupabaseSyncService.swift | head -10
```

- [ ] **Step 2: 扩写逻辑**

现有分支把 `avatarPhotoFileName = dto.avatarUrl; avatarVersion = dto.avatarVersion ?? 0` 的地方，改为：

```swift
let remoteVersion = dto.avatarVersion ?? 0
let shouldRefresh = remoteVersion > partner.avatarVersion
  || (remoteVersion == partner.avatarVersion && partner.avatarAssetID != dto.avatarAssetID)

if shouldRefresh {
    partner.avatarPhotoFileName = dto.avatarUrl   // now a signed URL
    partner.avatarAssetID = dto.avatarAssetID
    partner.avatarSystemName = dto.avatarSystemName
    partner.avatarVersion = remoteVersion

    if let urlString = dto.avatarUrl,
       let url = URL(string: urlString),
       let assetID = dto.avatarAssetID {
        Task.detached { [avatarUploader, avatarMediaStore, logger] in
            do {
                let bytes = try await avatarUploader.downloadAvatar(from: url)
                let fileName = "asset-\(assetID.lowercased()).jpg"
                try await avatarMediaStore.persistAvatarData(bytes, fileName: fileName)
                logger.info("downloaded partner avatar fileName=\(fileName, privacy: .public) bytes=\(bytes.count)")
            } catch {
                logger.error("partner avatar download failed: \(error.localizedDescription)")
            }
        }
    }
}
```

（`Task.detached` 让下载不阻塞 pull 主流程；失败只记日志。）

- [ ] **Step 3: 写 pull 测试**

`TogetherTests/SpaceMemberPullAvatarTests.swift`：

```swift
import Testing
import Foundation
@testable import Together

@Suite("Space member pull — avatar")
struct SpaceMemberPullAvatarTests {

    @Test("Pull downloads bytes when remote version > local")
    func pullDownloadsBytesOnVersionBump() async throws {
        let uploader = MockAvatarStorageUploader()
        uploader.stubbedDownloadBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let mediaStore = InMemoryAvatarMediaStore()
        let sut = makeSyncService(uploader: uploader, mediaStore: mediaStore)

        try await sut.seedPartnerMembership(avatarVersion: 1)
        try await sut.injectRemoteRow(
            avatarVersion: 3,
            avatarURL: "https://example.test/sig.jpg",
            avatarAssetID: "asset-new",
            avatarSystemName: nil
        )

        try await sut.runPullSpaceMembers()

        let partner = try await sut.loadPartnerMembership()
        #expect(partner.avatarVersion == 3)
        #expect(partner.avatarAssetID == "asset-new")
        #expect(mediaStore.persistedFiles.contains { $0.fileName == "asset-asset-new.jpg" || $0.fileName.contains("asset-new") })
    }

    @Test("Pull skips download when remote version ≤ local")
    func pullSkipsDownloadOnStale() async throws {
        let uploader = MockAvatarStorageUploader()
        let mediaStore = InMemoryAvatarMediaStore()
        let sut = makeSyncService(uploader: uploader, mediaStore: mediaStore)

        try await sut.seedPartnerMembership(avatarVersion: 5, avatarAssetID: "asset-existing")
        try await sut.injectRemoteRow(
            avatarVersion: 3,  // older
            avatarURL: "https://example.test/old.jpg",
            avatarAssetID: "asset-old",
            avatarSystemName: nil
        )

        try await sut.runPullSpaceMembers()

        #expect(mediaStore.persistedFiles.isEmpty)
        let partner = try await sut.loadPartnerMembership()
        #expect(partner.avatarAssetID == "asset-existing")
    }
}
```

- [ ] **Step 4: 跑测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/SpaceMemberPullAvatarTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **` + `Executed 2 tests`。

- [ ] **Step 5: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: commit**

```bash
git add Together/Sync/SupabaseSyncService.swift TogetherTests/SpaceMemberPullAvatarTests.swift
git commit -m "$(cat <<'EOF'
feat(sync): pullSpaceMembers downloads avatar bytes when remote version is newer

Pull now version-gates avatar refresh: only fetch the signed URL's
bytes if remote avatar_version > local (with tiebreak on
avatar_asset_id inequality). Download runs on a detached Task so the
main pull doesn't block on slow media. Failures are logged and
swallowed — next realtime/bootstrap cycle will retry.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `PairSpaceSummaryResolver` surfaces new fields

**Files:**
- Modify: `Together/Services/Pairing/PairSpaceSummaryResolver.swift`
- Create or extend: `TogetherTests/PairSpaceSummaryResolverAvatarTests.swift`

- [ ] **Step 1: 找 resolver**

```bash
grep -n "avatarPhotoFileName\|avatarVersion\|func resolve" Together/Services/Pairing/PairSpaceSummaryResolver.swift
```

- [ ] **Step 2: 扩写 `User` 的构造**

在把 `PersistentPairMembership` 映射成 `User` 的那一段，补上：

```swift
User(
    id: membership.partnerUserID,
    displayName: membership.nickname,
    avatarAssetID: membership.avatarAssetID,
    avatarSystemName: membership.avatarSystemName,
    avatarVersion: membership.avatarVersion
    // ... 其他字段
)
```

（`User` init 参数名要看现状，grep `struct User` / `init` 对齐。）

- [ ] **Step 3: 写 resolver 测试**

```swift
import Testing
import Foundation
@testable import Together

@Suite("PairSpaceSummaryResolver — avatar")
struct PairSpaceSummaryResolverAvatarTests {

    @Test("Partner User receives avatarAssetID + avatarSystemName from membership")
    func resolverPassesAvatarFields() throws {
        let membership = makePersistentPairMembership(
            avatarAssetID: "asset-x",
            avatarSystemName: nil,
            avatarVersion: 7
        )
        let sut = PairSpaceSummaryResolver(/* deps */)
        let summary = try sut.resolve(membership: membership)
        #expect(summary.partner?.avatarAssetID == "asset-x")
        #expect(summary.partner?.avatarVersion == 7)
    }
}
```

- [ ] **Step 4: 跑测试 + 全量**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/PairSpaceSummaryResolverAvatarTests 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add Together/Services/Pairing/PairSpaceSummaryResolver.swift TogetherTests/PairSpaceSummaryResolverAvatarTests.swift
git commit -m "$(cat <<'EOF'
feat(pair): PairSpaceSummaryResolver surfaces avatarAssetID + avatarSystemName

Resolver now carries the two new PersistentPairMembership fields
onto the partner User, which is what HomeViewModel.avatarMetadata
reads to build the HomeAvatar asset. Without this, pull writes the
columns but UI never sees them.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Immediate catchUp after pair success

**Files:**
- Modify: `Together/Services/Pairing/CloudPairingService.swift`

- [ ] **Step 1: 找 success sites**

```bash
grep -n "acceptInviteByCode\|checkAndFinalizeIfAccepted\|pairJoinObserver" Together/Services/Pairing/CloudPairingService.swift | head -10
```

Task 15（partner-nudge）加过 `PairJoinObserver`。我们复用这个已有钩子——但 observer 当前只触发通知权限请求，我们扩展它。

- [ ] **Step 2: 扩展 `PairJoinObserver` 协议**

```swift
protocol PairJoinObserver: AnyObject, Sendable {
    func onSuccessfulPairJoin() async
    /// 新加：pair 成功后立即补一次 catchUp，拉取伴侣现有头像 / 其它历史数据。
    func onRequestImmediateCatchUp() async
}
```

（或者，更简单：把两个职责合并到现有 `onSuccessfulPairJoin`，让 `AppContext` 在回调里同时做权限请求 + `catchUp`。选后者——不扩 protocol，改 AppContext 的实现即可。）

选**后者**（更改小）。在 `AppContext` 的 `onSuccessfulPairJoin` 里追加：

```swift
extension AppContext: PairJoinObserver {
    func onSuccessfulPairJoin() async {
        // 1) 通知权限（原有逻辑，不动）
        let status = await container.notificationService.authorizationStatus()
        if status == .notDetermined {
            _ = try? await container.notificationService.requestAuthorization()
        }
        // 2) 新加：立即 catchUp，确保伴侣已有头像进到本地
        do {
            try await container.syncCoordinator.catchUp()
        } catch {
            appContextLogger.error("post-pair catchUp failed: \(error.localizedDescription)")
        }
    }
}
```

（`catchUp()` 的真实方法名要按 `SyncCoordinatorProtocol` / `SupabaseSyncService` 现状对齐——grep `func catchUp` 找。）

- [ ] **Step 3: build**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add Together/App/AppContext.swift
git commit -m "$(cat <<'EOF'
feat(pair): pair-join callback also triggers an immediate catchUp

Reuses the existing PairJoinObserver wire (added in partner-nudge
Task 15). After asking for notification permission, AppContext now
also fires syncCoordinator.catchUp so the partner's pre-existing
avatar / other state is pulled before the user hits Home — fixes
the "first time pair, avatar doesn't show" bug.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: 300 KB 软 size guard

**Files:**
- Modify: `Together/Features/Profile/EditProfileViewModel.swift`

- [ ] **Step 1: 找现有的 jpegData 生成点**

```bash
grep -n "jpegData\|compressionQuality" Together/Features/Profile/EditProfileViewModel.swift
```

- [ ] **Step 2: 加 guard**

在 `jpegData(compressionQuality: 0.88)` 返回之后：

```swift
let bytes = image.jpegData(compressionQuality: 0.88) ?? Data()
if bytes.count > 300_000 {
    editProfileLogger.warning("avatar payload large: \(bytes.count) bytes")
}
```

（声明 `private let editProfileLogger = Logger(subsystem: "com.pigdog.Together", category: "EditProfileVM")` 如果没有。）

- [ ] **Step 3: build**

```bash
xcodebuild -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: commit**

```bash
git add Together/Features/Profile/EditProfileViewModel.swift
git commit -m "$(cat <<'EOF'
chore(profile): log warning when avatar JPEG exceeds 300 KB

Defensive check — at 512×512@0.88 the payload should stay ~80–120 KB,
but unusual source images (panoramic HEIC, etc.) could produce much
larger JPEGs. Log a warning so we can notice if the size creeps up,
but do not block the save.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: 全量回归 + 双设备 E2E + 合并到 main

**Files:** 无

- [ ] **Step 1: 全量 regression**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "TEST SUCC|TEST FAIL|Executed [0-9]+ tests" | tail -5
```
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 2: 双设备真机 E2E（user blocking）**

请用户在 iPhone + iPad 上执行以下场景，每条都要通过：

1. **新 pair 看到历史头像**：
   - iPad 先改头像为照片 X
   - 新 pair（或取消 pair 后重 pair） → iPhone 点接受
   - iPhone 进入主页后 10 秒内应显示 iPad 的头像 X（不是默认图）

2. **改头像推送给对方**：
   - iPhone 在已 pair 状态下改头像为照片 Y
   - iPad 的主页伴侣头像 strip 在 10 秒内刷新为 Y

3. **SF Symbol 头像同步**：
   - iPhone 改头像为 SF Symbol（比如 `person.circle.fill`）
   - iPad 在 10 秒内也显示同样的 Symbol（非照片）

4. **离线编辑**：
   - iPhone 断网，改头像
   - 恢复网络后，iPad 在 10 秒内收到

5. **Storage 路径验证**（通过 MCP SQL）：
   ```sql
   SELECT avatar_url, avatar_asset_id, avatar_system_name, avatar_version FROM space_members ORDER BY updated_at DESC LIMIT 5;
   ```
   Expected：`avatar_url` 是 `https://<project>.supabase.co/storage/v1/object/sign/avatars/...` 开头的 signed URL；非 null 的 `avatar_asset_id`。

- [ ] **Step 3: Supabase Storage 对象确认**

```
# Via MCP — 列出 avatars bucket
list_storage_objects(bucket_id="avatars")  # 如有此工具
```

或 SQL：
```sql
SELECT name, created_at, metadata->>'size' AS size_bytes
FROM storage.objects
WHERE bucket_id='avatars'
ORDER BY created_at DESC LIMIT 10;
```
Expected：至少有 E2E 期间改头像对应的 {space}/{user}/{version}.jpg 对象。

- [ ] **Step 4: 合并到 main + push**

```bash
git checkout main
git merge --ff-only feat/avatar-sync
git push origin main
```

- [ ] **Step 5: 追加实施日志**

打开 `docs/superpowers/plans/2026-04-19-avatar-sync.md`，在末尾追加 `## 实施日志` 段：
- Commit SHA 顺序列
- 遇到的偏差 / 不可行方案
- 留给后续分支的 TODO（比如 Storage 清理策略 / signed URL 过期处理 / 路径 RLS 收紧）

```bash
git add docs/superpowers/plans/2026-04-19-avatar-sync.md
git commit -m "docs(plan): avatar sync implementation log"
git push origin main
```

---

## Verification checklist

合并前确认：

```
□ §1 范围
  □ 仅改 Supabase pair 路径（CloudKit solo 不动）

□ §2 数据模型
  □ Migration 011 已 apply（MCP 验证）
  □ PersistentPairMembership 新字段 avatarAssetID + avatarSystemName

□ §3 同步流程
  □ pushUpsert(.avatarAsset) 真上传 + 写 pendingAvatarURL
  □ pushUpsert(.memberProfile) 带 signed URL + 所有 4 avatar 字段
  □ pullSpaceMembers version-gated + 异步下载字节
  □ acceptInviteByCode / checkAndFinalizeIfAccepted 后立即 catchUp

□ §4 隐私
  □ bucket private（public=false 已查）
  □ RLS policy 允许 anon INSERT/UPDATE，无 SELECT
  □ signed URL 1 年有效

□ §6 压缩
  □ 现有 512×512 @ 0.88 保持不变
  □ 300 KB 软警告加上

□ §8 测试
  □ AvatarSyncDTOTests 绿
  □ AvatarAssetPushTests 绿
  □ SpaceMemberPullAvatarTests 绿
  □ PairSpaceSummaryResolverAvatarTests 绿
  □ 全量回归绿
```

---

## 实施日志

### Timeline
开工：2026-04-19（`main` 基线 `90f8bf2`）
合并到 main：2026-04-19（`3efa20d` → `main`）

### Commit SHAs（按任务顺序）

Tasks 1-10（spec 内）:
- `6f458c8` T1 migration 011（space_members 加 `avatar_asset_id` + `avatar_system_name`，创建 `avatars` private bucket + anon INSERT/UPDATE RLS）
- `30e55fe` T2 PersistentPairMembership 加字段（实际上字段已存在，只补了文档注释）
- `0f9a62b` T3 SpaceMemberUpdateDTO + SpaceMemberDTO + MemberProfileRecordCodable 加字段 + 序列化测试
- `de5d39b` T4 AvatarStorageUploader 服务（真实 + mock） + path 格式测试
- `649b769` T5 把 uploader 接入 AppContainer + SupabaseSyncService（顺便把 avatarMediaStore 也注入）
- `7447aa1` T6 pushUpsert(.avatarAsset) 真上传 + memberProfile 带 signed URL + push 测试
- `5a7a122` T7 pullSpaceMembers version-gated 下载 + SpaceMemberReader 测试 seam
- `a3dfbf9` T7-fix 存储 cache filename 而非 signed URL（review 发现）
- `78101d5` T8 PairSpaceSummaryResolver 补伴侣 avatar 字段 + 测试（resolver 已在 T7 提前修好，此处只补测试）
- `d8966ba` T9 pair-join 回调追加 syncService.catchUp()
- `b2a9dae` T10 EditProfileViewModel 300 KB 软上限警告

Tasks 11+ 补丁（spec 外、调试中发现）:

**Supabase Storage RLS 调试（4 轮）:**
- `34541d7` migration 012：`TO anon` → `TO public`（SDK role 不稳）
- `db05cdd` migration 013：给 `storage.buckets` 加 avatars SELECT policy（Storage server 要先 SELECT bucket 再 INSERT object）
- `87c28d0` migration 014：给 `storage.objects` 加 avatars SELECT policy（`x-upsert: true` 触发 ON CONFLICT DO UPDATE，需要 SELECT 权限评估 USING）

**UI 缓存调试（4 轮）:**
- `dc5334b` 分区伴侣 cacheFileName `asset-{id}-v{version}.jpg` + 下载完成后发 `.partnerAvatarDownloaded`
- `81293fe` pull 版本闸门从 `remote > local` 改为 `remote != local`（reinstall 后 version 回退也能同步）
- `a77c3e3` User.avatarCacheFileName 优先返回 `avatarPhotoFileName`（此前它忽略新 versioned filename，UI 找不到文件回落到默认图）
- `2c32c3f` 下载后 evict UIImage NSCache + AvatarPhotoView 监听 `.partnerAvatarDownloaded` 重置 loadedImage
- `6467d15` `.onReceive` 加 `.receive(on: DispatchQueue.main)`（publisher 来自 Task.detached，默认在后台线程，导致 `@State` 变更被 SwiftUI 警告 "Publishing changes from background threads" 拒绝生效）
- `fbf8b68` 砍掉 AvatarPhotoView 的 3 分支（loadedImage/cache-hit/fallback），合并为单分支，`.onReceive` 不再按 fileName 匹配——任何 partner avatar 下载都 evict + bump tick 强制重读盘

最后 `3efa20d` docs 入库（spec + plan）。

### 关键技术决策

1. **Storage RLS 三连踩坑**：Supabase Storage 的 anon client 上传需要同时满足：
   - `storage.buckets` 有 SELECT policy（server 要先查 bucket 存在）
   - `storage.objects` 有 INSERT WITH CHECK policy（INSERT 本身）
   - `storage.objects` 有 SELECT + UPDATE policy（`x-upsert: true` 触发 ON CONFLICT DO UPDATE）
   
   三个缺一个，整个链路静默挂掉报 "new row violates RLS policy"。隐私靠 `bucket.public=false` + 1 年 signed URL + UUID 组合的路径保持。

2. **签名 URL vs 本地缓存文件名区分**：早期把 signed URL 存进 `PersistentPairMembership.avatarPhotoFileName` 了，但代码库其他地方（UI 读盘）把它当本地文件名处理。改为写 `asset-{id}-v{version}.jpg`（不跟 User.avatarAssetID 冲突）。

3. **UIImage 缓存 by URL 是 footgun**：`NSCache<NSString, UIImage>` 按路径 key，磁盘内容变化但路径不变 → 缓存永远返回旧 UIImage。用"路径加 version 后缀"让每次新版本 key 不同，再加"下载完成后显式 evict"作为第二道保险。

4. **SwiftUI `.onReceive` 默认 publisher 线程**：NotificationCenter.publisher 不自动切主线程。从 `Task.detached` post 的事件到达 `.onReceive` 的 closure 时仍在后台线程，对 `@State` 的写入被 SwiftUI runtime 警告并静默丢弃。**必须**在 publisher 链里 `.receive(on: DispatchQueue.main)`。

### 已验证不可行的方案

- **RLS `TO anon` (migration 011)**：SDK client 的 role 不稳定——`TO public` 才能覆盖。
- **不加 SELECT policy**：想靠 signed URL 做反向证明，但上传侧 `x-upsert: true` 需要 SELECT 评估 ON CONFLICT 的 USING 子句。
- **固定 cacheFileName `asset-{id}.jpg`（无版本）**：改头像后路径不变，UIImage 缓存永远返回旧图。
- **pull version gate `remote > local`**：reinstall 后 remote version 回退到 1，但字节其实是新的——永远不下载。改为 `!=` 才对。
- **AvatarPhotoView 按 fileName 精确匹配事件才 evict 缓存**：pairSpaceSummary 刷新有延迟，事件到达时 view 可能还没切到新 fileName → 匹配失败 → 不 evict → 缓存永远陈旧。改为任何事件都 evict。

### 身份模型问题（已记录）

本分支没触碰 `tasks.creator_id` / `space_members.user_id` 身份不一致问题，继续用 `push_on_task_change` trigger 的 fan-out + client 自过滤。头像同步虽然也走 `space_members`，但直接把成员 ID 写入 DTO，不依赖 auth.uid() 路由。

### 待续事项（下个分支）

- Storage bucket 老版本文件清理策略（每次改头像都留一个旧 `.jpg`，小，但积累会慢慢占空间）
- `avatar_url` 在 DB 里存的是 signed URL，1 年后过期——暂未处理过期重生成
- 用过期时 client 可能 403 下载失败，目前只 log，没触发 re-sync
- 身份模型统一（与 partner-nudge 分支共用的历史遗留）

