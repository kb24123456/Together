# Solo Recovery + Pro Multi-Device Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make solo-mode productivity data recoverable from Supabase after iPhone reinstall or iPhone replacement, while reserving iPad/Mac active sync for Pro.

**Architecture:** Add Supabase as the solo authoritative cloud source while keeping SwiftData as the local cache. Implement a solo-specific sync service that reuses the existing local outbox and DTO mapping patterns, but does not depend on pair-mode Realtime/session state. Gate non-iPhone platforms through `PremiumGate`; first milestone allows all iPhone push/pull so a second iPhone works as restore.

**Tech Stack:** Swift 6.2, SwiftData, Swift Testing, Supabase Swift SDK/PostgREST, Supabase SQL migrations with RLS.

**Design Spec:** `docs/superpowers/specs/2026-04-29-solo-recovery-pro-sync-design.md`

---

## Scope Check

This plan implements the iPhone solo recovery foundation first. It does not implement iPad/macOS targets because the repository is currently iPhone-only (`DEVELOPMENT_GUIDELINES.md`). The plan still adds a platform/pro gate seam so future iPad/Mac work can plug in without rewriting sync.

The first implementation covers currently reachable solo productivity data:

- `tasks`
- `task_lists`
- `projects`
- `project_subtasks`
- `periodic_tasks`

`important_dates` are already synced through the pair-oriented `SupabaseSyncService` and are primarily configured from pair context in current production flow, so the implementation phase must verify whether they are reachable as solo-owned data before adding them to the solo service.

## File Structure

### Supabase

- Create: `supabase/migrations/027_solo_recovery.sql`
  - Adds `device_installations`.
  - Adds active-single-space uniqueness guard after duplicate preflight.
  - Tightens/extends RLS policies for solo spaces without breaking pair space membership policies.

### Client Sync

- Create: `Together/Sync/Solo/SoloDevicePlatform.swift`
  - Maps current runtime to `.iphone`, future `.ipad`, `.mac`.
- Create: `Together/Sync/Solo/SoloSyncGate.swift`
  - Decides whether sync is allowed based on platform and `PremiumGate`.
- Create: `Together/Sync/Solo/SoloSyncMetadataStore.swift`
  - Persists migration and cursor metadata in `UserDefaults`.
- Create: `Together/Sync/Solo/SupabaseSoloRemoteGateway.swift`
  - Encapsulates Supabase calls for single space, device registration, snapshot fetch, and upsert.
- Create: `Together/Sync/Solo/SupabaseSoloSyncService.swift`
  - Orchestrates startup branch, local/remote single-space reconciliation, migration bootstrap, push, and pull.
- Create: `Together/Sync/Solo/SoloSyncDiagnostics.swift`
  - Produces diagnostic snapshots for TestFlight/debug.

### Existing Files

- Modify: `Together/App/AppContainer.swift`
  - Add `supabaseSoloSyncService`.
- Modify: `Together/Services/LocalServiceFactory.swift`
  - Construct and inject solo sync dependencies.
- Modify: `Together/App/AppContext.swift`
  - Start solo Supabase recovery after Supabase auth and profile hydration.
  - Keep CKSyncEngine temporarily, but do not rely on it as the only recovery path.
- No first-pass change: `Together/Sync/SupabaseSyncService.swift`
  - Existing DTO types are module-internal and available to new production files in the same target.
- No first-pass change: `Together/Domain/Entities/SharedSyncStatus.swift`
  - Solo diagnostics are kept in `SoloSyncDiagnosticSnapshot`; UI surfacing is outside this plan.

### Tests

- Create: `TogetherTests/SoloSyncGateTests.swift`
- Create: `TogetherTests/SoloSyncMetadataStoreTests.swift`
- Create: `TogetherTests/SupabaseSoloSyncServiceTests.swift`
- Create: `TogetherTests/SupabaseSoloRemoteGatewayDTOTests.swift`

---

## Task 1: Add Supabase Schema for Solo Recovery

**Files:**
- Create: `supabase/migrations/027_solo_recovery.sql`

- [ ] **Step 1: Write migration with duplicate preflight**

Create `supabase/migrations/027_solo_recovery.sql`:

```sql
-- 027_solo_recovery.sql
-- Solo recovery foundation: one active single space per owner and device registry.

do $$
begin
  if exists (
    select owner_user_id
    from public.spaces
    where type = 'single' and status = 'active'
    group by owner_user_id
    having count(*) > 1
  ) then
    raise exception 'duplicate active single spaces exist; archive or merge them before applying 027_solo_recovery';
  end if;
end $$;

create unique index if not exists idx_spaces_one_active_single_per_owner
on public.spaces(owner_user_id)
where type = 'single' and status = 'active';

create table if not exists public.device_installations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  platform text not null check (platform in ('iphone', 'ipad', 'mac')),
  device_name text,
  app_version text,
  build_number text,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_sync_at timestamptz,
  unique(user_id, installation_id)
);

create index if not exists idx_device_installations_user
on public.device_installations(user_id);

alter table public.device_installations enable row level security;

drop policy if exists "users can read own device installations" on public.device_installations;
create policy "users can read own device installations"
on public.device_installations
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "users can insert own device installations" on public.device_installations;
create policy "users can insert own device installations"
on public.device_installations
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "users can update own device installations" on public.device_installations;
create policy "users can update own device installations"
on public.device_installations
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
```

- [ ] **Step 2: Apply migration to Supabase**

Apply via MCP:

```sql
-- Use mcp__supabase__apply_migration with name: solo_recovery
-- and the exact SQL from Step 1.
```

Expected:

```text
Migration applies without duplicate-space exception.
```

If it fails with duplicate active single spaces, run a read-only query first:

```sql
select owner_user_id, array_agg(id order by updated_at desc) as space_ids
from public.spaces
where type = 'single' and status = 'active'
group by owner_user_id
having count(*) > 1;
```

Do not archive duplicates without user confirmation.

- [ ] **Step 3: Verify table and RLS**

