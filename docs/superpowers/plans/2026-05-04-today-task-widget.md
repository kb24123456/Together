# Today Task Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first-stage Today task widgets: small Focus, small List, and medium List, with App Group snapshot sharing, Today deep link, and interactive completion through App Intents.

**Architecture:** Move shared widget state into an App Group container and expose a small `TodayWidgetSnapshot` surface consumed by WidgetKit. Keep Today as the source of truth by generating snapshots from the same task ordering semantics, and make completion extension-safe through a gateway that reuses `DefaultTaskApplicationService` with the App Group SwiftData store. Add a Today deep link for all non-completion widget taps.

**Tech Stack:** Swift 6.2, SwiftUI, WidgetKit, AppIntents, SwiftData, Swift Testing/XCTest in the existing `TogetherTests` target, Xcode 26.2.

**Design Spec:** `docs/superpowers/specs/2026-05-04-today-task-widget-design.md`

---

## Scope Check

This plan implements only stage 1 from the spec: Today task widgets. It does not implement the stage 2 double-mode anniversary widget. The plan intentionally front-loads App Group, SwiftData store migration, Today deep link, and extension-safe completion because those are the risky cross-process foundations. Widget UI comes after the data and intent seams compile.

The plan keeps the current project rule of working on `main` and validating with `generic/platform=iOS` builds. Focused test steps use `build-for-testing` as compile gates, not simulator execution. If the user later permits simulator testing, run the same focused suites with a concrete simulator destination.

## File Structure

### Shared Widget Infrastructure

- Create: `Together/WidgetSupport/TodayWidgetConstants.swift`
  - App Group id, widget kind ids, deeplink URL, shared file names.
  - Target membership: app target + widget extension target + tests as needed.
- Create: `Together/WidgetSupport/TodayWidgetSnapshot.swift`
  - Codable snapshot and task row DTOs.
  - Target membership: app target + widget extension target + tests.
- Create: `Together/WidgetSupport/TodayWidgetSnapshotStore.swift`
  - Reads/writes JSON snapshot in the App Group container.
  - Target membership: app target + widget extension target + tests.
- Create: `Together/WidgetSupport/TodayWidgetSnapshotBuilder.swift`
  - Converts current-space Today items into the widget snapshot.
  - App target + tests.
- Create: `Together/WidgetSupport/TodayWidgetTaskCompletionGateway.swift`
  - Extension-safe completion gateway used by the App Intent.
  - App target + widget extension target + tests.

### Persistence / App Group

- Modify: `Together/Together.entitlements`
  - Add `com.apple.security.application-groups` with `group.com.pigdog.together.shared`.
- Create: `TogetherWidget/TogetherWidget.entitlements`
  - Widget extension entitlements with the same App Group.
- Modify: `Together/Persistence/PersistenceController.swift`
  - Add App Group store URL resolution.
  - Add one-time migration from the existing Application Support store to App Group store.
  - Keep preview/in-memory behavior unchanged.

### Deep Link

- Modify: `Together/Services/DeepLinkConfiguration.swift`
  - Add `together://today` URL builder/parser.
- Modify: `Together/App/AppContext.swift`
  - Route Today deep links to `router.currentSurface = .today`.
- Modify: `Together/Info.plist`
  - Add `CFBundleURLTypes` for the `together` scheme.

### Widget Extension

- Create: `TogetherWidget/TogetherWidgetBundle.swift`
- Create: `TogetherWidget/TodayFocusWidget.swift`
- Create: `TogetherWidget/TodayListWidget.swift`
- Create: `TogetherWidget/TodayWidgetViews.swift`
- Create: `TogetherWidget/CompleteTodayWidgetTaskIntent.swift`
- Create: `TogetherWidget/Info.plist`
- Modify: `Together.xcodeproj/project.pbxproj`
  - Add the Widget Extension target, files, build settings, entitlements, and embed extension phase.

### App Integration

- Modify: `Together/App/AppContext.swift`
  - Write widget snapshots after post-launch work, foreground refresh, and task mutation reload paths.
- Modify: `Together/Features/Home/HomeViewModel.swift`
  - Add a small hook for snapshot generation after Today data changes, or expose a sorted active Today list through a dedicated method if `AppContext` is the better integration point.
- Modify: `Together/Services/LocalServiceFactory.swift`
  - Ensure any app-side snapshot writer can access `ItemRepositoryProtocol`.

### Tests

- Create: `TogetherTests/TodayWidgetSnapshotStoreTests.swift`
- Create: `TogetherTests/TodayWidgetSnapshotBuilderTests.swift`
- Create: `TogetherTests/TodayWidgetDeepLinkTests.swift`
- Create: `TogetherTests/TodayWidgetTaskCompletionGatewayTests.swift`
- Create: `TogetherTests/PersistenceAppGroupStoreTests.swift`

---

## Task 1: Add App Group Constants and Store URL Resolution

**Files:**
- Create: `Together/WidgetSupport/TodayWidgetConstants.swift`
- Modify: `Together/Persistence/PersistenceController.swift`
- Test: `TogetherTests/PersistenceAppGroupStoreTests.swift`

- [ ] **Step 1: Write failing tests for App Group store URL fallback**

Create `TogetherTests/PersistenceAppGroupStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("Persistence App Group Store")
struct PersistenceAppGroupStoreTests {
    @Test("uses injected app group container when available")
    func usesInjectedAppGroupContainer() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let resolved = PersistenceController.resolvedPersistentStoreURL(appGroupContainerURL: root)

        #expect(resolved == root.appending(path: "Together.store"))
    }

    @Test("falls back to legacy application support directory when app group unavailable")
    func fallsBackToLegacyDirectory() {
        let resolved = PersistenceController.resolvedPersistentStoreURL(appGroupContainerURL: nil)

        #expect(resolved.lastPathComponent == "Together.store")
        #expect(resolved.path.contains("Together"))
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/PersistenceAppGroupStoreTests -quiet
```

Expected: BUILD FAILS because `PersistenceController.resolvedPersistentStoreURL(appGroupContainerURL:)` does not exist yet.

- [ ] **Step 3: Add shared widget constants**

Create `Together/WidgetSupport/TodayWidgetConstants.swift`:

