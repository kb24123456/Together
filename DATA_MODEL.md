# 一起 数据模型说明

## 1. 迁移结论

### 事实
- 当前仓库已有 `PairSpace / Invite / Decision / Anniversary` 等旧模型。
- 这些模型来自旧的双人优先方案。

### 结论
- 当前 MVP 的核心模型应回到 `Task / TaskList / Project / Reminder / Space`。
- 新开发优先使用通用 `spaceID`，不要继续扩散 `relationshipID`。
- 双人模式未来应作为 `PairSpace` 扩展能力挂在同一套 Space 模型下，而不是让单人模式变成“未绑定试用态”。

## 2. User
- `id: UUID`
- `appleUserID: String?`
- `displayName: String`
- `avatarSystemName: String?`
- `createdAt: Date`
- `updatedAt: Date`
- `preferences: UserPreferences`

### UserPreferences
- `theme: AppThemePreference`
- `startPage: StartPagePreference`
- `reduceMotionOverride: Bool?`
- `notificationSettings: NotificationSettings`

### NotificationSettings
- `taskReminderEnabled: Bool`
- `dailySummaryEnabled: Bool`
- `calendarReminderEnabled: Bool`
- `futureCollaborationInviteEnabled: Bool`

## 3. Space

### 3.1 Space
- `id: UUID`
- `type: SpaceType`
- `displayName: String`
- `ownerUserID: UUID`
- `status: SpaceStatus`
- `createdAt: Date`
- `updatedAt: Date`
- `archivedAt: Date?`

### 3.2 SpaceType
- `single`
- `pair`
- `multi`

### 3.3 SpaceStatus
- `active`
- `paused`
- `archived`

### 3.4 SpaceMembership（V2+）
- `spaceID: UUID`
- `userID: UUID`
- `role: SpaceRole`
- `joinedAt: Date`

### 3.5 规则
- V1 默认只有一个活跃 `SingleSpace`。
- V2 才开始真正使用 `PairSpace` 的共享能力。
- V3 以前不要让 `MultiSpace` 进入产品承诺。

## 4. Task

### 4.1 核心字段
- `id: UUID`
- `spaceID: UUID`
- `creatorUserID: UUID`
- `assigneeUserID: UUID?`
- `listID: UUID?`
- `projectID: UUID?`
- `title: String`
- `notes: String?`
- `status: TaskStatus`
- `priority: TaskPriority`
- `dueAt: Date?`
- `remindAt: Date?`
- `completedAt: Date?`
- `sortOrder: Double?`
- `isFlagged: Bool`
- `createdAt: Date`
- `updatedAt: Date`
- `collaboration: TaskCollaboration?`

### 4.2 TaskStatus
- `inbox`
- `todo`
- `inProgress`
- `completed`
- `archived`

### 4.3 TaskPriority
- `normal`
- `important`
- `critical`

### 4.4 TaskCollaboration（V2+）
- `mode: TaskCollaborationMode`
- `sharedByUserID: UUID`
- `lastSyncAt: Date?`
- `partnerState: TaskPartnerState?`

### 4.5 规则
- `TaskStatus` 表达任务生命周期，不承载未来双人协作的反馈语义。
- 双人模式下的接收、确认、共同编辑等行为，优先放进 `TaskCollaboration`，不要污染单人任务主状态。

## 5. TaskList
- `id: UUID`
- `spaceID: UUID`
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

## 6. Project
- `id: UUID`
- `spaceID: UUID`
- `name: String`
- `notes: String?`
- `colorToken: String?`
- `status: ProjectStatus`
- `targetDate: Date?`
- `createdAt: Date`
- `updatedAt: Date`
- `completedAt: Date?`

### ProjectStatus
- `active`
- `onHold`
- `completed`
- `archived`

## 7. Reminder / Notification
- `id: UUID`
- `spaceID: UUID`
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
- `futurePairInvite`

## 8. 附加模块（非 V1 核心）

### DecisionCard（后续）
- 用于记录需要讨论的事项，不再作为首页主数据对象。
- 若保留，必须挂在 `spaceID` 下，而不是独立于 Todo 系统之外。

### AnniversaryEvent（后续）
- 用于记录纪念性日期或重要提醒。
- 若实现，优先作为提醒附加能力，而不是一级主流程。

## 9. 兼容说明
- 当前代码仍使用 `relationshipID` 与 `PairSpace` 的地方，属于迁移中的技术债。
- 后续代码改造时，优先引入兼容层或映射层，再逐步迁移字段命名，避免一次性大拆。

## 10. Open Questions
- V1 是否需要独立的标签模型，还是先用 `TaskList + Project` 组合承接。
- `TaskStatus.inbox` 与 `TaskList.systemInbox` 是否统一用一个系统语义源维护。
