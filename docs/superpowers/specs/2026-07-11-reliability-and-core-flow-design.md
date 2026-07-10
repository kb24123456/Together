# Together 可靠性与核心功能闭环设计

**日期：** 2026-07-11
**状态：** 已确认，待实施计划
**适用范围：** iPhone-only、纯单人、本地 SwiftData + CloudKit private database

## 1. 目标

在不丢失现有用户数据、不改变 CloudKit container、不恢复旧双人路线的前提下，完成以下工作：

1. 消除自动删库、加载失败伪装为空状态和身份接管风险。
2. 取消强制“通过 Apple 登录”，以当前设备 iCloud private database 作为唯一云身份边界。
3. 让“删除所有数据”与实际删除范围一致，并提供可验证的失败处理。
4. 移除双人纪念日 Widget 和相关公开产品入口。
5. 补齐活跃任务搜索与高价值筛选。
6. 提升 OCR 草稿校对效率。
7. 修复 Widget、通知和 URL Scheme 的外部入口语义。
8. 让 iCloud 状态文案只表达能够被当前实现证实的事实。

## 2. 已确认产品决策

- 取消强制“通过 Apple 登录”和“退出登录”。
- 不修改现有 SwiftData schema、不更换 store URL、不更换 CloudKit container。
- 现有 `PersistentUserProfile.userID`、`PersistentSpace.id`、`ownerUserID`、任务和子任务 ID 必须原样保留。
- 同一个 iCloud 账号继续通过 `iCloud.com.pigdog.Together` private database 多设备同步。
- 不同 iCloud 账号之间不共享数据。
- 清单 UI 本轮不继续建设；移除不可达占位承诺，但保留底层模型以避免 CloudKit schema 删除风险。
- 本轮不实现数据导出、App Intent 快速创建或首次引导。
- 不恢复项目、日历、双人协作、纪念日、聊天、Supabase、RevenueCat 或付费能力。

## 3. 实施分解

本设计分为四个可独立交付的子项目。每个子项目必须形成独立实施计划、测试闭环和提交，不允许跨阶段混合大改。

1. 数据安全与无登录迁移。
2. 数据控制与旧功能清理。
3. 活跃任务搜索与筛选。
4. OCR 校对与外部入口修复。

## 4. 子项目一：数据安全与无登录迁移

### 4.1 Store 打开失败

`PersistenceController` 第一次打开或 probe 失败时不得删除 `Together.store`、WAL、SHM 或 external-storage support 目录。

启动结果改为显式状态：

- `ready(ModelContainer)`：正常进入应用。
- `failed(PersistenceStartupFailure)`：保留所有 store 文件并进入不可写的恢复提示页。

恢复提示页只提供：

- 重试打开。
- 查看简短错误说明。
- DEBUG 构建中的显式开发者重置入口。

Release 构建不提供自动重置，也不把 store 打开失败解释为“没有数据”。

### 4.2 页面加载状态

首页、例行任务和清单数据源统一遵循：

- 首次加载：显示 loading。
- 刷新失败且已有数据：保留最后一次成功数据，显示非阻断错误和重试。
- 刷新失败且没有缓存：显示错误状态和重试。
- 只有成功读取到空集合后才能显示空状态。

完成、删除、推迟、恢复和保存失败必须产生用户可见反馈。不得继续使用空 `catch {}` 或仅在 DEBUG 打印错误。

### 4.3 取消强制 Apple 登录

删除登录门槛后，应用启动不再依赖 Keychain 中的 Apple user identifier，也不再校验 Sign in with Apple credential state。

本地身份解析顺序：

1. 如果存在 `PersistentUserProfile`，选择与数据承载单人空间一致的 profile，并保留其 `userID`。
2. 如果存在单人空间但 profile 暂未恢复，进入“正在恢复数据”状态，不改写 `ownerUserID`。
3. 如果本地 store 为空且 iCloud 可用，保持“正在恢复数据”状态并观察 `NSPersistentCloudKitContainer.eventChangedNotification` 的首次成功 import 事件；事件到达后再次查询。
4. 首次成功 import 后仍没有 profile/space 时，展示“开始使用”操作，由用户确认后创建一组新的 profile/space；不得仅凭固定超时自动创建。
5. 如果用户在无 iCloud 或离线状态下明确选择本机使用，创建一组新的 profile/space。

`LocalSpaceService` 不再根据本次临时用户 ID 自动 claim 数据空间，也不得批量重写任务、清单、项目或例行任务的 creator ID。

### 4.4 新设备与离线初始化

新设备同一 iCloud 账号：

- 首屏允许持续展示恢复状态；超过 10 秒只更新为“恢复时间较长”，不自动创建第二个空间。
- CloudKit 导入已有 profile/space 后使用其原始 ID。
- 不在恢复完成前创建第二个默认空间。

离线且 store 为空：