```swift
import Foundation

enum TodayWidgetConstants {
    static let appGroupIdentifier = "group.com.pigdog.together.shared"

    static let focusWidgetKind = "com.pigdog.Together.widgets.today-focus"
    static let listWidgetKind = "com.pigdog.Together.widgets.today-list"

    static let snapshotFileName = "today-widget-snapshot.json"

    static var todayDeepLink: URL {
        URL(string: "together://today")!
    }
}
```

- [ ] **Step 4: Add App Group-aware URL resolution without migration yet**

Modify `Together/Persistence/PersistenceController.swift` by replacing `persistentStoreURL` with a resolver-backed implementation:

```swift
static var persistentStoreURL: URL {
    resolvedPersistentStoreURL(
        appGroupContainerURL: FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    )
}

static func resolvedPersistentStoreURL(appGroupContainerURL: URL?) -> URL {
    if let appGroupContainerURL {
        if FileManager.default.fileExists(atPath: appGroupContainerURL.path) == false {
            try? FileManager.default.createDirectory(at: appGroupContainerURL, withIntermediateDirectories: true)
        }
        return appGroupContainerURL.appending(path: "Together.store")
    }

    let applicationSupportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first ?? URL.documentsDirectory

    let directory = applicationSupportDirectory.appendingPathComponent("Together", isDirectory: true)

    if FileManager.default.fileExists(atPath: directory.path) == false {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    return directory.appendingPathComponent("Together.store")
}
```

- [ ] **Step 5: Run the focused tests and verify they pass**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/PersistenceAppGroupStoreTests -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 6: Commit**

```bash
git add Together/WidgetSupport/TodayWidgetConstants.swift Together/Persistence/PersistenceController.swift TogetherTests/PersistenceAppGroupStoreTests.swift
git commit -m "feat: add app group store resolution"
```

## Task 2: Add Safe Store Migration to App Group

**Files:**
- Modify: `Together/Persistence/PersistenceController.swift`
- Test: `TogetherTests/PersistenceAppGroupStoreTests.swift`

- [ ] **Step 1: Add failing tests for store artifact migration**

Append to `TogetherTests/PersistenceAppGroupStoreTests.swift`:

```swift
@Test("migrates sqlite store artifacts into app group when destination is empty")
func migratesStoreArtifactsIntoAppGroupWhenDestinationEmpty() throws {
    let legacyRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let appGroupRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)

    let legacyStore = legacyRoot.appending(path: "Together.store")
    let groupStore = appGroupRoot.appending(path: "Together.store")
    try Data("store".utf8).write(to: legacyStore)
    try Data("wal".utf8).write(to: legacyStore.deletingPathExtension().appendingPathExtension("store-wal"))
    try Data("shm".utf8).write(to: legacyStore.deletingPathExtension().appendingPathExtension("store-shm"))

    try PersistenceController.migrateStoreArtifactsIfNeeded(
        legacyStoreURL: legacyStore,
        appGroupStoreURL: groupStore
    )

    #expect(FileManager.default.fileExists(atPath: groupStore.path))
    #expect(FileManager.default.fileExists(atPath: groupStore.deletingPathExtension().appendingPathExtension("store-wal").path))
    #expect(FileManager.default.fileExists(atPath: groupStore.deletingPathExtension().appendingPathExtension("store-shm").path))
}

@Test("does not overwrite existing app group store")
func doesNotOverwriteExistingAppGroupStore() throws {
    let legacyRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let appGroupRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)

    let legacyStore = legacyRoot.appending(path: "Together.store")
    let groupStore = appGroupRoot.appending(path: "Together.store")
    try Data("legacy".utf8).write(to: legacyStore)
    try Data("group".utf8).write(to: groupStore)

    try PersistenceController.migrateStoreArtifactsIfNeeded(
        legacyStoreURL: legacyStore,
        appGroupStoreURL: groupStore
    )

    let data = try Data(contentsOf: groupStore)
    #expect(String(decoding: data, as: UTF8.self) == "group")
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/PersistenceAppGroupStoreTests -quiet
```

Expected: BUILD FAILS because `migrateStoreArtifactsIfNeeded` does not exist.

- [ ] **Step 3: Implement artifact migration**

Add to `Together/Persistence/PersistenceController.swift` near the existing store URL helpers:

```swift
static func migrateStoreArtifactsIfNeeded(
    legacyStoreURL: URL,
    appGroupStoreURL: URL
) throws {
    guard legacyStoreURL != appGroupStoreURL else { return }
    guard FileManager.default.fileExists(atPath: legacyStoreURL.path) else { return }
    guard FileManager.default.fileExists(atPath: appGroupStoreURL.path) == false else { return }

    try FileManager.default.createDirectory(
        at: appGroupStoreURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    for source in storeArtifactURLs(for: legacyStoreURL) where FileManager.default.fileExists(atPath: source.path) {
        let destination = appGroupStoreURL.deletingLastPathComponent().appending(path: source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) == false {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }
}

static func storeArtifactURLs(for storeURL: URL) -> [URL] {
    let base = storeURL.deletingLastPathComponent()
        .appendingPathComponent(storeURL.deletingPathExtension().lastPathComponent)
    return ["store", "store-shm", "store-wal"].map { base.appendingPathExtension($0) }
}
```

Then call migration before opening the persistent store:

```swift
private static func migrateToAppGroupStoreIfNeeded() {
    guard let appGroupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
    ) else { return }

    let legacyURL = legacyApplicationSupportStoreURL()
    let groupURL = appGroupURL.appending(path: "Together.store")
    try? migrateStoreArtifactsIfNeeded(legacyStoreURL: legacyURL, appGroupStoreURL: groupURL)
}

private static func legacyApplicationSupportStoreURL() -> URL {
    let applicationSupportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first ?? URL.documentsDirectory
    let directory = applicationSupportDirectory.appendingPathComponent("Together", isDirectory: true)
    return directory.appendingPathComponent("Together.store")
}
```

Call `Self.migrateToAppGroupStoreIfNeeded()` at the start of `init(inMemory:)` when `inMemory == false`.

