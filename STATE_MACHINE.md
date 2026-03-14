# 一起 状态机说明

## 1. 任务状态机（V1 核心）

### 1.1 状态
- `draft`
- `inbox`
- `todo`
- `inProgress`
- `completed`
- `archived`

### 1.2 流转
1. 快捷新建但未保存 -> `draft`
2. 保存任务 -> `inbox`
3. 进入计划状态、被整理进待办视图 -> `todo`
4. 开始执行 -> `inProgress`
5. 完成 -> `completed`
6. 手动归档 -> `archived`
7. 已完成任务重新打开：
   - 有明确时间或仍需继续推进 -> `todo`
   - 无明确承载位置 -> `inbox`

### 1.3 关键规则
- `inbox` 表示已收集、未整理。
- `todo` 表示已进入正式待办系统，可以出现在 Today、项目、清单或日历视图中。
- `inProgress` 适合承载“当前正在做”的任务聚焦状态。
- `completed` 与 `archived` 必须区分，归档不是完成的同义词。

## 2. 项目状态机

### 2.1 状态
- `active`
- `onHold`
- `completed`
- `archived`

### 2.2 流转
1. 创建项目 -> `active`
2. 暂停推进 -> `onHold`
3. 恢复推进 -> `active`
4. 完成 -> `completed`
5. 手动收纳历史项目 -> `archived`

### 2.3 规则
- `completed` 项目默认仍可查看历史任务。
- `archived` 项目不应继续出现在主工作流入口。

## 3. Today 视图交互状态

### 3.1 日期焦点
- `today`
- `otherDay`

切换日期时只改变焦点日期，不改变任务底层状态。

### 3.2 任务详情展开
- `collapsed`
- `peek`
- `expanded`

适用于首页卡片、底部详情抽屉、任务详情页的联动过渡。

### 3.3 筛选与排序
- `default`
- `filtered`
- `sorted`

筛选和排序属于展示状态，不写进任务模型本身。

## 4. 日历视图状态

### 4.1 模式
- `week`
- `month`

### 4.2 流转规则
- 周 / 月切换只改变日历可视密度与导航方式。
- 当前焦点日期必须在两种模式之间保留。

## 5. 主按钮状态
- `collapsed`
- `expanded`
- `presentingSheet`

用于承载“新建任务 / 新建项目 / 快捷整理”等后续入口。

## 6. 双人模式状态机（V2 预留）

### 6.1 状态
- `singleActive`
- `pairInvitationPending`
- `pairActive`
- `pairEnded`

### 6.2 规则
- 该状态机属于未来协作层，不是 V1 核心主状态机。
- 双人协作不应反向定义单人任务的基础生命周期。

## 7. 动效约束
- 任务完成：使用自然收束的完成动画与轻量触感反馈。
- 日期切换：使用短响应的层级切换，不做花哨翻页。
- 周 / 月切换：优先做结构连贯的尺寸与透明度过渡。
- 详情展开 / 收起：优先使用系统感 sheet 或卡片连续过渡。
- 筛选 / 排序 / 分组切换：优先做内容重排动画，避免瞬间跳变。

## 8. Open Questions
- V1 是否需要 `snoozed` 这类独立状态，还是先通过 `remindAt` + `todo` 组合表达。
- 任务从 `inbox` 进入 `todo` 的具体触发动作，是否要在产品层明确为“整理完成”。