- 提供“先在本机使用”。
- 新建空间标记为 provisional bootstrap state，但不新增 CloudKit schema 字段；状态保存在本机配置中。
- 后续发现远端已有数据时，优先保留远端数据承载空间；本机 provisional 数据按实体 ID 去重后迁入远端空间。
- 合并只发生在单人空间之间，并在成功保存后才移除 provisional 标记。

### 4.5 身份迁移验收

- 升级现有安装后任务数量、ID、完成状态、子任务、例行任务和设置不变。
- 现有 profile 和 data-bearing space 的 ID 不变。
- 同一 iCloud 账号第二台设备能恢复同一数据。
- 不同 iCloud 账号看不到彼此 private database 数据。
- 应用内不再出现登录、退出登录或账号注销语义；只保留“删除所有数据”。

## 5. 子项目二：数据控制与旧功能清理

### 5.1 删除所有数据

新增单一 `PersonalDataDeletionService`，负责枚举并删除：

- 任务及 occurrence completion。
- 普通任务子任务。
- 例行任务及其完成记录。
- 任务模板。
- 自定义和系统清单记录。
- legacy project/project subtask 记录。
- 单人空间。
- 用户资料。
- 本地头像文件和 legacy avatar payload。
- Widget snapshot 与 shared context。
- 本地通知和 AlarmKit 调度。
- 与应用锁、恢复提示和 provisional bootstrap 相关的 UserDefaults。

删除采用明确阶段和结果清单：

1. 读取删除 manifest。
2. 取消通知和闹钟。
3. 在 SwiftData 中删除业务实体并保存。
4. 删除头像和 Widget 文件。
5. 重新读取 store 验证 manifest 对象均不存在。
6. 成功后重建空的单人 profile/space，直接回到应用，而不是退出登录页。

任一关键阶段失败：

- 保持删除页面可见。
- 展示失败原因和“重试”。
- 不宣称完成。
- 不自动退出或清空 UI session。

CloudKit 删除是 SwiftData 托管同步的后续结果。UI 文案只能写“已从本机删除，iCloud 会继续同步删除”，不能承诺不可观测的即时云端清空。

### 5.2 旧 Widget 和旧功能残留

- 从 `TogetherWidgetBundle` 移除 `AnniversaryWidget`。
- 删除 Anniversary Widget 代码、snapshot、资源和未再引用的常量。
- 保留 CloudKit 已发布 schema 所需的 legacy SwiftData model；不把 legacy model 暴露为产品功能。
- 全局搜索 `双人|纪念日|配对|partner|AnniversaryWidget`，只允许明确的 migration 注释或历史文档命中。

### 5.3 iCloud 状态

当前只通过 `CKContainer.accountStatus()` 得到账号可用性，因此文案必须使用：

- iCloud 已登录。
- 未登录 iCloud。
- iCloud 访问受限。
- iCloud 暂时不可用。
- 无法确认 iCloud 状态。

不得使用“同步完成”“已连接”“所有数据已上传”等无法证实的状态。启动阶段可以用 CloudKit import event 判断是否完成首次恢复检查，但不把单次 import event 等同于持续同步健康；最近成功时间和长期错误诊断后续单独设计。

## 6. 子项目三：活跃任务搜索与筛选

### 6.1 功能范围

首页增加系统原生搜索入口，搜索范围包括：

- 任务标题。
- 任务备注。
- 子任务标题。

筛选仅包含四个可组合条件：

- 紧急。
- 逾期。
- 无日期。
- 含提醒。

搜索与筛选只作用于当前首页已加载的全部未归档任务和今天已完成任务；已完成历史继续使用现有分页搜索。

### 6.2 状态与交互

- 搜索和筛选不修改持久化数据。
- 清除搜索后恢复原日期分组和排序。
- 筛选结果为空时显示“没有符合条件的任务”，不能显示首次使用空状态。
- 搜索、筛选和内联展开互斥；开始搜索时先保存并收起当前编辑草稿。
- 筛选面板使用原生 sheet/Menu，不引入新的自定义导航层。
- 排序继续使用当前业务规则：日期组、紧急优先、时间和 `sortOrder`；本轮不新增用户自定义排序模式。

### 6.3 清单边界

- 从当前产品文档中移除“清单已是 MVP 可用能力”的表述。
- `ListsView` 不加入导航，不继续展示“下一步会接入”的用户可见占位文案。
- `TaskList` 和 `PersistentTaskList` 暂时保留，服务 legacy 数据和 CloudKit schema 兼容。
- 完整清单功能必须在后续独立规格中重新确认 IA 后才能实施。

## 7. 子项目四：OCR 校对与外部入口

### 7.1 OCR 原文对照

确认页增加可折叠“识别原文”区域，直接读取 `OCRImportDraft.rawText`。默认收起，展开后可复制，不直接编辑原文。

### 7.2 顶层草稿操作

OCR 确认页支持：