- [ ] **Step 4: Run migration tests**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/PersistenceAppGroupStoreTests -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add Together/Persistence/PersistenceController.swift TogetherTests/PersistenceAppGroupStoreTests.swift
git commit -m "feat: migrate store into app group"
```

## Task 3: Add Today Widget Snapshot Model and Store

**Files:**
- Create: `Together/WidgetSupport/TodayWidgetSnapshot.swift`
- Create: `Together/WidgetSupport/TodayWidgetSnapshotStore.swift`
- Test: `TogetherTests/TodayWidgetSnapshotStoreTests.swift`

- [ ] **Step 1: Write failing tests for snapshot persistence**

Create `TogetherTests/TodayWidgetSnapshotStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("Today Widget Snapshot Store")
struct TodayWidgetSnapshotStoreTests {
    @Test("writes and reads a snapshot")
    func writesAndReadsSnapshot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = TodayWidgetSnapshotStore(containerURL: root)
        let taskID = UUID()
        let snapshot = TodayWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_777_837_512),
            referenceDate: Date(timeIntervalSince1970: 1_777_800_000),
            remainingCount: 1,
            tasks: [
                TodayWidgetTaskSnapshot(
                    id: taskID,
                    title: "核对审核备注",
                    dueTimeText: "18:00",
                    sortIndex: 0
                )
            ]
        )

        try store.write(snapshot)
        let read = try store.read()

        #expect(read == snapshot)
    }

    @Test("returns fallback empty snapshot when file missing")
    func returnsFallbackWhenMissing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let store = TodayWidgetSnapshotStore(containerURL: root)

        let read = try store.read()

        #expect(read.remainingCount == 0)
        #expect(read.tasks.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetSnapshotStoreTests -quiet
```

Expected: BUILD FAILS because the snapshot types do not exist.

- [ ] **Step 3: Add snapshot DTOs**

Create `Together/WidgetSupport/TodayWidgetSnapshot.swift`:

```swift
import Foundation

struct TodayWidgetSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var referenceDate: Date
    var remainingCount: Int
    var tasks: [TodayWidgetTaskSnapshot]

    static var empty: Self {
        TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: .now,
            remainingCount: 0,
            tasks: []
        )
    }
}

struct TodayWidgetTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var dueTimeText: String?
    var sortIndex: Int
}
```

- [ ] **Step 4: Add JSON snapshot store**

Create `Together/WidgetSupport/TodayWidgetSnapshotStore.swift`:

```swift
import Foundation

struct TodayWidgetSnapshotStore: Sendable {
    private let containerURL: URL?

    init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.containerURL = containerURL
    }

    func read() throws -> TodayWidgetSnapshot {
        guard let fileURL else { return .empty }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.todayWidget.decode(TodayWidgetSnapshot.self, from: data)
    }

    func write(_ snapshot: TodayWidgetSnapshot) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.todayWidget.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private var fileURL: URL? {
        containerURL?.appending(path: TodayWidgetConstants.snapshotFileName)
    }
}

private extension JSONEncoder {
    static var todayWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var todayWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 5: Run snapshot store tests**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetSnapshotStoreTests -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 6: Commit**

```bash
git add Together/WidgetSupport/TodayWidgetSnapshot.swift Together/WidgetSupport/TodayWidgetSnapshotStore.swift TogetherTests/TodayWidgetSnapshotStoreTests.swift
git commit -m "feat: add today widget snapshot store"
```

## Task 4: Build Snapshots From Today Ordering

**Files:**
- Create: `Together/WidgetSupport/TodayWidgetSnapshotBuilder.swift`
- Test: `TogetherTests/TodayWidgetSnapshotBuilderTests.swift`

- [ ] **Step 1: Write failing tests for builder ordering and formatting**

Create `TogetherTests/TodayWidgetSnapshotBuilderTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("Today Widget Snapshot Builder")
struct TodayWidgetSnapshotBuilderTests {
    private let spaceID = UUID()
    private let actorID = UUID()
    private let calendar = Calendar(identifier: .gregorian)

    @Test("uses Today ordering and keeps only incomplete tasks")
    func usesTodayOrderingAndIncompleteTasks() {
        let now = Date(timeIntervalSince1970: 1_777_800_000)
        let first = item(title: "第一项", dueAt: now.addingTimeInterval(3600), sortOrder: 0)
        var completed = item(title: "已完成", dueAt: now.addingTimeInterval(1800), sortOrder: 1)
        completed.completedAt = now
        completed.status = .completed
        let second = item(title: "第二项", dueAt: now.addingTimeInterval(7200), sortOrder: 2)

        let snapshot = TodayWidgetSnapshotBuilder(calendar: calendar).build(
            items: [second, completed, first],
            referenceDate: now,
            limit: 3
        )

        #expect(snapshot.remainingCount == 2)
        #expect(snapshot.tasks.map(\.title) == ["第一项", "第二项"])
    }

    @Test("formats explicit time and hides missing due time")
    func formatsDueTime() {
        let now = Date(timeIntervalSince1970: 1_777_800_000)
        let explicit = item(title: "有时间", dueAt: now, hasExplicitTime: true, sortOrder: 0)
        let noDate = item(title: "无时间", dueAt: nil, sortOrder: 1)

        let snapshot = TodayWidgetSnapshotBuilder(calendar: calendar).build(
            items: [explicit, noDate],
            referenceDate: now,
            limit: 3
        )

        #expect(snapshot.tasks[0].dueTimeText != nil)
        #expect(snapshot.tasks[1].dueTimeText == nil)
    }

    private func item(
        title: String,
        dueAt: Date?,
        hasExplicitTime: Bool = true,
        sortOrder: Double
    ) -> Item {
        Item(
            id: UUID(),
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: title,
            notes: nil,
            executionRole: .creator,
            assigneeMode: .self,
            dueAt: dueAt,
            hasExplicitTime: hasExplicitTime,
            remindAt: nil,
            status: .inProgress,
            responseHistory: [],
            createdAt: dueAt ?? .now,
            updatedAt: dueAt ?? .now,
            sortOrder: sortOrder,
            isDraft: false
        )
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetSnapshotBuilderTests -quiet
```

Expected: BUILD FAILS because `TodayWidgetSnapshotBuilder` does not exist.

- [ ] **Step 3: Implement builder**

Create `Together/WidgetSupport/TodayWidgetSnapshotBuilder.swift`:

```swift
import Foundation

struct TodayWidgetSnapshotBuilder: Sendable {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func build(
        items: [Item],
        referenceDate: Date,
        limit: Int = 3
    ) -> TodayWidgetSnapshot {
        let sorted = items
            .filter { $0.isCompleted(on: referenceDate, calendar: calendar) == false && $0.status != .completed }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                let lhsDate = lhs.occurrenceDueDate(on: referenceDate, calendar: calendar) ?? lhs.dueAt ?? .distantFuture
                let rhsDate = rhs.occurrenceDueDate(on: referenceDate, calendar: calendar) ?? rhs.dueAt ?? .distantFuture
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        return TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: referenceDate,
            remainingCount: sorted.count,
            tasks: Array(sorted.prefix(max(limit, 1))).enumerated().map { index, item in
                TodayWidgetTaskSnapshot(
                    id: item.id,
                    title: item.title,
                    dueTimeText: dueTimeText(for: item, referenceDate: referenceDate),
                    sortIndex: index
                )
            }
        )
    }

    private func dueTimeText(for item: Item, referenceDate: Date) -> String? {
        let dueAt = item.occurrenceDueDate(on: referenceDate, calendar: calendar) ?? item.dueAt
        guard let dueAt, item.hasExplicitTime else { return nil }
        return dueAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
```

- [ ] **Step 4: Run builder tests**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetSnapshotBuilderTests -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Compare builder ordering against `HomeViewModel.sortedItemsForTimeline`**

Read [HomeViewModel.swift](/Users/papertiger/Desktop/Together/Together/Features/Home/HomeViewModel.swift) around `sortedItemsForTimeline`. If the builder differs in a user-visible way, update the builder and tests so widget ordering matches Today. At minimum, keep `sortOrder`, due date, `createdAt`, and `id` tie-breakers aligned.

- [ ] **Step 6: Commit**

```bash
git add Together/WidgetSupport/TodayWidgetSnapshotBuilder.swift TogetherTests/TodayWidgetSnapshotBuilderTests.swift
git commit -m "feat: build today widget snapshots"
```

## Task 5: Add Today Deep Link

**Files:**
- Modify: `Together/Services/DeepLinkConfiguration.swift`
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/Info.plist`
- Test: `TogetherTests/TodayWidgetDeepLinkTests.swift`

- [ ] **Step 1: Write failing tests for Today deep link parsing**

Create `TogetherTests/TodayWidgetDeepLinkTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("Today Widget Deep Link")
struct TodayWidgetDeepLinkTests {
    @Test("builds today deep link")
    func buildsTodayDeepLink() {
        #expect(DeepLinkConfiguration.todayURL.absoluteString == "together://today")
    }