Run with Supabase MCP:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name = 'device_installations';
```

Expected:

```text
device_installations
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/027_solo_recovery.sql
git commit -m "chore(sync): add solo recovery schema"
```

---

## Task 2: Add Platform and Pro Sync Gate

**Files:**
- Create: `Together/Sync/Solo/SoloDevicePlatform.swift`
- Create: `Together/Sync/Solo/SoloSyncGate.swift`
- Test: `TogetherTests/SoloSyncGateTests.swift`

- [ ] **Step 1: Write failing tests**

Create `TogetherTests/SoloSyncGateTests.swift`:

```swift
import Testing
@testable import Together

@Suite("SoloSyncGate")
struct SoloSyncGateTests {
    @Test("iPhone is allowed without Pro for restore")
    func iPhoneAllowedWithoutPro() {
        let decision = SoloSyncGate.decision(platform: .iphone, isPro: false)
        #expect(decision == .allowed)
    }

    @Test("iPad is blocked without Pro")
    func iPadBlockedWithoutPro() {
        let decision = SoloSyncGate.decision(platform: .ipad, isPro: false)
        #expect(decision == .blockedRequiresPro)
    }

    @Test("Mac is blocked without Pro")
    func macBlockedWithoutPro() {
        let decision = SoloSyncGate.decision(platform: .mac, isPro: false)
        #expect(decision == .blockedRequiresPro)
    }

