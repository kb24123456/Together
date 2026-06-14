# 一起 下一步建议

## 1. 第一优先级：完成纯单人化迁移
- 删除 Supabase、RevenueCat、Paywall、PremiumGate、双人协作、邀请、聊天、关系运营相关入口与装配。
- 将启动链路收敛为本地 SwiftData + CloudKit private database + 本地通知。
- 将 `SessionStore / AppContext / AppContainer` 改成纯单人依赖，不再维护 pair mode、shared sync、premium gate。

## 2. 第二优先级：重塑核心数据模型
- 将 Task / TaskList / Project / Reminder 改成纯单人语义。
- 删除 `assigneeMode / assignmentState / responseHistory / assignmentMessages / partner` 等协作字段。
- 删除旧 Supabase outbox / recovery cursor / realtime DTO。
- 建立 CloudKit 兼容 SwiftData schema。

## 3. 第三优先级：恢复主链路可运行
- 保留当前 Today 视觉方向。
- 跑通任务创建、完成、恢复、归档、排序、筛选。
- 跑通清单、项目、日历的纯单人数据流。
- 确保 Profile 只保留个人设置、通知、主题、隐私和 iCloud 状态。

## 4. 第四优先级：Widget 适配
- 保留 Today widget 展示个人任务。
- 重写完成任务写入路径，移除 Supabase outbox 依赖。
- 确认 Widget snapshot 与新 SwiftData schema 一致。

## 5. 第五优先级：OCR MVP
- 新增 OCR 扫描导入入口。
- 使用 Vision / VisionKit 识别图片文字。
- 将识别结果转换为 `OCRImportDraft`。
- 用户确认后再写入 Task / Project。

## 6. 工程治理
- 为关键状态机、repository、OCR parser、Widget completion 建立可持续单测。
- 增加 lint / format / CI。
- 为设计 token 与动效 token 建立统一入口。
- 补充数据删除、iCloud 同步、相机权限和 OCR 隐私说明。

## 7. 当前不要做
- 不要新增任何双人、多人、邀请、共享、聊天或关系运营能力。
- 不要继续接入或修补 Supabase。
- 不要继续接入或修补 RevenueCat / Paywall / Pro gate。
- 不要把 OCR 结果未经用户确认直接写入任务。
- 不要先重写当前首页 UI。
- 不要做只有炫技价值、没有任务效率价值的动画。