    @Test("recognizes today deep link")
    func recognizesTodayDeepLink() {
        #expect(DeepLinkConfiguration.isTodayURL(URL(string: "together://today")!))
        #expect(DeepLinkConfiguration.isTodayURL(URL(string: "together://today/")!))
        #expect(!DeepLinkConfiguration.isTodayURL(URL(string: "https://onetwotogether.xyz/invite/abc")!))
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetDeepLinkTests -quiet
```

Expected: BUILD FAILS because `todayURL` and `isTodayURL` do not exist.

- [ ] **Step 3: Add Today deep link helpers**

Modify `Together/Services/DeepLinkConfiguration.swift`:

```swift
static let appScheme = "together"
private static let todayHost = "today"

static var todayURL: URL {
    URL(string: "\(appScheme)://\(todayHost)")!
}

static func isTodayURL(_ url: URL) -> Bool {
    url.scheme == appScheme && url.host == todayHost
}
```

- [ ] **Step 4: Route Today links in AppContext**

Modify `Together/App/AppContext.swift`:

```swift
func handleDeepLink(url: URL) {
    if DeepLinkConfiguration.isTodayURL(url) {
        router.currentSurface = .today
        router.isProfilePresented = false
        router.isProjectModePresented = false
        router.isRoutinesModePresented = false
        router.activeComposer = nil
        return
    }

    guard let code = DeepLinkConfiguration.inviteCode(from: url) else { return }
    pendingInviteCode = code
    router.isProfilePresented = true
}
```

- [ ] **Step 5: Add URL type**

Modify `Together/Info.plist` with:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.pigdog.Together</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>together</string>
        </array>
    </dict>
</array>
```

Keep existing keys unchanged.

- [ ] **Step 6: Run deep link tests**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetDeepLinkTests -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 7: Validate plist**

Run:

```bash
plutil -lint Together/Info.plist
```

Expected: `Together/Info.plist: OK`.

- [ ] **Step 8: Commit**

```bash
git add Together/Services/DeepLinkConfiguration.swift Together/App/AppContext.swift Together/Info.plist TogetherTests/TodayWidgetDeepLinkTests.swift
git commit -m "feat: add today widget deep link"
```

## Task 6: Add Extension-Safe Completion Gateway

**Files:**
- Create: `Together/WidgetSupport/TodayWidgetTaskCompletionGateway.swift`
- Test: `TogetherTests/TodayWidgetTaskCompletionGatewayTests.swift`

- [ ] **Step 1: Write failing gateway tests with mocks**

Create `TogetherTests/TodayWidgetTaskCompletionGatewayTests.swift`:

```swift
import Foundation
import Testing
@testable import Together

@Suite("Today Widget Task Completion Gateway")
struct TodayWidgetTaskCompletionGatewayTests {
    @Test("completes task and refreshes snapshot")
    func completesTaskAndRefreshesSnapshot() async throws {
        let taskID = UUID()
        let spaceID = UUID()
        let actorID = UUID()
        let task = Item(
            id: taskID,
            spaceID: spaceID,
            listID: nil,
            projectID: nil,
            creatorID: actorID,
            title: "核对审核备注",
            notes: nil,
            executionRole: .creator,
            assigneeMode: .self,
            dueAt: nil,
            remindAt: nil,
            status: .inProgress,
            responseHistory: [],
            createdAt: .now,
            updatedAt: .now,
            isDraft: false
        )
        let service = MockWidgetTaskApplicationService(item: task)
        let snapshotWriter = MockTodayWidgetSnapshotWriter()
        let gateway = TodayWidgetTaskCompletionGateway(
            taskApplicationService: service,
            snapshotWriter: snapshotWriter,
            spaceIDProvider: { spaceID },
            actorIDProvider: { actorID }
        )

        try await gateway.complete(taskID: taskID, referenceDate: .now)

        #expect(service.completedTaskID == taskID)
        #expect(snapshotWriter.writeCount == 1)
    }
}

private actor MockWidgetTaskApplicationService: TaskApplicationServiceProtocol {
    var completedTaskID: UUID?
    private let item: Item

    init(item: Item) {
        self.item = item
    }

    func tasks(in spaceID: UUID, scope: TaskScope) async throws -> [Item] { [item] }
    func todaySummary(in spaceID: UUID, referenceDate: Date) async throws -> TaskTodaySummary {
        TaskTodaySummary(referenceDate: referenceDate, actionableCount: 1, overdueCount: 0, dueTodayCount: 1, completedTodayCount: 0, pinnedCount: 0)
    }
    func createTask(in spaceID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { item }
    func updateTask(in spaceID: UUID, taskID: UUID, actorID: UUID, draft: TaskDraft) async throws -> Item { item }
    func moveTask(in spaceID: UUID, taskID: UUID, actorID: UUID, listID: UUID?, projectID: UUID?) async throws -> Item { item }
    func rescheduleTask(in spaceID: UUID, taskID: UUID, actorID: UUID, dueAt: Date?, remindAt: Date?) async throws -> Item { item }
    func snoozeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, option: TaskSnoozeOption) async throws -> Item { item }
    func toggleTaskCompletion(in spaceID: UUID, taskID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item { item }
    func completeTask(in spaceID: UUID, taskID: UUID, actorID: UUID, referenceDate: Date) async throws -> Item {
        completedTaskID = taskID
        return item
    }
    func archiveTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { item }
    func deleteTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws {}
    func respondToTask(in spaceID: UUID, taskID: UUID, actorID: UUID, response: ItemResponseKind, message: String?) async throws -> Item { item }
    func sendTaskComment(in spaceID: UUID, taskID: UUID, actorID: UUID, content: String) async throws -> TaskMessage? { nil }
    func requeueDeclinedTask(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { item }
    func appendAssignmentMessage(in spaceID: UUID, taskID: UUID, actorID: UUID, message: String) async throws -> Item { item }
    func sendReminderToPartner(in spaceID: UUID, taskID: UUID, actorID: UUID) async throws -> Item { item }
}

private actor MockTodayWidgetSnapshotWriter: TodayWidgetSnapshotWriting {
    var writeCount = 0
    func refreshTodayWidgetSnapshot() async throws {
        writeCount += 1
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetTaskCompletionGatewayTests -quiet
```

Expected: BUILD FAILS because `TodayWidgetTaskCompletionGateway` and `TodayWidgetSnapshotWriting` do not exist.

- [ ] **Step 3: Implement completion gateway protocols and type**

Create `Together/WidgetSupport/TodayWidgetTaskCompletionGateway.swift`:

```swift
import Foundation

protocol TodayWidgetSnapshotWriting: Sendable {
    func refreshTodayWidgetSnapshot() async throws
}

enum TodayWidgetCompletionError: Error {
    case missingSpace
    case missingActor
}

struct TodayWidgetTaskCompletionGateway: Sendable {
    private let taskApplicationService: TaskApplicationServiceProtocol
    private let snapshotWriter: TodayWidgetSnapshotWriting
    private let spaceIDProvider: @Sendable () -> UUID?
    private let actorIDProvider: @Sendable () -> UUID?

    init(
        taskApplicationService: TaskApplicationServiceProtocol,
        snapshotWriter: TodayWidgetSnapshotWriting,
        spaceIDProvider: @escaping @Sendable () -> UUID?,
        actorIDProvider: @escaping @Sendable () -> UUID?
    ) {
        self.taskApplicationService = taskApplicationService
        self.snapshotWriter = snapshotWriter
        self.spaceIDProvider = spaceIDProvider
        self.actorIDProvider = actorIDProvider
    }

    func complete(taskID: UUID, referenceDate: Date) async throws {
        guard let spaceID = spaceIDProvider() else { throw TodayWidgetCompletionError.missingSpace }
        guard let actorID = actorIDProvider() else { throw TodayWidgetCompletionError.missingActor }
        _ = try await taskApplicationService.completeTask(
            in: spaceID,
            taskID: taskID,
            actorID: actorID,
            referenceDate: referenceDate
        )
        try await snapshotWriter.refreshTodayWidgetSnapshot()
    }
}
```

- [ ] **Step 4: Add production factory for extension use**

Add a factory in the same file:

```swift
extension TodayWidgetTaskCompletionGateway {
    static func live() throws -> TodayWidgetTaskCompletionGateway {
        let persistence = PersistenceController()
        let container = persistence.container
        let syncCoordinator = LocalSyncCoordinator(container: container)
        let itemRepository = LocalItemRepository(container: container, syncCoordinator: syncCoordinator)
        let taskMessageRepository = LocalTaskMessageRepository(container: container)
        let notificationService = LocalNotificationService()
        let reminderScheduler = LocalReminderScheduler(notificationService: notificationService)
        let service = DefaultTaskApplicationService(
            itemRepository: itemRepository,
            taskMessageRepository: taskMessageRepository,
            syncCoordinator: syncCoordinator,
            reminderScheduler: reminderScheduler
        )
        let context = TodayWidgetSharedContextStore()
        let writer = TodayWidgetSnapshotWriter(
            itemRepository: itemRepository,
            contextStore: context,
            snapshotStore: TodayWidgetSnapshotStore()
        )
        return TodayWidgetTaskCompletionGateway(
            taskApplicationService: service,
            snapshotWriter: writer,
            spaceIDProvider: { context.read()?.spaceID },
            actorIDProvider: { context.read()?.actorID }
        )
    }
}
```

If `LocalNotificationService` or reminder scheduling cannot be safely used from the widget extension target, replace only the extension factory’s reminder scheduler with a small `NoopReminderScheduler` that conforms to `ReminderSchedulerProtocol`; keep `DefaultTaskApplicationService` and `LocalItemRepository` unchanged.

- [ ] **Step 5: Run gateway tests**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -only-testing:TogetherTests/TodayWidgetTaskCompletionGatewayTests -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 6: Commit**

```bash
git add Together/WidgetSupport/TodayWidgetTaskCompletionGateway.swift TogetherTests/TodayWidgetTaskCompletionGatewayTests.swift
git commit -m "feat: add today widget completion gateway"
```

## Task 7: Add Shared Context and Snapshot Writer

**Files:**
- Create: `Together/WidgetSupport/TodayWidgetSharedContextStore.swift`
- Create: `Together/WidgetSupport/TodayWidgetSnapshotWriter.swift`
- Modify: `Together/App/AppContext.swift`
- Test: `TogetherTests/TodayWidgetSnapshotBuilderTests.swift`

- [ ] **Step 1: Add shared context store**

Create `Together/WidgetSupport/TodayWidgetSharedContextStore.swift`:

```swift
import Foundation

struct TodayWidgetSharedContext: Codable, Equatable, Sendable {
    var spaceID: UUID
    var actorID: UUID
}

struct TodayWidgetSharedContextStore: Sendable {
    private let defaults: UserDefaults?

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
    }

    func read() -> TodayWidgetSharedContext? {
        guard let data = defaults?.data(forKey: "today-widget-context") else { return nil }
        return try? JSONDecoder().decode(TodayWidgetSharedContext.self, from: data)
    }

    func write(_ context: TodayWidgetSharedContext) {
        guard let data = try? JSONEncoder().encode(context) else { return }
        defaults?.set(data, forKey: "today-widget-context")
    }
}
```

- [ ] **Step 2: Add snapshot writer**

Create `Together/WidgetSupport/TodayWidgetSnapshotWriter.swift`:

```swift
import Foundation

actor TodayWidgetSnapshotWriter: TodayWidgetSnapshotWriting {
    private let itemRepository: ItemRepositoryProtocol
    private let contextStore: TodayWidgetSharedContextStore
    private let snapshotStore: TodayWidgetSnapshotStore
    private let builder: TodayWidgetSnapshotBuilder

    init(
        itemRepository: ItemRepositoryProtocol,
        contextStore: TodayWidgetSharedContextStore = TodayWidgetSharedContextStore(),
        snapshotStore: TodayWidgetSnapshotStore = TodayWidgetSnapshotStore(),
        builder: TodayWidgetSnapshotBuilder = TodayWidgetSnapshotBuilder()
    ) {
        self.itemRepository = itemRepository
        self.contextStore = contextStore
        self.snapshotStore = snapshotStore
        self.builder = builder
    }

    func refreshTodayWidgetSnapshot() async throws {
        guard let context = contextStore.read() else {
            try snapshotStore.write(.empty)
            return
        }
        let items = try await itemRepository.fetchActiveItems(spaceID: context.spaceID)
        let snapshot = builder.build(items: items, referenceDate: .now, limit: 3)
        try snapshotStore.write(snapshot)
    }
}
```

- [ ] **Step 3: Wire app-side context and writer**

Modify `Together/App/AppContext.swift`:

```swift
private let todayWidgetContextStore = TodayWidgetSharedContextStore()
private lazy var todayWidgetSnapshotWriter = TodayWidgetSnapshotWriter(
    itemRepository: container.itemRepository
)

func refreshTodayWidgetSnapshot() async {
    guard let spaceID = sessionStore.currentSpace?.id,
          let actorID = sessionStore.currentUser?.id
    else { return }
    todayWidgetContextStore.write(TodayWidgetSharedContext(spaceID: spaceID, actorID: actorID))
    try? await todayWidgetSnapshotWriter.refreshTodayWidgetSnapshot()
}
```

If `AppContext` cannot have a lazy property because it is an `@Observable` class with current initialization constraints, inject `TodayWidgetSnapshotWriter` from `LocalServiceFactory` or keep it as a computed local inside `refreshTodayWidgetSnapshot()`.

- [ ] **Step 4: Call snapshot refresh after post-launch and foreground work**

In `Together/App/AppContext.swift`, call:

```swift
await refreshTodayWidgetSnapshot()
```

after the app has loaded the current space and Today data in `performPostLaunchWorkIfNeeded()` and after foreground reload paths that already refresh Home data.

- [ ] **Step 5: Call snapshot refresh after task mutation**

In `Together/Features/Home/HomeViewModel.swift`, after successful `completeItem`, create/update/delete, and reorder flows, notify AppContext through an existing mutation callback if available. If no callback exists, keep the refresh call in `AppContext.reloadAfterSync()` and app foreground paths for the first pass, then add a small `onTodayDataChanged` closure to `HomeViewModel`:

```swift
var onTodayDataChanged: (@MainActor @Sendable () -> Void)?
```

Invoke it after mutations:

```swift
onTodayDataChanged?()
```

Configure it in `AppContext`:

```swift
homeViewModel.onTodayDataChanged = { [weak self] in
    Task { await self?.refreshTodayWidgetSnapshot() }
}
```

- [ ] **Step 6: Commit**

```bash
git add Together/WidgetSupport/TodayWidgetSharedContextStore.swift Together/WidgetSupport/TodayWidgetSnapshotWriter.swift Together/App/AppContext.swift Together/Features/Home/HomeViewModel.swift
git commit -m "feat: refresh today widget snapshots"
```

## Task 8: Add Widget Extension Target and Entitlements

**Files:**
- Modify: `Together/Together.entitlements`
- Create: `TogetherWidget/TogetherWidget.entitlements`
- Create: `TogetherWidget/Info.plist`
- Modify: `Together.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add App Group entitlement to app target**

Modify `Together/Together.entitlements`:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.pigdog.together.shared</string>
</array>
```

Keep existing iCloud, Sign in with Apple, APNs, and Associated Domains keys.

- [ ] **Step 2: Add widget entitlements**

Create `TogetherWidget/TogetherWidget.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.pigdog.together.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Add widget Info.plist**

Create `TogetherWidget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 4: Add the Widget Extension target in Xcode project**

Modify `Together.xcodeproj/project.pbxproj` to add a Widget Extension target with:

```text
PRODUCT_BUNDLE_IDENTIFIER = com.pigdog.Together.TogetherWidget;
CODE_SIGN_ENTITLEMENTS = TogetherWidget/TogetherWidget.entitlements;
INFOPLIST_FILE = TogetherWidget/Info.plist;
SKIP_INSTALL = YES;
SUPPORTED_PLATFORMS = iphoneos iphonesimulator;
TARGETED_DEVICE_FAMILY = 1;
```

Add sources from:

- `TogetherWidget/*.swift`
- shared `Together/WidgetSupport/*.swift`
- any domain/service files required by `TodayWidgetTaskCompletionGateway.live()`.

Add the extension product to the app target embed app extensions phase. Prefer using Xcode to create the target if manual `.pbxproj` editing becomes noisy; then inspect the generated diff and remove unrelated churn.

- [ ] **Step 5: Validate plist and project can parse**

Run:

```bash
plutil -lint Together/Together.entitlements TogetherWidget/TogetherWidget.entitlements TogetherWidget/Info.plist Together/Info.plist
xcodebuild -list -project Together.xcodeproj
```

Expected: plist lint OK and `xcodebuild -list` returns schemes/targets without project parse errors.

- [ ] **Step 6: Commit**

```bash
git add Together/Together.entitlements TogetherWidget/TogetherWidget.entitlements TogetherWidget/Info.plist Together.xcodeproj/project.pbxproj
git commit -m "feat: add today widget extension target"
```

## Task 9: Add App Intent

**Files:**
- Create: `TogetherWidget/CompleteTodayWidgetTaskIntent.swift`
- Modify: `Together.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add complete intent**

Create `TogetherWidget/CompleteTodayWidgetTaskIntent.swift`:

```swift
import AppIntents
import Foundation
import WidgetKit

struct CompleteTodayWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "完成今日任务"
    static var description = IntentDescription("从 Together 小组件完成一项今日任务。")
    static var isDiscoverable = false

    @Parameter(title: "任务 ID")
    var taskID: String

    init() {
        self.taskID = ""
    }

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else {
            return .result()
        }

        let gateway = try TodayWidgetTaskCompletionGateway.live()
        try await gateway.complete(taskID: id, referenceDate: .now)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
        return .result()
    }
}
```

- [ ] **Step 2: Add target membership**

Ensure this file is included in the widget extension target. If the intent is reused in the app target, include it in the app target too; otherwise keep it widget-only.

- [ ] **Step 3: Build the widget target**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet
```

Expected: BUILD FAILS only if target membership/dependencies are incomplete; fix those before proceeding.

- [ ] **Step 4: Commit**

```bash
git add TogetherWidget/CompleteTodayWidgetTaskIntent.swift Together.xcodeproj/project.pbxproj
git commit -m "feat: add today widget completion intent"
```

## Task 10: Build Widget UI

**Files:**
- Create: `TogetherWidget/TogetherWidgetBundle.swift`
- Create: `TogetherWidget/TodayFocusWidget.swift`
- Create: `TogetherWidget/TodayListWidget.swift`
- Create: `TogetherWidget/TodayWidgetViews.swift`

- [ ] **Step 1: Add widget bundle**

Create `TogetherWidget/TogetherWidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct TogetherWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayFocusWidget()
        TodayListWidget()
    }
}
```

- [ ] **Step 2: Add shared views**

Create `TogetherWidget/TodayWidgetViews.swift`:

```swift
import SwiftUI
import WidgetKit

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(TodayWidgetEntry(date: .now, snapshot: (try? TodayWidgetSnapshotStore().read()) ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let snapshot = (try? TodayWidgetSnapshotStore().read()) ?? .empty
        let entry = TodayWidgetEntry(date: .now, snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TodayWidgetTaskRow: View {
    let task: TodayWidgetTaskSnapshot

    var body: some View {
        HStack(spacing: 7) {
            Button(intent: CompleteTodayWidgetTaskIntent(taskID: task.id)) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.44),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3.6, 4.4])
                    )
                    .frame(width: 25, height: 25)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成任务，\(task.title)")

            Link(destination: TodayWidgetConstants.todayDeepLink) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 12.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let dueTimeText = task.dueTimeText {
                        Text(dueTimeText)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityLabel("打开 Today，\(task.title)")
        }
    }
}

struct TodayWidgetEmptyView: View {
    var body: some View {
        Link(destination: TodayWidgetConstants.todayDeepLink) {
            VStack(spacing: 6) {
                Image("EmptyCalendar")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 54)
                    .accessibilityHidden(true)
                Text("今日已清空")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("享受当下，或规划新任务")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel("今日已清空，打开 Today")
    }
}
```

- [ ] **Step 3: Add Focus widget**

Create `TogetherWidget/TodayFocusWidget.swift`:

```swift
import SwiftUI
import WidgetKit

struct TodayFocusWidget: Widget {
    let kind = TodayWidgetConstants.focusWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayFocusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Today Focus")
        .description("显示今天下一件重点任务。")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayFocusWidgetView: View {
    let entry: TodayWidgetEntry

    var body: some View {
        if let first = entry.snapshot.tasks.first {
            VStack(alignment: .leading, spacing: 12) {
                TodayWidgetHeader(title: "今日", remainingCount: entry.snapshot.remainingCount)
                TodayWidgetTaskRow(task: first)
                Spacer(minLength: 0)
            }
            .padding(13)
            .widgetURL(TodayWidgetConstants.todayDeepLink)
        } else {
            TodayWidgetEmptyView()
                .padding(13)
        }
    }
}

struct TodayWidgetHeader: View {
    let title: String
    let remainingCount: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text("还剩 \(remainingCount) 项")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.37, blue: 0.57))
        }
    }
}
```

- [ ] **Step 4: Add List widget**

Create `TogetherWidget/TodayListWidget.swift`:

```swift
import SwiftUI
import WidgetKit

struct TodayListWidget: Widget {
    let kind = TodayWidgetConstants.listWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayListWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Today List")
        .description("显示今天前三项待办。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        if entry.snapshot.tasks.isEmpty {
            TodayWidgetEmptyView()
                .padding(13)
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 12) {
                TodayWidgetHeader(
                    title: family == .systemSmall ? "今日" : "今日重点",
                    remainingCount: entry.snapshot.remainingCount
                )
                ForEach(entry.snapshot.tasks.prefix(3)) { task in
                    TodayWidgetTaskRow(task: task)
                }
                Spacer(minLength: 0)
            }
            .padding(family == .systemSmall ? 13 : 16)
            .widgetURL(TodayWidgetConstants.todayDeepLink)
        }
    }
}
```

- [ ] **Step 5: Add previews**

Append previews to widget files:

```swift
#Preview(as: .systemSmall) {
    TodayFocusWidget()
} timeline: {
    TodayWidgetEntry(
        date: .now,
        snapshot: TodayWidgetSnapshot(
            generatedAt: .now,
            referenceDate: .now,
            remainingCount: 5,
            tasks: [
                TodayWidgetTaskSnapshot(id: UUID(), title: "核对审核备注", dueTimeText: "18:00", sortIndex: 0)
            ]
        )
    )
}
```

Add `.systemSmall` and `.systemMedium` previews for `TodayListWidget`, plus an empty snapshot preview.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 7: Commit**

```bash
git add TogetherWidget/TogetherWidgetBundle.swift TogetherWidget/TodayFocusWidget.swift TogetherWidget/TodayListWidget.swift TogetherWidget/TodayWidgetViews.swift
git commit -m "feat: add today widget views"
```

## Task 11: Integrate WidgetCenter Reloads

**Files:**
- Modify: `Together/App/AppContext.swift`
- Modify: `Together/Features/Home/HomeViewModel.swift`
- Modify: `TogetherWidget/CompleteTodayWidgetTaskIntent.swift`

- [ ] **Step 1: Reload timelines after app-side snapshot writes**

In `Together/App/AppContext.swift`, after successful `refreshTodayWidgetSnapshot()` writes:

```swift
#if canImport(WidgetKit)
import WidgetKit
#endif
```

and:

```swift
#if canImport(WidgetKit)
WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
#endif
```

- [ ] **Step 2: Verify App Intent already reloads both widget kinds**

Open `TogetherWidget/CompleteTodayWidgetTaskIntent.swift` and confirm:

```swift
WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.focusWidgetKind)
WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetConstants.listWidgetKind)
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 4: Commit**

```bash
git add Together/App/AppContext.swift Together/Features/Home/HomeViewModel.swift TogetherWidget/CompleteTodayWidgetTaskIntent.swift
git commit -m "feat: reload today widget timelines"
```

## Task 12: Full Verification and Project Memory

**Files:**
- Modify: `docs/PROJECT_MEMORY.md`

- [ ] **Step 1: Run diff check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Lint plists**

Run:

```bash
plutil -lint Together/Info.plist Together/Together.entitlements TogetherWidget/Info.plist TogetherWidget/TogetherWidget.entitlements
```

Expected: every file reports `OK`.

- [ ] **Step 3: Run focused tests**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' \
  -only-testing:TogetherTests/PersistenceAppGroupStoreTests \
  -only-testing:TogetherTests/TodayWidgetSnapshotStoreTests \
  -only-testing:TogetherTests/TodayWidgetSnapshotBuilderTests \
  -only-testing:TogetherTests/TodayWidgetDeepLinkTests \
  -only-testing:TogetherTests/TodayWidgetTaskCompletionGatewayTests \
  -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 4: Run generic app build**

Run:

```bash
xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 5: Run build-for-testing**

Run:

```bash
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet
```

Expected: BUILD SUCCEEDS.

- [ ] **Step 6: Update project memory**

Append to `docs/PROJECT_MEMORY.md`:

```markdown
- 2026-05-04：完成 Today 任务小组件第一阶段实现。新增 Today Focus / Today List widget，App Group 快照、Today deeplink、extension-safe 完成任务 App Intent 和 widget timeline reload。验证：`git diff --check`、widget 相关 focused tests、`xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet`、`xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过。未做模拟器测试。
```

- [ ] **Step 7: Commit**

```bash
git add docs/PROJECT_MEMORY.md
git commit -m "docs: record today widget implementation"
```

## Plan Self-Review

Spec coverage:

- Product forms: Tasks 8-10 create `TodayFocusWidget`, `TodayListWidget`, small/medium supported families, and shared row UI.
- App Group: Tasks 1-2 and 8 add constants, entitlements, and store migration.
- Snapshot data: Tasks 3-4 and 7 add DTOs, store, builder, context, and app refresh integration.
- Completion: Tasks 6 and 9 add the extension-safe gateway and App Intent.
- Deep link: Task 5 adds `together://today` parsing, routing, and URL type.
- Refresh: Tasks 7 and 11 write snapshots and reload timelines.
- Empty state and visual language: Task 10 implements empty view and task row style.
- Verification: Task 12 covers focused tests, plist lint, generic build, build-for-testing, and project memory.
- Stage 2 anniversary widget: intentionally excluded per spec.

Red-flag scan:

- No red-flag wording or unowned generic implementation steps remain.

Type consistency:

- Widget constants: `TodayWidgetConstants.focusWidgetKind`, `TodayWidgetConstants.listWidgetKind`, `TodayWidgetConstants.todayDeepLink`.
- Snapshot types: `TodayWidgetSnapshot`, `TodayWidgetTaskSnapshot`, `TodayWidgetSnapshotStore`, `TodayWidgetSnapshotBuilder`.
- Completion types: `TodayWidgetTaskCompletionGateway`, `TodayWidgetSnapshotWriting`, `CompleteTodayWidgetTaskIntent`.
- Deep link helpers: `DeepLinkConfiguration.todayURL`, `DeepLinkConfiguration.isTodayURL(_:)`.

Implementation caution:

- If Xcode target creation changes `.pbxproj` more than expected, stop after target scaffolding and review the diff before continuing.
- If widget extension cannot safely link `LocalNotificationService`, use a `NoopReminderScheduler` only inside `TodayWidgetTaskCompletionGateway.live()` and document that reminder resync remains app-side on next launch.
