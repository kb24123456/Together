# 一起 数据模型说明

## 1. 设计原则
- 所有双人共享数据必须带 `relationshipID`
- 未绑定试用态产生的数据只能是草稿或示例，不得直接视为共享历史
- 解绑后旧 `relationshipID` 不得复用
- 新绑定必须生成新的 `PairSpace.id` 和新的 `dataBoundaryToken`

## 2. User

### 2.1 事实字段
- `id: UUID`
- `appleUserID: String?`
- `displayName: String`
- `avatarSystemName: String?`
- `createdAt: Date`
- `updatedAt: Date`
- `preferences: NotificationSettings`

### 2.2 NotificationSettings
- `newItemEnabled: Bool`
- `decisionEnabled: Bool`
- `anniversaryEnabled: Bool`
- `deadlineEnabled: Bool`

## 3. PairSpace / Relationship

### 3.1 PairSpace
- `id: UUID`
- `status: PairSpaceStatus`
- `memberA: PairMember`
- `memberB: PairMember?`
- `dataBoundaryToken: UUID`
- `createdAt: Date`
- `activatedAt: Date?`
- `endedAt: Date?`

### 3.2 PairMember
- `userID: UUID`
- `nickname: String`
- `joinedAt: Date`

### 3.3 PairSpaceStatus
- `trial`
- `pendingAcceptance`
- `active`
- `ended`

### 3.4 数据边界规则
- 所有共享 Item / Decision / Anniversary / Reminder 都以 `relationshipID == PairSpace.id` 归属
- 解绑后活跃 `PairSpace` 失效，但历史 PairSpace 不可自动转给新对象
- 新关系从新 `PairSpace` 开始，不继承旧对象

## 4. Item（事项）

### 4.1 字段
- `id: UUID`
- `relationshipID: UUID?`
- `creatorID: UUID`
- `title: String`
- `notes: String?`
- `executionRole: ItemExecutionRole`
- `priority: ItemPriority`
- `dueAt: Date?`
- `remindAt: Date?`
- `status: ItemStatus`
- `latestResponse: ItemResponse?`
- `responseHistory: [ItemResponse]`
- `createdAt: Date`
- `updatedAt: Date`
- `completedAt: Date?`
- `isDraft: Bool`

### 4.2 ItemExecutionRole
- `initiator`
  - 存储语义：由发起人完成，对方知情
  - UI 映射：根据当前用户显示为“我负责 / 对方负责”
- `recipient`
  - 存储语义：由接收方完成
  - UI 映射：根据当前用户显示为“我负责 / 对方负责”
- `both`
  - 存储语义：双方共同完成
  - UI 映射：显示为“双方 / 一起做”

### 4.3 ItemStatus
- `pendingConfirmation`：待确认
- `inProgress`：进行中
- `completed`：已完成
- `declinedOrBlocked`：未同意 / 无法完成

### 4.4 ItemResponse
- `responderID: UUID`
- `kind: ItemResponseKind`
- `message: String?`
- `respondedAt: Date`

### 4.5 ItemResponseKind
- `willing`
- `notAvailableNow`
- `notSuitable`
- `acknowledged`

## 5. Decision（决策）

### 5.1 字段
- `id: UUID`
- `relationshipID: UUID?`
- `creatorID: UUID`
- `template: DecisionTemplate`
- `title: String`
- `notes: String?`
- `referenceLink: URL?`
- `proposedTime: Date?`
- `status: DecisionStatus`
- `votes: [DecisionVote]`
- `createdAt: Date`
- `updatedAt: Date`
- `archivedAt: Date?`
- `convertedItemID: UUID?`
- `isDraft: Bool`

### 5.2 DecisionTemplate
- `buy`
- `eat`
- `go`

### 5.3 DecisionVote
- `voterID: UUID`
- `value: DecisionVoteValue`
- `respondedAt: Date`

### 5.4 DecisionVoteValue
- `agree`
- `neutral`
- `reject`

### 5.5 DecisionStatus
- `pendingResponse`：待表态
- `consensusReached`：已达成一致
- `noConsensusYet`：暂未达成一致
- `archived`：已归档

## 6. Anniversary（纪念日）

### 6.1 字段
- `id: UUID`
- `relationshipID: UUID?`
- `name: String`
- `kind: AnniversaryKind`
- `eventDate: Date`
- `reminderRule: ReminderRule?`
- `createdAt: Date`
- `updatedAt: Date`

### 6.2 AnniversaryKind
- `relationshipStart`
- `wedding`
- `trip`
- `custom`

### 6.3 ReminderRule
- `leadDays: Int`
- `remindAtHour: Int`
- `remindAtMinute: Int`

## 7. Notification / Reminder

### 7.1 代码命名
- `AppNotification`

### 7.2 字段
- `id: UUID`
- `relationshipID: UUID?`
- `targetID: UUID`
- `targetType: ReminderTargetType`
- `channel: ReminderChannel`
- `status: ReminderDeliveryStatus`
- `title: String`
- `body: String`
- `scheduledAt: Date`
- `deliveredAt: Date?`

### 7.3 ReminderTargetType
- `item`
- `decision`
- `anniversary`
- `invite`
- `binding`

## 8. Invite / BindingState

### 8.1 Invite
- `id: UUID`
- `pairSpaceID: UUID`
- `inviterID: UUID`
- `inviteCode: String`
- `status: InviteStatus`
- `sentAt: Date`
- `respondedAt: Date?`
- `expiresAt: Date`

### 8.2 InviteStatus
- `pending`
- `accepted`
- `declined`
- `expired`
- `cancelled`
- `revoked`

### 8.3 BindingState
- `singleTrial`
- `invitePending`
- `inviteReceived`
- `paired`
- `unbound`

## 9. Assumptions / Open Questions

### 9.1 Assumptions
- 当前字段先覆盖首版闭环，不提前扩成聊天、评论、附件、子任务模型
- `relationshipID == nil` 视为未进入双人空间的本地草稿或示例数据

### 9.2 Open Questions
- Item 是否允许图片 / 链接附件，文档未明确
- Decision 的链接字段是否需要富预览，文档未明确
- Anniversary 是否区分农历、重复周期，文档未明确