    @Test("iPad and Mac are allowed with Pro")
    func proAllowsNonPhonePlatforms() {
        #expect(SoloSyncGate.decision(platform: .ipad, isPro: true) == .allowed)
        #expect(SoloSyncGate.decision(platform: .mac, isPro: true) == .allowed)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SoloSyncGateTests
```

Expected:

```text
Cannot find 'SoloSyncGate' in scope
```

- [ ] **Step 3: Implement platform and gate**

Create `Together/Sync/Solo/SoloDevicePlatform.swift`:

```swift
import Foundation
#if os(iOS)
import UIKit
#endif

enum SoloDevicePlatform: String, Codable, Hashable, Sendable {
    case iphone
    case ipad
    case mac

    static var current: SoloDevicePlatform {
        #if os(macOS)
        return .mac
        #else
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
        #else
        return .iphone
        #endif
        #endif
    }
}
```

Create `Together/Sync/Solo/SoloSyncGate.swift`:

```swift
import Foundation

enum SoloSyncGateDecision: Hashable, Sendable {
    case allowed
    case blockedRequiresPro
}

enum SoloSyncGate {
    static func decision(platform: SoloDevicePlatform, isPro: Bool) -> SoloSyncGateDecision {
        switch platform {
        case .iphone:
            return .allowed
        case .ipad, .mac:
            return isPro ? .allowed : .blockedRequiresPro
        }
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SoloSyncGateTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Solo/SoloDevicePlatform.swift Together/Sync/Solo/SoloSyncGate.swift TogetherTests/SoloSyncGateTests.swift
git commit -m "feat(sync): add solo platform gate"
```

---

## Task 3: Add Local Solo Sync Metadata

**Files:**
- Create: `Together/Sync/Solo/SoloSyncMetadataStore.swift`
- Test: `TogetherTests/SoloSyncMetadataStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `TogetherTests/SoloSyncMetadataStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("SoloSyncMetadataStore")
struct SoloSyncMetadataStoreTests {
    @Test("stores migration completion per space")
    func migrationCompletionPersistsPerSpace() {
        let suiteName = "SoloSyncMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SoloSyncMetadataStore(defaults: defaults)
        let spaceID = UUID()
        let date = Date(timeIntervalSince1970: 100)

        #expect(store.migrationCompletedAt(spaceID: spaceID) == nil)
        store.markMigrationCompleted(spaceID: spaceID, at: date, build: "13")

        #expect(store.migrationCompletedAt(spaceID: spaceID) == date)
        #expect(store.migrationBuild(spaceID: spaceID) == "13")
    }

    @Test("stores pull and push cursors separately")
    func storesPullAndPushCursors() {
        let suiteName = "SoloSyncMetadataStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SoloSyncMetadataStore(defaults: defaults)
        let spaceID = UUID()
        let pull = Date(timeIntervalSince1970: 200)
        let push = Date(timeIntervalSince1970: 300)

        store.setLastPulledAt(pull, spaceID: spaceID)
        store.setLastPushedAt(push, spaceID: spaceID)

        #expect(store.lastPulledAt(spaceID: spaceID) == pull)
        #expect(store.lastPushedAt(spaceID: spaceID) == push)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SoloSyncMetadataStoreTests
```

Expected:

```text
Cannot find 'SoloSyncMetadataStore' in scope
```

- [ ] **Step 3: Implement metadata store**

Create `Together/Sync/Solo/SoloSyncMetadataStore.swift`:

```swift
import Foundation

final class SoloSyncMetadataStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func migrationCompletedAt(spaceID: UUID) -> Date? {
        defaults.object(forKey: key("migrationCompletedAt", spaceID)) as? Date
    }

    func migrationBuild(spaceID: UUID) -> String? {
        defaults.string(forKey: key("migrationBuild", spaceID))
    }

    func markMigrationCompleted(spaceID: UUID, at date: Date, build: String?) {
        defaults.set(date, forKey: key("migrationCompletedAt", spaceID))
        if let build {
            defaults.set(build, forKey: key("migrationBuild", spaceID))
        }
    }

    func lastPulledAt(spaceID: UUID) -> Date? {
        defaults.object(forKey: key("lastPulledAt", spaceID)) as? Date
    }

    func setLastPulledAt(_ date: Date, spaceID: UUID) {
        defaults.set(date, forKey: key("lastPulledAt", spaceID))
    }

    func lastPushedAt(spaceID: UUID) -> Date? {
        defaults.object(forKey: key("lastPushedAt", spaceID)) as? Date
    }

    func setLastPushedAt(_ date: Date, spaceID: UUID) {
        defaults.set(date, forKey: key("lastPushedAt", spaceID))
    }

    private func key(_ name: String, _ spaceID: UUID) -> String {
        "together.soloSupabase.\(spaceID.uuidString).\(name)"
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SoloSyncMetadataStoreTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Solo/SoloSyncMetadataStore.swift TogetherTests/SoloSyncMetadataStoreTests.swift
git commit -m "feat(sync): add solo sync metadata store"
```

---

## Task 4: Add Solo Remote Gateway DTOs and Test Seams

**Files:**
- Create: `Together/Sync/Solo/SupabaseSoloRemoteGateway.swift`
- Test: `TogetherTests/SupabaseSoloRemoteGatewayDTOTests.swift`

- [ ] **Step 1: Write failing DTO tests**

Create `TogetherTests/SupabaseSoloRemoteGatewayDTOTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("SupabaseSoloRemoteGateway DTOs")
struct SupabaseSoloRemoteGatewayDTOTests {
    @Test("single space insert uses auth uid and single type")
    func singleSpaceInsertUsesAuthUID() {
        let userID = UUID()
        let dto = SoloSpaceUpsertDTO.newSingle(ownerUserID: userID, displayName: "我的空间")

        #expect(dto.ownerUserID == userID)
        #expect(dto.type == "single")
        #expect(dto.status == "active")
        #expect(dto.displayName == "我的空间")
    }

    @Test("device installation upsert uses platform and user id")
    func deviceInstallationUsesPlatformAndUserID() {
        let userID = UUID()
        let installationID = UUID()
        let dto = DeviceInstallationUpsertDTO(
            userID: userID,
            installationID: installationID,
            platform: .iphone,
            deviceName: "iPhone",
            appVersion: "1.0",
            buildNumber: "13"
        )

        #expect(dto.userID == userID)
        #expect(dto.installationID == installationID)
        #expect(dto.platform == "iphone")
        #expect(dto.deviceName == "iPhone")
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloRemoteGatewayDTOTests
```

Expected:

```text
Cannot find 'SoloSpaceUpsertDTO' in scope
```

- [ ] **Step 3: Implement DTOs and gateway protocol**

Create `Together/Sync/Solo/SupabaseSoloRemoteGateway.swift`:

```swift
import Foundation
import Supabase

struct SoloSpaceUpsertDTO: Codable, Sendable {
    let id: UUID?
    let ownerUserID: UUID
    let type: String
    let displayName: String
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, status
        case ownerUserID = "owner_user_id"
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }

    static func newSingle(ownerUserID: UUID, displayName: String, now: Date = .now) -> SoloSpaceUpsertDTO {
        SoloSpaceUpsertDTO(
            id: nil,
            ownerUserID: ownerUserID,
            type: "single",
            displayName: displayName,
            status: "active",
            updatedAt: now
        )
    }
}

struct DeviceInstallationUpsertDTO: Codable, Sendable {
    let userID: UUID
    let installationID: UUID
    let platform: String
    let deviceName: String?
    let appVersion: String?
    let buildNumber: String?
    let isActive: Bool
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case platform
        case userID = "user_id"
        case installationID = "installation_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case isActive = "is_active"
        case lastSeenAt = "last_seen_at"
    }

    init(
        userID: UUID,
        installationID: UUID,
        platform: SoloDevicePlatform,
        deviceName: String?,
        appVersion: String?,
        buildNumber: String?,
        now: Date = .now
    ) {
        self.userID = userID
        self.installationID = installationID
        self.platform = platform.rawValue
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.isActive = true
        self.lastSeenAt = now
    }
}

struct SoloRemoteSnapshot: Sendable {
    var tasks: [TaskDTO] = []
    var taskLists: [TaskListDTO] = []
    var projects: [ProjectDTO] = []
    var projectSubtasks: [ProjectSubtaskDTO] = []
    var periodicTasks: [PeriodicTaskDTO] = []
}

protocol SupabaseSoloRemoteGatewayProtocol: Sendable {
    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID
    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws
    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot
    func upsert(snapshot: SoloRemoteSnapshot) async throws
}
```

Then add a production `SupabaseSoloRemoteGateway` actor in the same file:

```swift
actor SupabaseSoloRemoteGateway: SupabaseSoloRemoteGatewayProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID {
        struct SpaceRow: Decodable { let id: UUID }

        let existing: [SpaceRow] = try await client.from("spaces")
            .select("id")
            .eq("owner_user_id", value: userID.uuidString)
            .eq("type", value: "single")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        if let id = existing.first?.id {
            try await ensureMembership(spaceID: id, userID: userID)
            return id
        }

        let inserted: [SpaceRow] = try await client.from("spaces")
            .insert(SoloSpaceUpsertDTO.newSingle(ownerUserID: userID, displayName: displayName))
            .select("id")
            .execute()
            .value

        guard let id = inserted.first?.id else {
            throw SoloRemoteGatewayError.missingInsertedSpaceID
        }
        try await ensureMembership(spaceID: id, userID: userID)
        return id
    }

    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws {
        try await client.from("device_installations")
            .upsert(dto, onConflict: "user_id,installation_id")
            .execute()
    }

    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot {
        var snapshot = SoloRemoteSnapshot()
        let sinceDate = since ?? .distantPast
        let sinceISO = ISO8601DateFormatter().string(from: sinceDate)

        snapshot.tasks = try await client.from("tasks").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.taskLists = try await client.from("task_lists").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.projects = try await client.from("projects").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.projectSubtasks = try await client.from("project_subtasks").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.periodicTasks = try await client.from("periodic_tasks").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        return snapshot
    }

    func upsert(snapshot: SoloRemoteSnapshot) async throws {
        if snapshot.taskLists.isEmpty == false {
            try await client.from("task_lists").upsert(snapshot.taskLists, onConflict: "id").execute()
        }
        if snapshot.projects.isEmpty == false {
            try await client.from("projects").upsert(snapshot.projects, onConflict: "id").execute()
        }
        if snapshot.projectSubtasks.isEmpty == false {
            try await client.from("project_subtasks").upsert(snapshot.projectSubtasks, onConflict: "id").execute()
        }
        if snapshot.periodicTasks.isEmpty == false {
            try await client.from("periodic_tasks").upsert(snapshot.periodicTasks, onConflict: "id").execute()
        }
        if snapshot.tasks.isEmpty == false {
            try await client.from("tasks").upsert(snapshot.tasks, onConflict: "id").execute()
        }
    }

    private func ensureMembership(spaceID: UUID, userID: UUID) async throws {
        struct MemberDTO: Encodable {
            let space_id: UUID
            let user_id: UUID
            let display_name: String
            let role: String
        }

        try await client.from("space_members")
            .upsert(
                MemberDTO(space_id: spaceID, user_id: userID, display_name: "我", role: "owner"),
                onConflict: "space_id,user_id"
            )
            .execute()
    }
}

enum SoloRemoteGatewayError: Error {
    case missingInsertedSpaceID
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloRemoteGatewayDTOTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Solo/SupabaseSoloRemoteGateway.swift TogetherTests/SupabaseSoloRemoteGatewayDTOTests.swift
git commit -m "feat(sync): add solo Supabase gateway"
```

---

## Task 5: Implement Solo Sync Service Bootstrap Branches

**Files:**
- Create: `Together/Sync/Solo/SupabaseSoloSyncService.swift`
- Test: `TogetherTests/SupabaseSoloSyncServiceTests.swift`

- [ ] **Step 1: Write tests with fake remote gateway**

Create `TogetherTests/SupabaseSoloSyncServiceTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import Together

@Suite("SupabaseSoloSyncService")
struct SupabaseSoloSyncServiceTests {
    @Test("fresh install pulls remote snapshot and writes metadata")
    func freshInstallPullsRemoteSnapshot() async throws {
        let harness = try SoloSyncHarness()
        let spaceID = UUID()
        let taskID = UUID()
        harness.remote.spaceID = spaceID
        harness.remote.snapshot.tasks = [
            TaskDTO.fixture(id: taskID, spaceID: spaceID, title: "remote task")
        ]

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        let context = ModelContext(harness.container)
        let items = try context.fetch(FetchDescriptor<PersistentItem>())
        #expect(items.map(\.title) == ["remote task"])
        #expect(harness.metadata.migrationCompletedAt(spaceID: spaceID) != nil)
    }

    @Test("existing local store uploads local records before marking migration complete")
    func existingLocalStoreUploadsBeforeBaseline() async throws {
        let harness = try SoloSyncHarness()
        let localSpaceID = UUID()
        let remoteSpaceID = UUID()
        harness.remote.spaceID = remoteSpaceID

        let context = ModelContext(harness.container)
        context.insert(PersistentSpace(space: Space(id: localSpaceID, type: .single, displayName: "我的空间", ownerUserID: harness.userID, status: .active, createdAt: .now, updatedAt: .now)))
        context.insert(PersistentItem.sample(id: UUID(), spaceID: localSpaceID, creatorID: harness.userID, title: "local task"))
        try context.save()

        try await harness.service.start(
            userID: harness.userID,
            localUserID: harness.userID,
            displayName: "我",
            platform: .iphone,
            isPro: false
        )

        #expect(harness.remote.upserted.tasks.map(\.title) == ["local task"])
        #expect(harness.remote.upserted.tasks.first?.spaceId == remoteSpaceID)
        #expect(harness.metadata.migrationCompletedAt(spaceID: remoteSpaceID) != nil)
    }

    @Test("iPad without Pro does not pull or push")
    func ipadWithoutProBlocked() async throws {
        let harness = try SoloSyncHarness()

        do {
            try await harness.service.start(
                userID: harness.userID,
                localUserID: harness.userID,
                displayName: "我",
                platform: .ipad,
                isPro: false
            )
            Issue.record("Expected requiresPro")
        } catch SoloSyncServiceError.requiresPro {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(harness.remote.didFetchSnapshot == false)
    }
}
```

Add test helpers in the same file:

```swift
private final class FakeSoloRemoteGateway: SupabaseSoloRemoteGatewayProtocol, @unchecked Sendable {
    var spaceID = UUID()
    var snapshot = SoloRemoteSnapshot()
    var upserted = SoloRemoteSnapshot()
    var didFetchSnapshot = false

    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID { spaceID }
    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws {}
    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot {
        didFetchSnapshot = true
        return snapshot
    }
    func upsert(snapshot: SoloRemoteSnapshot) async throws {
        upserted.tasks.append(contentsOf: snapshot.tasks)
        upserted.taskLists.append(contentsOf: snapshot.taskLists)
        upserted.projects.append(contentsOf: snapshot.projects)
        upserted.projectSubtasks.append(contentsOf: snapshot.projectSubtasks)
        upserted.periodicTasks.append(contentsOf: snapshot.periodicTasks)
    }
}

private struct SoloSyncHarness {
    let container: ModelContainer
    let remote = FakeSoloRemoteGateway()
    let metadata: SoloSyncMetadataStore
    let service: SupabaseSoloSyncService
    let userID = UUID()

    init() throws {
        container = try ModelContainer(
            for: PersistentUserProfile.self, PersistentSpace.self, PersistentPairSpace.self,
            PersistentPairMembership.self, PersistentInvite.self, PersistentTaskList.self,
            PersistentProject.self, PersistentProjectSubtask.self, PersistentItem.self,
            PersistentItemOccurrenceCompletion.self, PersistentTaskTemplate.self,
            PersistentSyncChange.self, PersistentSyncState.self, PersistentPeriodicTask.self,
            PersistentPairingHistory.self, PersistentTaskMessage.self, PersistentImportantDate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = UserDefaults(suiteName: "SoloSyncHarness.\(UUID().uuidString)")!
        metadata = SoloSyncMetadataStore(defaults: defaults)
        service = SupabaseSoloSyncService(
            modelContainer: container,
            remote: remote,
            metadata: metadata,
            installationIDProvider: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! },
            appVersionProvider: { "1.0" },
            buildNumberProvider: { "13" }
        )
    }
}
```

Add this local test helper in the same test file:

```swift
private extension PersistentItem {
    static func sample(id: UUID, spaceID: UUID, creatorID: UUID, title: String) -> PersistentItem {
        PersistentItem(
            id: id,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: creatorID,
            title: title,
            notes: nil,
            locationText: nil,
            executionRoleRawValue: ItemExecutionRole.initiator.rawValue,
            assigneeModeRawValue: "self",
            dueAt: nil,
            hasExplicitTime: false,
            remindAt: nil,
            statusRawValue: ItemStatus.pendingConfirmation.rawValue,
            assignmentStateRawValue: TaskAssignmentState.active.rawValue,
            latestResponseData: nil,
            responseHistoryData: Data(),
            assignmentMessagesData: Data(),
            lastActionByUserID: nil,
            lastActionAt: nil,
            createdAt: .now,
            updatedAt: .now,
            completedAt: nil,
            completedByUserID: nil,
            isPinned: false,
            isDraft: false,
            isArchived: false,
            archivedAt: nil,
            repeatRuleData: nil,
            reminderRequestedAt: nil,
            isLocallyDeleted: false
        )
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloSyncServiceTests
```

Expected:

```text
Cannot find 'SupabaseSoloSyncService' in scope
```

- [ ] **Step 3: Implement service skeleton and branches**

Create `Together/Sync/Solo/SupabaseSoloSyncService.swift`:

```swift
import Foundation
import SwiftData
import os

enum SoloSyncServiceError: Error, Equatable {
    case requiresPro
    case missingSingleSpace
}

actor SupabaseSoloSyncService {
    private let modelContainer: ModelContainer
    private let remote: SupabaseSoloRemoteGatewayProtocol
    private let metadata: SoloSyncMetadataStore
    private let logger = Logger(subsystem: "com.pigdog.Together", category: "SupabaseSoloSync")
    private let installationIDProvider: @Sendable () -> UUID
    private let appVersionProvider: @Sendable () -> String?
    private let buildNumberProvider: @Sendable () -> String?

    init(
        modelContainer: ModelContainer,
        remote: SupabaseSoloRemoteGatewayProtocol = SupabaseSoloRemoteGateway(),
        metadata: SoloSyncMetadataStore = SoloSyncMetadataStore(),
        installationIDProvider: @escaping @Sendable () -> UUID = { InstallationIDStore.current },
        appVersionProvider: @escaping @Sendable () -> String? = { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String },
        buildNumberProvider: @escaping @Sendable () -> String? = { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    ) {
        self.modelContainer = modelContainer
        self.remote = remote
        self.metadata = metadata
        self.installationIDProvider = installationIDProvider
        self.appVersionProvider = appVersionProvider
        self.buildNumberProvider = buildNumberProvider
    }

    func start(
        userID: UUID,
        localUserID: UUID,
        displayName: String,
        platform: SoloDevicePlatform,
        isPro: Bool
    ) async throws {
        guard SoloSyncGate.decision(platform: platform, isPro: isPro) == .allowed else {
            throw SoloSyncServiceError.requiresPro
        }

        let spaceID = try await remote.ensureSingleSpace(userID: userID, displayName: displayName)
        try reconcileLocalSingleSpace(remoteSpaceID: spaceID, userID: localUserID, displayName: displayName)
        try await remote.registerDevice(DeviceInstallationUpsertDTO(
            userID: userID,
            installationID: installationIDProvider(),
            platform: platform,
            deviceName: nil,
            appVersion: appVersionProvider(),
            buildNumber: buildNumberProvider()
        ))

        let localState = try classifyLocalState(spaceID: spaceID)
        switch localState {
        case .freshInstall:
            try await fullPull(spaceID: spaceID)
        case .needsBootstrap:
            try await bootstrapLocalData(spaceID: spaceID, userID: userID)
        case .hasBaseline:
            try await pushPending(spaceID: spaceID, userID: userID)
            try await pullDeltas(spaceID: spaceID)
        }
    }
}
```

Add installation ID persistence in the same file:

```swift
private enum InstallationIDStore {
    private static let key = "together.installationID"

    static var current: UUID {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
```

Also implement the private helpers in the same file:

```swift
private enum SoloLocalState {
    case freshInstall
    case needsBootstrap
    case hasBaseline
}

private extension SupabaseSoloSyncService {
    func reconcileLocalSingleSpace(remoteSpaceID: UUID, userID: UUID, displayName: String) throws {
        let context = ModelContext(modelContainer)
        let spaces = try context.fetch(FetchDescriptor<PersistentSpace>())
        let activeSingles = spaces.filter {
            $0.typeRawValue == SpaceType.single.rawValue &&
            $0.statusRawValue != SpaceStatus.archived.rawValue
        }

        if let exact = activeSingles.first(where: { $0.id == remoteSpaceID }) {
            exact.ownerUserID = userID
            exact.displayName = exact.displayName.isEmpty ? displayName : exact.displayName
            try context.save()
            return
        }

        let dataBearingSpaceID = try dataBearingSingleSpaceID(context: context)
        if let oldID = dataBearingSpaceID,
           let existing = activeSingles.first(where: { $0.id == oldID }) {
            existing.id = remoteSpaceID
            existing.ownerUserID = userID
            existing.updatedAt = .now
            try reassignSoloData(from: oldID, to: remoteSpaceID, context: context)
            try context.save()
            return
        }

        let now = Date()
        context.insert(PersistentSpace(space: Space(
            id: remoteSpaceID,
            type: .single,
            displayName: displayName.isEmpty ? "我的空间" : displayName,
            ownerUserID: userID,
            status: .active,
            createdAt: now,
            updatedAt: now
        )))
        try context.save()
    }

    func dataBearingSingleSpaceID(context: ModelContext) throws -> UUID? {
        if let item = try context.fetch(FetchDescriptor<PersistentItem>()).first(where: { $0.spaceID != nil && !$0.isLocallyDeleted }) {
            return item.spaceID
        }
        if let list = try context.fetch(FetchDescriptor<PersistentTaskList>()).first(where: { !$0.isLocallyDeleted }) {
            return list.spaceID
        }
        if let project = try context.fetch(FetchDescriptor<PersistentProject>()).first(where: { !$0.isLocallyDeleted }) {
            return project.spaceID
        }
        if let periodic = try context.fetch(FetchDescriptor<PersistentPeriodicTask>()).first(where: { $0.spaceID != nil && !$0.isLocallyDeleted }) {
            return periodic.spaceID
        }
        return nil
    }

    func reassignSoloData(from oldSpaceID: UUID, to newSpaceID: UUID, context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<PersistentItem>()) where item.spaceID == oldSpaceID {
            item.spaceID = newSpaceID
        }
        for list in try context.fetch(FetchDescriptor<PersistentTaskList>()) where list.spaceID == oldSpaceID {
            list.spaceID = newSpaceID
        }
        for project in try context.fetch(FetchDescriptor<PersistentProject>()) where project.spaceID == oldSpaceID {
            project.spaceID = newSpaceID
        }
        for periodic in try context.fetch(FetchDescriptor<PersistentPeriodicTask>()) where periodic.spaceID == oldSpaceID {
            periodic.spaceID = newSpaceID
        }
        for change in try context.fetch(FetchDescriptor<PersistentSyncChange>()) where change.spaceID == oldSpaceID {
            change.spaceID = newSpaceID
        }
    }

    func classifyLocalState(spaceID: UUID) throws -> SoloLocalState {
        if metadata.migrationCompletedAt(spaceID: spaceID) != nil {
            return .hasBaseline
        }
        let context = ModelContext(modelContainer)
        let hasLocalData =
            ((try? context.fetchCount(FetchDescriptor<PersistentItem>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<PersistentTaskList>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<PersistentProject>())) ?? 0) > 0 ||
            ((try? context.fetchCount(FetchDescriptor<PersistentPeriodicTask>())) ?? 0) > 0
        return hasLocalData ? .needsBootstrap : .freshInstall
    }

    func fullPull(spaceID: UUID) async throws {
        let snapshot = try await remote.fetchSnapshot(spaceID: spaceID, since: nil)
        try apply(snapshot: snapshot)
        let now = Date()
        metadata.setLastPulledAt(now, spaceID: spaceID)
        metadata.markMigrationCompleted(spaceID: spaceID, at: now, build: buildNumberProvider())
    }

    func bootstrapLocalData(spaceID: UUID, userID: UUID) async throws {
        let remoteSnapshot = try await remote.fetchSnapshot(spaceID: spaceID, since: nil)
        try apply(snapshot: remoteSnapshot)
        let localSnapshot = try makeLocalSnapshot(spaceID: spaceID, supabaseUserID: userID)
        try await remote.upsert(snapshot: localSnapshot)
        let now = Date()
        metadata.setLastPushedAt(now, spaceID: spaceID)
        metadata.setLastPulledAt(now, spaceID: spaceID)
        metadata.markMigrationCompleted(spaceID: spaceID, at: now, build: buildNumberProvider())
    }

    func makeLocalSnapshot(spaceID: UUID, supabaseUserID: UUID) throws -> SoloRemoteSnapshot {
        let context = ModelContext(modelContainer)
        var snapshot = SoloRemoteSnapshot()
        snapshot.taskLists = try context.fetch(FetchDescriptor<PersistentTaskList>(
            predicate: #Predicate { $0.spaceID == spaceID }
        )).map { TaskListDTO(from: $0, spaceID: spaceID) }
        snapshot.projects = try context.fetch(FetchDescriptor<PersistentProject>(
            predicate: #Predicate { $0.spaceID == spaceID }
        )).map { ProjectDTO(from: $0, spaceID: spaceID) }
        let projectIDs = Set(snapshot.projects.map(\.id))
        snapshot.projectSubtasks = try context.fetch(FetchDescriptor<PersistentProjectSubtask>()).compactMap { subtask in
            projectIDs.contains(subtask.projectID) ? ProjectSubtaskDTO(from: subtask, spaceID: spaceID) : nil
        }
        snapshot.periodicTasks = try context.fetch(FetchDescriptor<PersistentPeriodicTask>(
            predicate: #Predicate { $0.spaceID == spaceID }
        )).map { PeriodicTaskDTO(from: $0, spaceID: spaceID) }
        snapshot.tasks = try context.fetch(FetchDescriptor<PersistentItem>(
            predicate: #Predicate { $0.spaceID == spaceID }
        )).map { TaskDTO(from: $0, spaceID: spaceID, supabaseUserID: supabaseUserID) }
        return snapshot
    }

    func apply(snapshot: SoloRemoteSnapshot) throws {
        let context = ModelContext(modelContainer)
        for row in snapshot.taskLists { row.applyToLocal(context: context) }
        for row in snapshot.projects { row.applyToLocal(context: context) }
        for row in snapshot.projectSubtasks { row.applyToLocal(context: context) }
        for row in snapshot.periodicTasks { row.applyToLocal(context: context) }
        for row in snapshot.tasks { row.applyToLocal(context: context) }
        try context.save()
    }

    func pullDeltas(spaceID: UUID) async throws {
        let snapshot = try await remote.fetchSnapshot(spaceID: spaceID, since: metadata.lastPulledAt(spaceID: spaceID))
        try apply(snapshot: snapshot)
        metadata.setLastPulledAt(Date(), spaceID: spaceID)
    }
}
```

Add this `pushPending` implementation in Task 5 so established-baseline startup compiles before Task 6 adds outbox draining:

```swift
func pushPending(spaceID: UUID, userID: UUID) async throws {}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloSyncServiceTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Solo/SupabaseSoloSyncService.swift TogetherTests/SupabaseSoloSyncServiceTests.swift
git commit -m "feat(sync): add solo Supabase bootstrap"
```

---

## Task 6: Drain Solo Outbox to Supabase

**Files:**
- Modify: `Together/Sync/Solo/SupabaseSoloSyncService.swift`
- Test: `TogetherTests/SupabaseSoloSyncServiceTests.swift`

- [ ] **Step 1: Add failing outbox test**

Append to `SupabaseSoloSyncServiceTests`:

```swift
@Test("baseline startup pushes pending solo changes")
func baselineStartupPushesPendingChanges() async throws {
    let harness = try SoloSyncHarness()
    let spaceID = UUID()
    let taskID = UUID()
    harness.remote.spaceID = spaceID
    harness.metadata.markMigrationCompleted(spaceID: spaceID, at: .now, build: "13")

    let context = ModelContext(harness.container)
    context.insert(PersistentSpace(space: Space(id: spaceID, type: .single, displayName: "我的空间", ownerUserID: harness.userID, status: .active, createdAt: .now, updatedAt: .now)))
    context.insert(PersistentItem.sample(id: taskID, spaceID: spaceID, creatorID: harness.userID, title: "pending task"))
    context.insert(PersistentSyncChange(change: SyncChange(entityKind: .task, operation: .upsert, recordID: taskID, spaceID: spaceID)))
    try context.save()

    try await harness.service.start(userID: harness.userID, localUserID: harness.userID, displayName: "我", platform: .iphone, isPro: false)

    #expect(harness.remote.upserted.tasks.map(\.id) == [taskID])
    let remaining = try context.fetch(FetchDescriptor<PersistentSyncChange>())
    #expect(remaining.isEmpty)
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloSyncServiceTests/baselineStartupPushesPendingChanges
```

Expected:

```text
Expectation failed: remaining.isEmpty
```

- [ ] **Step 3: Implement outbox drain**

In `SupabaseSoloSyncService.swift`, implement:

```swift
func pushPending(spaceID: UUID, userID: UUID) async throws {
    let context = ModelContext(modelContainer)
    let pendingRaw = SyncMutationLifecycleState.pending.rawValue
    let failedRaw = SyncMutationLifecycleState.failed.rawValue
    let changes = try context.fetch(FetchDescriptor<PersistentSyncChange>(
        predicate: #Predicate {
            $0.spaceID == spaceID &&
            ($0.lifecycleStateRawValue == pendingRaw || $0.lifecycleStateRawValue == failedRaw)
        },
        sortBy: [SortDescriptor(\.changedAt)]
    ))

    guard changes.isEmpty == false else { return }

    var snapshot = SoloRemoteSnapshot()
    for change in changes {
        let kind = SyncEntityKind(rawValue: change.entityKindRawValue) ?? .task
        switch kind {
        case .task:
            if let row = try localTaskDTO(id: change.recordID, spaceID: spaceID, userID: userID, context: context) {
                snapshot.tasks.append(row)
            }
        case .taskList:
            if let row = try localTaskListDTO(id: change.recordID, spaceID: spaceID, context: context) {
                snapshot.taskLists.append(row)
            }
        case .project:
            if let row = try localProjectDTO(id: change.recordID, spaceID: spaceID, context: context) {
                snapshot.projects.append(row)
            }
        case .projectSubtask:
            if let row = try localProjectSubtaskDTO(id: change.recordID, spaceID: spaceID, context: context) {
                snapshot.projectSubtasks.append(row)
            }
        case .periodicTask:
            if let row = try localPeriodicTaskDTO(id: change.recordID, spaceID: spaceID, context: context) {
                snapshot.periodicTasks.append(row)
            }
        default:
            continue
        }
        change.lifecycleStateRawValue = SyncMutationLifecycleState.sending.rawValue
        change.lastAttemptedAt = Date()
    }
    try context.save()

    do {
        try await remote.upsert(snapshot: snapshot)
        for change in changes {
            context.delete(change)
        }
        try context.save()
        metadata.setLastPushedAt(Date(), spaceID: spaceID)
    } catch {
        for change in changes {
            change.lifecycleStateRawValue = SyncMutationLifecycleState.failed.rawValue
            change.lastError = error.localizedDescription
        }
        try? context.save()
        throw error
    }
}
```

Implement `localTaskDTO`, `localTaskListDTO`, `localProjectDTO`, `localProjectSubtaskDTO`, and `localPeriodicTaskDTO` as small fetch helpers in the same private extension.

- [ ] **Step 4: Run solo sync service tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloSyncServiceTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Solo/SupabaseSoloSyncService.swift TogetherTests/SupabaseSoloSyncServiceTests.swift
git commit -m "feat(sync): push solo outbox to Supabase"
```

---

## Task 7: Wire Solo Sync into App Startup

**Files:**
- Modify: `Together/App/AppContainer.swift`
- Modify: `Together/Services/LocalServiceFactory.swift`
- Modify: `Together/App/AppContext.swift`

- [ ] **Step 1: Add container property**

Modify `Together/App/AppContainer.swift`:

```swift
let supabaseSoloSyncService: SupabaseSoloSyncService
```

Place it near the existing sync services.

- [ ] **Step 2: Construct service**

Modify `Together/Services/LocalServiceFactory.swift`:

```swift
let supabaseSoloSyncService = SupabaseSoloSyncService(modelContainer: modelContainer)
```

Pass it into `AppContainer(...)`.

- [ ] **Step 3: Start service after Supabase auth restore**

Modify `Together/App/AppContext.swift` inside `performPostLaunchWorkIfNeeded()` after `_ = await supabaseAuth.restoreSession()` and `await configurePremiumGate()`:

```swift
if let supabaseUserID = await supabaseAuth.currentUserID,
   let localUserID = sessionStore.currentUser?.id {
    do {
        try await container.supabaseSoloSyncService.start(
            userID: supabaseUserID,
            localUserID: localUserID,
            displayName: sessionStore.currentUser?.displayName ?? "我",
            platform: .current,
            isPro: container.premiumGate.isPremium
        )
    } catch SoloSyncServiceError.requiresPro {
        appContextLogger.info("Solo Supabase sync blocked by Pro gate on this platform")
    } catch {
        appContextLogger.error("Solo Supabase sync failed: \(error.localizedDescription)")
    }
}
```

Keep `startSoloSyncEngineIfNeeded()` temporarily after this block until CloudKit import retirement is implemented.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/App/AppContainer.swift Together/Services/LocalServiceFactory.swift Together/App/AppContext.swift
git commit -m "feat(sync): start solo Supabase recovery"
```

---

## Task 8: Add Solo Sync Diagnostics

**Files:**
- Create: `Together/Sync/Solo/SoloSyncDiagnostics.swift`
- Modify: `Together/Sync/Solo/SupabaseSoloSyncService.swift`
- Test: `TogetherTests/SupabaseSoloSyncServiceTests.swift`

- [ ] **Step 1: Add failing diagnostics test**

Append:

```swift
@Test("diagnostics reports local and remote counts")
func diagnosticsReportsCounts() async throws {
    let harness = try SoloSyncHarness()
    let spaceID = UUID()
    harness.remote.spaceID = spaceID
    harness.remote.snapshot.tasks = [
        TaskDTO.fixture(id: UUID(), spaceID: spaceID, title: "remote")
    ]

    let snapshot = try await harness.service.diagnostics(
        userID: harness.userID,
        platform: .iphone,
        isPro: false
    )

    #expect(snapshot.platform == .iphone)
    #expect(snapshot.gateDecision == .allowed)
    #expect(snapshot.remoteTaskCount == 1)
}
```

- [ ] **Step 2: Implement diagnostics model**

Create `Together/Sync/Solo/SoloSyncDiagnostics.swift`:

```swift
import Foundation

struct SoloSyncDiagnosticSnapshot: Hashable, Sendable {
    let userID: UUID
    let spaceID: UUID?
    let platform: SoloDevicePlatform
    let gateDecision: SoloSyncGateDecision
    let localTaskCount: Int
    let remoteTaskCount: Int
    let pendingMutationCount: Int
    let failedMutationCount: Int
    let lastPulledAt: Date?
    let lastPushedAt: Date?
    let migrationCompletedAt: Date?
    let lastError: String?
}
```

- [ ] **Step 3: Implement diagnostics method**

In `SupabaseSoloSyncService`:

```swift
func diagnostics(userID: UUID, platform: SoloDevicePlatform, isPro: Bool) async throws -> SoloSyncDiagnosticSnapshot {
    let gate = SoloSyncGate.decision(platform: platform, isPro: isPro)
    let spaceID = try? await remote.ensureSingleSpace(userID: userID, displayName: "我")
    let context = ModelContext(modelContainer)
    let localTaskCount = (try? context.fetchCount(FetchDescriptor<PersistentItem>())) ?? 0
    let pendingRaw = SyncMutationLifecycleState.pending.rawValue
    let failedRaw = SyncMutationLifecycleState.failed.rawValue
    let pending = (try? context.fetchCount(FetchDescriptor<PersistentSyncChange>(predicate: #Predicate { $0.lifecycleStateRawValue == pendingRaw }))) ?? 0
    let failed = (try? context.fetchCount(FetchDescriptor<PersistentSyncChange>(predicate: #Predicate { $0.lifecycleStateRawValue == failedRaw }))) ?? 0
    let remoteSnapshot = try await remote.fetchSnapshot(spaceID: spaceID ?? UUID(), since: nil)

    return SoloSyncDiagnosticSnapshot(
        userID: userID,
        spaceID: spaceID,
        platform: platform,
        gateDecision: gate,
        localTaskCount: localTaskCount,
        remoteTaskCount: remoteSnapshot.tasks.count,
        pendingMutationCount: pending,
        failedMutationCount: failed,
        lastPulledAt: spaceID.flatMap { metadata.lastPulledAt(spaceID: $0) },
        lastPushedAt: spaceID.flatMap { metadata.lastPushedAt(spaceID: $0) },
        migrationCompletedAt: spaceID.flatMap { metadata.migrationCompletedAt(spaceID: $0) },
        lastError: nil
    )
}
```

- [ ] **Step 4: Run diagnostics test**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TogetherTests/SupabaseSoloSyncServiceTests/diagnosticsReportsCounts
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Solo/SoloSyncDiagnostics.swift Together/Sync/Solo/SupabaseSoloSyncService.swift TogetherTests/SupabaseSoloSyncServiceTests.swift
git commit -m "feat(sync): add solo sync diagnostics"
```

---

## Task 9: Verification and TestFlight Readiness

**Files:**
- No required source changes.
- Update this plan checklist as tasks complete.

- [ ] **Step 1: Run focused tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TogetherTests/SoloSyncGateTests \
  -only-testing:TogetherTests/SoloSyncMetadataStoreTests \
  -only-testing:TogetherTests/SupabaseSoloRemoteGatewayDTOTests \
  -only-testing:TogetherTests/SupabaseSoloSyncServiceTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: Run full tests**

Run:

```bash
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 3: Run Supabase verification queries**

Run via Supabase MCP:

```sql
select count(*) from public.device_installations;
select type, count(*) from public.spaces group by type order by type;
```

Expected:

```text
device_installations exists; spaces can contain single and pair rows.
```

- [ ] **Step 4: Manual TestFlight test**

Manual steps:

1. Install new build on iPhone A.
2. Sign in and confirm Pro/free status does not block iPhone sync.
3. Create task `solo-recovery-smoke`.
4. Wait until diagnostics show remote task count includes it and pending count is 0.
5. Delete App.
6. Reinstall the same build.
7. Sign in with same Apple ID.
8. Confirm `solo-recovery-smoke` returns.
9. Install on iPhone B with same Apple ID.
10. Confirm `solo-recovery-smoke` returns.

- [ ] **Step 5: Commit verification note if docs changed**

```bash
git status --short
```

Expected:

```text
No source changes unless checklist/docs were intentionally updated.
```
