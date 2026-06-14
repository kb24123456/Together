# 一起 数据模型说明

## 1. 迁移结论

### 事实
- 当前仓库已有 `PairSpace / Invite / Decision / Anniversary / TaskMessage / Premium / Supabase Sync` 等旧模型。
- 这些模型来自旧的双人优先、第三方后端和订阅付费方案。
- 用户已确认不迁移旧 Supabase 数据，允许删除旧双人/付费/后端数据链路。

### 结论
- 当前目标模型只服务单人 Todo。
- 不再定义 `PairSpace / MultiSpace / SpaceMembership / Invite / BindingState / relationshipID`。
- 不再定义 `Premium / Entitlement / Subscription / Paywall`。
- 不再定义 Supabase DTO、Realtime DTO、Edge Function payload 或远端恢复游标。
- 若迁移期间仍需读取旧 `spaceID`，只能作为临时兼容输入；目标模型不保留多空间能力。

## 2. UserProfile
- `id: UUID`
- `appleUserID: String?`
- `displayName: String`
- `avatarSystemName: String?`
- `avatarPhotoFileName: String?`
- `createdAt: Date`
- `updatedAt: Date`
- `preferences: UserPreferences`

### UserPreferences
- `theme: AppThemePreference`
- `startPage: StartPagePreference`
- `reduceMotionOverride: Bool?`
- `notificationSettings: NotificationSettings`
- `taskUrgencyWindowMinutes: Int`
- `defaultSnoozeMinutes: Int`
- `completedTaskAutoArchiveEnabled: Bool`
- `completedTaskAutoArchiveDays: Int`

### NotificationSettings
- `taskReminderEnabled: Bool`
- `dailySummaryEnabled: Bool`
- `calendarReminderEnabled: Bool`

## 3. Task

### 3.1 核心字段
- `id: UUID`
- `listID: UUID?`
- `projectID: UUID?`
- `title: String`
- `notes: String?`
- `status: TaskStatus`
- `priority: TaskPriority`
- `dueAt: Date?`
- `hasExplicitTime: Bool`
- `remindAt: Date?`
- `completedAt: Date?`
- `sortOrder: Double`
- `isFlagged: Bool`
- `isArchived: Bool`
- `archivedAt: Date?`
- `repeatRule: TaskRepeatRule?`
- `createdAt: Date`
- `updatedAt: Date`

### 3.2 TaskStatus
- `inbox`
- `todo`
- `inProgress`
- `completed`
- `archived`

### 3.3 TaskPriority
- `normal`
- `important`
- `critical`

### 3.4 规则
- `TaskStatus` 只表达单人任务生命周期。
- 任务完成、恢复、归档、提醒、排序都不依赖协作者、响应状态或订阅状态。
- OCR 生成的任务先进入 `OCRImportDraft`，用户确认后才创建 `Task`。

## 4. TaskList
- `id: UUID`
- `name: String`
- `kind: TaskListKind`
- `colorToken: String?`
- `sortOrder: Double`
- `isArchived: Bool`
- `createdAt: Date`
- `updatedAt: Date`

### TaskListKind
- `systemInbox`
- `systemToday`
- `systemSomeday`
- `custom`

## 5. Project
- `id: UUID`
- `name: String`
- `notes: String?`
- `colorToken: String?`
- `status: ProjectStatus`
- `targetDate: Date?`
- `remindAt: Date?`
- `sortOrder: Double`
- `createdAt: Date`
- `updatedAt: Date`
- `completedAt: Date?`

### ProjectStatus
- `active`
- `onHold`
- `completed`
- `archived`

### ProjectTask
- 项目内任务仍使用 `Task.projectID` 关联，不单独复制任务生命周期。
- 项目详情可提供轻量子任务 UI，但数据真相应尽量回到 Task。

## 6. Reminder / Notification
- `id: UUID`
- `taskID: UUID?`
- `projectID: UUID?`
- `kind: ReminderKind`
- `channel: ReminderChannel`
- `scheduledAt: Date`
- `deliveredAt: Date?`
- `status: ReminderDeliveryStatus`
- `title: String`
- `body: String`

### ReminderKind
- `taskDue`
- `taskReminder`
- `dailySummary`
- `projectDeadline`

## 7. OCRImportDraft
- `id: UUID`
- `sourceImageID: UUID?`
- `rawText: String`
- `createdAt: Date`
- `updatedAt: Date`
- `status: OCRDraftStatus`
- `taskDrafts: [TaskDraft]`
- `projectDrafts: [ProjectDraft]`

### OCRDraftStatus
- `recognizing`
- `needsReview`
- `applied`
- `failed`
- `discarded`

### TaskDraft
- `id: UUID`
- `title: String`
- `notes: String?`
- `listID: UUID?`
- `projectDraftID: UUID?`
- `dueAt: Date?`
- `priority: TaskPriority`
- `sourceTextRange: String?`

### ProjectDraft
- `id: UUID`
- `name: String`
- `notes: String?`
- `targetDate: Date?`
- `taskDraftIDs: [UUID]`

### 规则
- OCR 草稿不是业务真相。
- 用户确认前，草稿不得影响 Today、清单、项目、日历或 Widget。
- 用户确认后，草稿转换为真实 Task / Project，并标记为 `applied` 或删除。

## 8. Widget Snapshot
- `generatedAt: Date`
- `referenceDate: Date`
- `remainingCount: Int`
- `tasks: [TodayWidgetTaskSnapshot]`
- `animatingCompletionTaskIDs: [UUID]`
- `appearingTaskIDs: [UUID]`

### TodayWidgetTaskSnapshot
- `id: UUID`
- `title: String`
- `dueTimeText: String?`
- `sortIndex: Int`

### 规则
- Widget snapshot 只用于展示和动画。
- Widget 完成任务必须更新 SwiftData 业务真相源。
- Widget 不再写 Supabase outbox 或任何第三方同步队列。

## 9. SwiftData + CloudKit 约束
- 目标 SwiftData 模型必须兼容 CloudKit private database。
- 不使用 `@Attribute(.unique)`。
- 所有持久化属性必须有默认值或声明为 optional。
- 关系必须 optional 或提供 CloudKit 兼容默认结构。
- 旧 store 允许被删除，因此可以优先选择干净 schema，而不是保留复杂历史字段。

## 10. 删除对象清单
- `PairSpace`
- `PairMember`
- `Invite`
- `BindingState`
- `PairingContext`
- `TaskMessage`
- `TaskChatReadState`
- `TaskAssignmentMessage`
- `ItemResponse` / `TaskAssignmentResponse`
- `DecisionCard`
- `AnniversaryEvent` / `ImportantDate` 作为关系运营能力
- `PremiumStatus`
- `PremiumGate`
- `RevenueCat` entitlement models
- `Supabase` sync DTOs and recovery cursors

## 11. Open Questions
- 是否保留独立标签模型，还是继续用 `TaskList + Project` 承接分类。
- OCR 草稿是否需要持久化跨启动恢复，还是仅在当前导入流程内短期保存。
