# App Store 更新准备

状态：准备中；已创建 ASC 2.0 草稿，并写入、回读核对已确认的中文名称与副标题。本地桌面名称已更新，尚未上传新构建或提交审核。英文名称与截图方向待确认。

最新决定：用户选择等待 Xcode 27 正式版后上架，不配置云构建。分发证书与主 App / Widget 的 App Store 描述文件已创建、安装并核验，私钥签名探针通过。详见 `docs/app-store/2026-09-05/signing-and-resume.md`；实际 App 的正式归档、导出与上传仍待完成。

## 已核实

- ASC App ID：6763774768；当前名称「一二：待办清单 提醒事项 双人协作」。
- 当前可分发版本：1.0，绑定 build 47；简体中文页面有 6 张 6.5 英寸截图。
- 旧描述和审核备注仍介绍双人协作、Sign in with Apple、Together Pro 与内购。
- 本地 main 工作区含未提交的最新改动；主 App 和 Widget 仍为 1.0 (46)，Bundle ID 分别为 com.pigdog.Together、com.pigdog.Together.TogetherWidget，最低 iOS 26.0。
- ASC 已登录；首页提示账户持有人需接受新版 Apple Developer Program 许可协议，并提示新的社交媒体年龄分级问题。
- 初查时 PATH 中未发现 asc / fastlane；现已安装并连接 asc（见下文）。随后已创建并导入 Apple Distribution 身份，保留原开发身份。
- 默认 Xcode 为 /Applications/Xcode.app，版本 26.6 (17F113)。Release 无签名构建在 destination 检查失败：iOS 26.5 is not installed；未进入源码编译。
- Together/Features/Profile/LegalURLs.swift 的 privacy / terms 仍为 example.com 占位 URL。
- docs/legal 的现有政策仍含 Supabase、配对等旧产品说明，不能直接作为新版政策发布。
- 当前 PrivacyInfo.xcprivacy 仍声明姓名、用户 ID、邮箱、照片与用户内容；需按实际处理方式与 Apple 的收集定义重新核实，不能直接照旧勾选。
- CloudKit 正式环境和旧版覆盖升级尚未验证；内购记录状态见下文，只读核查未涉及历史交易。

## 推荐发布路径

1. 中文品牌已确认；继续确定英文名称与截图方向。ASC 已按 2.0 创建草稿，最终在检查全部 ASC 构建后确定新 build 号。
2. 等待 Xcode 27 正式版，核实主机兼容性、构建与法律链接；不以 Beta 无签名编译通过替代正式分发验证。
3. 核实 CloudKit production schema、App Group 与分发签名；检查旧商店版覆盖升级，明确旧协作数据与历史购买的处理。
4. 归档上传到 TestFlight，在真机验收同一候选包；保持用户现有数据，不卸载日常使用的 App 来测试恢复。
5. 在新版草稿中更新名称、副标题、描述、关键词、更新说明、截图、支持 URL、政策 URL、隐私标签、年龄分级和审核备注。
6. 所有材料与候选包可审阅且验收通过后提交审核，沿用手动发布策略，除非用户另选。

用户已明确选择后续 CLI 优先。已从 rorkai/App-Store-Connect-CLI 的 GitHub Release 安装 asc 4.11.0（macOS arm64）到 /Users/papertiger/.local/bin/asc，安装前 SHA-256 与 GitHub asset digest 一致。该工具是第三方开源客户端，使用 Apple App Store Connect API。命令行流程使用 asc 管理商店资料与构建、xcodebuild 归档导出；网页用于 API 未覆盖的账号或协议步骤。不把签名证书与 ASC API 密钥混为一谈。

首次使用 Developer 密钥建立系统钥匙串中的 `Together` profile，读取线上 1.0 (47)：构建处理状态 VALID、TestFlight 已过期、商店状态 READY_FOR_DISTRIBUTION，无进行中的审核提交。随后用户提供 App 管理角色新密钥，已建立并切换默认 profile 为 `YierRelease`，`asc auth status --validate` 验证通过；旧 profile 保留。原始私钥权限为 `0600`，未写入项目。

已通过 `YierRelease` 创建 iOS 2.0 草稿，version ID 为 `25a0d05b-80ef-4a58-bbed-b210ddf5b3e0`，editable appInfo ID 为 `3d2c6797-d0b4-47ae-bedd-b7f0e746340b`。中文名称与副标题已写入并独立回读核对，隐私 URL 暂保留现有有效地址。未执行完整元数据 push、上传新构建或提交审核；当前线上仍是 1.0。

## 简体中文文案草稿

用户已确认：手机桌面名称“一二”；App Store 中文名称“一二：待办清单与提醒事项”。主 App 与 Widget 的 CFBundleDisplayName 已同步为“一二”，不改应用或持久化标识。

已确认副标题：日常计划、定期任务与执行回顾

推广文本：把零散的想法整理成行动。管理日常待办与定期任务，将纸面清单转成可编辑草稿，在每周和每月的回顾中看见自己的安排与完成。

描述：

让每天要做的事，清楚一点。

记录临时想法、安排日常任务，把复杂事项拆成一步步可以完成的小事。从待办到定期安排，再到完成后的回顾，在简洁的 iPhone 界面里整理自己的节奏。

