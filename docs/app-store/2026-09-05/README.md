# 2.0 发布材料草稿

ASC 已创建 `2.0` 草稿，已写入并回读核对用户确认的中文名称与副标题。其他材料尚未上传或发布，工程版本仍是本地 1.0 (46)，尚未上传新构建或提交审核。CLI 默认使用系统钥匙串中的 `YierRelease` profile，App 管理角色已验证。

用户已选择等待 Xcode 27 正式版再上架，不配置云构建。分发证书与主 App / Widget 的 App Store 描述文件均已创建并安装，私钥签名探针通过。恢复发布见 [签名与后续步骤](signing-and-resume.md)，导出设置见 `ExportOptions.plist`；尚未验证实际 App archive / export。

- `live-metadata/`：2026-09-05 通过 ASC API 导出的已上架 1.0 中英文资料，供追溯与比较。
- `draft-metadata/`：可由 `asc metadata` 读取的中英文草稿，已通过离线字段与字数检查。
- `legal/`：新版政策、条款和支持页草稿；计划使用独立 `/v2/` 地址，保留旧版政策供仍使用 1.0 的用户查阅。部署地址尚不存在，不能把离线校验通过理解为 URL 已可用。
- `review-notes.md`：审核说明和发布前待核实事项。

用户已确认桌面名称“一二”、中文 App Store 名称“一二：待办清单与提醒事项”、副标题“日常计划、定期任务与执行回顾”。主 App 与 Widget 的 CFBundleDisplayName 已更新为“一二”，Bundle ID、App Group 与 CloudKit 容器身份保留。英文商店名称仍为未定稿草稿，不得按已确认内容上传。截图方向与来源待用户确认，尚未生成或上传截图。

当前入口：[App Store 更新准备](../../app-store-update-2026-09-05.md)。

## 检查命令

```sh
asc --profile YierRelease status --app 6763774768 --include app,builds,appstore,submission
asc metadata validate --dir docs/app-store/2026-09-05/draft-metadata
git diff --check
```

新版法律页面部署后，再使用 `asc metadata validate --dir docs/app-store/2026-09-05/draft-metadata --check-urls`。不要在 URL 未部署、名称未确认、发布候选未验证时执行 push。

## 尚未完成的发布条件

- 确认英文商店名称、截图方向和来源；中文品牌已确认，ASC 已按 2.0 创建草稿。
- Apple 开发者协议接受状态需账户持有人处理并复核。
- 分发证书和两份描述文件已核验；待使用正式工具链验证实际 App 的归档、导出与上传。
- 本机 macOS 27 Beta 不在 Xcode 26.6 官方支持范围内，且系统拒绝启动该 Xcode。按用户决定等待 Xcode 27 正式版，届时复核主机与发布工具链兼容性。
- `cktool` 未配置 management token，CloudKit production schema 未核实。
- 旧版覆盖升级和正式 iCloud 同步/恢复尚未真机验收。代码确认使用 SwiftData V4 migration plan，启动失败不自动删库；这不等于真实升级已验证。
- 公共政策、App 内法律链接、隐私标签与隐私清单需同步；目前 App 内仍是 example.com 占位链接。

## 内购只读核查

月订阅 `com.pigdog.together.monthly1m`、年订阅 `com.pigdog.together.yearly`、终身内购 `com.pigdog.together.lifetime` 当前均为 `PENDING_BINARY_APPROVAL`。未发现这三项显示 APPROVED；未查询收入、历史交易或订阅用户数量，不能据此保证从未发生过购买。不删除记录，不自动变更销售状态，也不把它们随新版加入审核。

## Retrieval Evidence

- Query：`SwiftData CloudKit production schema App Store upgrade migration legacy local store recovery`
- 命中 keys：无。
- 实际采用记录：无；无需 Expert Delta。

参考：[Apple 数据收集定义](https://developer.apple.com/app-store/app-privacy-details/)、[Apple 最新工具链](https://developer.apple.com/news/releases/)。隐私标签应以开发者和第三方实际取得的数据为准；权限申请、本地存储和用户私人 iCloud 同步不应未经分析直接等同为开发者收集。