- 新增顶层任务。
- 删除顶层任务。
- 拖动调整顶层任务顺序。
- 将相邻任务合并：后一任务标题和子任务并入前一任务的子任务列表，原始文本仍保留。
- 将选中的子任务拆分为新的顶层任务。

所有操作只修改内存中的 `OCRImportDraft`；用户点击“导入”前不得写入 SwiftData。

### 7.3 OCR 解析边界

本轮继续使用 Vision + 本地 parser，不引入联网 AI 或 Foundation Models。parser 可增加确定性的日期、时间和紧急词规则，但必须满足：

- 无法确定时保持普通文本，不猜测。
- 解析结果始终可编辑。
- 每条自动解析规则都有单元测试。

文档扫描裁切、透视校正和多页 VisionKit 扫描不纳入本轮；当前相机和最多六张照片入口继续保留。

### 7.4 外部入口路由

定义明确 URL 路由：

- `together://today`：切换到任务首页并收起例行任务模式。
- `together://task/<uuid>`：刷新首页后定位并高亮任务。

Widget 根链接使用 `together://today`，每个支持链接的任务行使用 task URL。完成框仍只触发 `TodayTaskCompletionIntent`。

通知点击使用同一 task route。目标任务不存在、已删除或无法读取时：

- 回到任务首页。
- 显示“该任务已不存在或尚未同步完成”。
- 提供一次刷新重试，不进入空白页面。

## 8. 错误处理原则

- 数据读取失败与数据为空必须是两个状态。
- 异步写入失败必须保留用户输入或现有数据。
- 删除、迁移和身份归并不得使用 `try?` 隐藏关键错误。
- 所有后台错误使用 `Logger` 记录安全摘要，不记录任务标题、OCR 文本或私人内容。
- UI 只展示可行动的简短错误和重试入口。

## 9. 测试与验证

### 9.1 自动化测试

必须新增以下测试组：

- Store 首次打开失败不会调用文件删除。
- 首页/例行加载失败保留已有数据并暴露错误状态。
- 现有 profile/space 解析保留原始 ID。
- 不同临时身份不会触发空间 ownership claim。
- provisional 空间与远端空间合并的去重和失败回滚。
- 删除 manifest 覆盖所有模型、文件、Widget 和通知层。
- 删除任一阶段失败不会报告成功。
- 首页标题/备注/子任务搜索和四类筛选。
- OCR 顶层新增、删除、排序、合并、拆分。
- `today`、有效 task、无效 task 三类 Deep Link。
- Widget task URL 与 completion intent 命中区域保持独立。

### 9.2 静态与构建验证

每个子项目至少执行：

```bash
git diff --check
rg -n "双人|纪念日|配对|partner|AnniversaryWidget" Together TogetherWidget TogetherTests
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

如果本机 simulator runner 无法执行，必须保留完整错误并明确标记“仅测试编译通过”，不能写成测试通过。

### 9.3 真机验收

以下项目必须真机验收：

- 旧版本原地升级保留全部数据。
- 同一 iCloud 账号两台设备同步。
- 删除 App 后重装恢复。
- 离线首次启动后恢复联网并归并。
- 切换设备 iCloud 账号后的数据隔离。
- 删除所有数据在另一台设备同步消失。
- Widget 点击、任务定位、完成动作和返回 App 刷新。
- OCR 相机、照片、中文输入法与大量草稿编辑。

## 10. 提交与发布顺序

1. 数据库失败保护和加载状态。
2. 无登录迁移与身份解析。
3. 删除所有数据。
4. Anniversary Widget 清理和 iCloud 文案。
5. 首页搜索与筛选。
6. OCR 校对。
7. Deep Link、Widget 和通知入口。
8. 全量回归、项目记忆更新和真机验收清单。

任何阶段出现数据迁移、CloudKit 或测试失败时，后续阶段暂停，不允许用新增 UI 掩盖可靠性问题。

## 11. 非目标

- 不修改 CloudKit container identifier。
- 不删除已发布 CloudKit schema 中的 legacy record type。
- 不实现跨 iCloud 账号共享。
- 不增加团队、多人、情侣或社交功能。
- 不建设完整清单、标签或文件夹系统。
- 不建设独立项目或日历页面。
- 不接入第三方后端、账号系统、AI 服务或分析 SDK。
- 不在本轮实现导入/导出、快捷指令或新手引导。

## 12. 完成标准

- 不存在未经用户明确操作的本地 store 删除路径。
- App 不再要求 Apple 登录，现有数据和 ID 原样保留。
- 同一 iCloud 账号的自动同步配置不变。
- 删除所有数据具有完整 manifest、验证和错误反馈。
- 用户看不到旧双人纪念日 Widget 或双人产品入口。
- 活跃任务可搜索并按四类条件筛选。
- OCR 草稿可对照原文并完成顶层结构校对。
- Widget、通知和 URL Scheme 均能可靠回到正确首页或任务。
- 自动化测试、真实构建和明确列出的真机验收范围全部有可追踪结果。