• 清晰安排日常：按日期查看待办，设置时间与提醒，处理逾期事项。
• 拆解多步骤任务：添加备注和子任务，把想法变成具体行动。
• 管理定期安排：为重复出现的事项设置周期。
• 从纸面到待办：拍照、选择照片或粘贴文字，先编辑识别草稿，确认后再添加任务。
• 回看执行过程：查看已完成任务、计划变化，以及本周和本月的执行回顾。
• 使用系统入口：通过桌面小组件查看任务，在实时活动中关注当前事项。
• 个人数据与设置：支持 iCloud 同步与恢复、浅色和深色外观，以及应用锁定。

新版专注个人任务管理，不再提供双人协作和应用内订阅购买。

关键词草稿：任务管理,日程,计划,时间管理,效率,子任务,定期,重复任务,文字识别,扫描,回顾,小组件

更新说明草稿：

这次更新带来了重新设计的个人待办体验：
• 全新的待办、定期任务与详情编辑界面。
• 支持拍照识别、照片导入和粘贴文字，确认草稿后添加任务。
• 新增任务履历与本周、本月执行回顾。
• 更新桌面小组件与关注任务实时活动。
• 使用 iCloud 进行个人数据同步与恢复。
• 产品调整为单人使用，移除双人协作与应用内购买入口。

发布前须补充已验证的旧用户升级说明；不得承诺未确认的旧账号数据迁移或历史购买处理。

## 截图内容清单（待确认）

建议以真实新版界面制作 6 张，不复用旧版截图，不将 AI 生成界面当作真实产品截图。

1. 待办首页：今天要做的事，一眼清楚。
2. 任务详情与子任务：把大事，拆成能完成的小事。
3. 定期任务：重复的安排，交给定期任务。
4. OCR 草稿确认：纸上的清单，变成手边的待办。
5. 执行回顾：回看完成，也看见安排的变化。
6. 小组件与实时活动：重要的事，随时看得到。

使用虚构演示内容；优先真机截图，遵循用户既有不启动 Simulator 的偏好。6.9 英寸可选 1320×2868 或 Apple 列明的其他尺寸，最终文件不含透明通道。截图真实性、尺寸与功能可用性均须逐张检查。

## 验证与来源

- git diff --check：通过（新增本文前的当前工作区）。
- Release 构建：失败于缺失平台组件，日志 /tmp/together-release-readiness-20260905.log；不代表代码编译通过。
- Apple Expert 检索 query：App Store distribution beta Xcode SDK acceptance CloudKit production schema deployment provisioning profile；结果：无需 Expert Delta；命中 keys 与实际采用记录均无。
- [Apple 云托管证书](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)
- [Apple 上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [CloudKit 正式环境部署](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)

中文名称与副标题已写入 ASC 2.0 草稿，其余文案仍为本地草稿，均未正式发布。法律协议须由账户持有人查阅并决定是否接受。

## 继续准备的结果

- 已通过 CLI 导出并保留上架 1.0 的中英文资料；已创建 2.0 中英文 canonical JSON 草稿、版本化法律页面草稿及审核说明，位于 `docs/app-store/2026-09-05/`。英文名称仍为候选；中文名称与副标题已写入后台新草稿。
- `asc metadata validate`：4 个草稿文件通过，0 error、0 warning。此为离线检查，`/v2/` URL 尚未部署；不能上传前省略线上 URL 验证。
- 现有 GitHub Pages 法律站仓库可访问，Pages API 状态为 built，仍是旧版内容。新版采用独立 URL 的建议是避免提前覆盖仍服务 1.0 的政策，待确认发布。
- 初查 API 可见证书仅 1 张 DEVELOPMENT、profiles 为空；现已新增 DISTRIBUTION 证书及主 App / Widget 的 IOS_APP_STORE 描述文件。月/年订阅和终身内购均 PENDING_BINARY_APPROVAL，未执行销售状态变更或删除。
- `cktool get-teams` 明确返回缺少 management token；ASC API 密钥不替代 CloudKit 管理授权。正式 schema 尚未验证。
- Xcode 26.6 列出 iOS 26.5 SDK，但全部 iOS destination 不可用。进一步尝试启动应用时，系统返回 kLSIncompatibleApplicationVersionErr；Apple 支持表将其限定在 macOS 26.2–26.x，本机 macOS 27 Beta 不在支持范围内。已停止对该不受支持组合继续排查。
- 当前主机为 macOS 27.0 Beta（26A5425a）。Apple 发布页仍将 Xcode 27 列为 Beta；需确认可接受的分发工具链后再归档上传，不修改归档元数据伪装正式环境。
- Xcode 27 Beta：`-configuration Release build` 无签名主 App / Widget 构建通过。首次 `-configuration Release build-for-testing` 失败于 Together 模块未启用 `-enable-testing`；改用 `-configuration Debug build-for-testing` 后 `TEST BUILD SUCCEEDED`。均未运行模拟器或真机测试。
- plist 与 entitlement 的 `plutil -lint` 通过，`git diff --check` 通过。隐私清单语法正确不等于数据披露语义已完成审核。
