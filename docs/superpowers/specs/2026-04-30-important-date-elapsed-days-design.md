# Important Date Elapsed Days Display Design

## 任务目标

在现有纪念日能力上，为用户创建的纪念日与自定义日期增加“同时展示累计天数”偏好。打开后，同一个日期锚点可以同时表达两类计数：

- 距离下一次还有多少天：`还有 N 天`
- 从首次日期累计至今天多少天：`已经 N 天`

该偏好需要影响纪念日管理 sheet 与 Today 首页粉色纪念日胶囊，并在双人空间中同步。

## 范围

### 包含

- `ImportantDate` 增加一个布尔展示偏好。
- SwiftData 本地模型、Supabase `important_dates`、DTO push/pull 同步该偏好。
- `ImportantDatesManagementView` 列表行内为 `anniversary` 与 `custom` 显示开关。
- `AnniversaryCapsuleView` 根据该偏好决定是否允许长按切换累计天数。
- 测试覆盖 DTO、push/pull、默认兼容和计数规则。

### 不包含

- 不改变生日、节日的展示逻辑。
- 不把纪念日升级为 V1 首页主链路。
- 不新增多人模式或新的关系运营入口。
- 不重构纪念日编辑页整体结构。

## 产品规则

1. `birthday` 与 `holiday` 永远只显示 `还有 N 天`，不出现“同时展示累计天数”开关。
2. `anniversary` 与 `custom` 可由用户在纪念日管理 sheet 行内打开或关闭“同时展示累计天数”。
3. 开关打开时，sheet 行内同时显示 `还有 N 天` 与 `已经 N 天`。
4. 开关关闭时，sheet 行内只显示 `还有 N 天`。
5. 首页粉色纪念日胶囊遵守同一个偏好；关闭时不能长按切到 `已经 N 天`。
6. 累计天数文案统一使用 `已经 N 天`，不使用 `已 N 天`。

## 默认与兼容

- 现有 `kind = anniversary` 记录默认视为 `showsElapsedDays = true`，用于兼容当前已创建的“我们在一起的日子”。
- 现有 `kind = custom` 记录默认视为 `showsElapsedDays = false`。
- 新建 `anniversary` 与 `custom` 默认 `showsElapsedDays = false`，避免用户没有意识到就多展示一行。
- 新建 `birthday` 与 `holiday` 固定 `showsElapsedDays = false`。

## 数据设计

### Domain

`ImportantDate` 增加：

```swift
var showsElapsedDays: Bool
```

建议补一个计算属性，用于统一 UI 判断：

```swift
var supportsElapsedDaysDisplay: Bool
```

规则：仅 `anniversary` 与 `custom` 返回 `true`。

### SwiftData

`PersistentImportantDate` 增加：

```swift
var showsElapsedDays: Bool
```

`domainModel()`、`make(from:)`、`apply(from:)` 都必须双向映射该字段。

### Supabase

新增 migration：

```sql
alter table public.important_dates
add column if not exists shows_elapsed_days boolean not null default false;

update public.important_dates
set shows_elapsed_days = true
where kind = 'anniversary' and is_deleted = false;
```

说明：数据库默认值保持 `false`，只对现有未删除 anniversary 做一次兼容回填。

### DTO

`ImportantDateDTO` 增加 snake_case 字段：

```swift
var showsElapsedDays: Bool
// CodingKey: shows_elapsed_days
```

解码旧数据时需要兼容缺字段。推荐手写 `init(from:)`，缺失时按 `kind` 派生默认值：

- `anniversary` -> `true`
- 其他 -> `false`

## UI 设计

### 纪念日管理 Sheet

列表行保持 iOS 原生 plain list 风格，不恢复大卡片。

行内布局：

- 左侧：标题、日期与 recurrence 标识。
- 右侧：计数区与 Toggle。
- `showsElapsedDays = true` 时计数区两行：
  - `还有 N 天`
  - `已经 N 天`
- `showsElapsedDays = false` 时计数区一行：
  - `还有 N 天`
- Toggle 只在 `anniversary/custom` 行出现。

交互：

- 点行非 Toggle 区域：进入编辑 sheet。
- 点 Toggle：只切换 `showsElapsedDays` 并保存，不打开编辑 sheet。
- Toggle 操作触发轻反馈，保存失败时回滚或重新加载当前列表。

### 首页粉色胶囊

当前胶囊继续通过最近一个重要日期展示。

规则：

- 当 `event.supportsElapsedDaysDisplay && event.showsElapsedDays` 为 `true` 时，长按可在 `还有 N 天` 与 `已经 N 天` 间切换。
- 当不满足时，禁用累计天数切换，只显示 `还有 N 天`。
- 如果 `@AppStorage("together.anniversaryCapsule.countMode")` 当前残留为 elapsed，但新的 nextEvent 不允许累计展示，需要自动回退为 next。
- 数字变化继续使用 `.contentTransition(.numericText())`。

## 数据流

1. 用户在 `ImportantDatesManagementView` 行内切换 Toggle。
2. View 构造新的 `ImportantDate` 值，仅修改 `showsElapsedDays` 与 `updatedAt`。
3. 调用 `ImportantDatesViewModel.save(_:)`。
4. `LocalImportantDateRepository.save(_:)` 更新 SwiftData 并记录 `.importantDate` upsert sync change。
5. Supabase push 将 `shows_elapsed_days` 写入远端。
6. 伴侣设备 pull/realtime 收到更新后，本地 UI 刷新。

## 测试策略

### 单元测试

- `ImportantDateDTO` 编码包含 `shows_elapsed_days`。
- `ImportantDateDTO` 解码旧 JSON 缺字段时：
  - `kind = anniversary` 得到 `true`
  - `kind = custom` 得到 `false`
- `ImportantDateDTO(from: PersistentImportantDate)` 能带出 `showsElapsedDays`。
- pull 新增与更新时能写入 `PersistentImportantDate.showsElapsedDays`。
- push upsert 时 DTO 包含本地字段值。
- `daysSinceStart` 继续按自然日从 `dateValue` 到今天计算。

### 交互验证

- 纪念日 sheet 中 anniversary/custom 行出现 Toggle，birthday/holiday 行不出现。
- Toggle 不触发行点击编辑。
- 开关打开后 sheet 行展示 `还有 N 天` + `已经 N 天`。
- 首页胶囊在允许时长按切换，禁用时长按无效。
- 连续长按切换不触发同步、排序或重查询，只改本地显示模式。

### 构建验证

- `git diff --check`
- 相关 Swift Testing 测试
- iOS Simulator build

## 风险与边界

- 这是数据库 schema 变更，必须同时更新 Supabase migration、DTO 和测试，不能只做本地字段。
- 旧 JSON 解码需要兼容缺字段，否则历史同步数据或测试 fixture 可能失败。
- 行内 Toggle 会提高列表密度，实现时要优先保证可读性和点击区域，不为了塞信息牺牲交互。
- 首页 `@AppStorage` 是全局模式偏好，必须在当前事件不支持累计时回退，避免显示状态残留。

## 用户确认

- 开关位置：纪念日管理 sheet 列表行内。
- 文案：`已经 N 天`。
- 开关语义：该日期的全局展示偏好，关闭后 sheet 和首页都不展示累计天数。
- 默认兼容：现有 anniversary 默认开，现有 custom 默认关，新建 anniversary/custom 默认关。
