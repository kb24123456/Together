# 分发签名与恢复发布

## 当前决定

用户于 2026-09-05 明确选择等待 Xcode 27 正式版后上架，不启用云构建。本轮不上传 Beta 工具链构建，不提交审核。未创建自动监控或定时任务。

本机 macOS 27 Beta（26A5425a）启动 Xcode 26.6 被 LaunchServices 拒绝，错误为 `kLSIncompatibleApplicationVersionErr`。Apple [Xcode 系统要求](https://developer.apple.com/xcode/system-requirements) 将 Xcode 26.6 的支持范围列为 macOS 26.2–26.x；这台机器不在范围内。命令行仍列出 SDK，但全部 iOS destination 均不可用。无需继续通过下载模拟器或修改 Xcode 元数据绕过。

## 已配置的签名资产

- 系统登录钥匙串含有效 `Apple Distribution: Yunfeng Liao (N2ZJ3W3FFD)` 身份。
- 证书有效至 2027-09-05 05:20 UTC；原开发证书保留，未撤销任何既有证书。
- 主 App 描述文件：`Yier App Store 20260905`，类型 `IOS_APP_STORE`，匹配 `com.pigdog.Together`。
- Widget 描述文件：`Yier Widget App Store 20260905`，类型 `IOS_APP_STORE`，匹配 `com.pigdog.Together.TogetherWidget`。
- 两者已安装至 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`；共同包含 `group.com.pigdog.together.shared`，证书指纹一致，`get-task-allow` 为 false。
- 主 App 描述文件包含 `iCloud.com.pigdog.Together` 和生产 APNs 权限。描述文件允许的权限不等于 CloudKit production schema 已部署。
- 私钥、CSR、证书和原始描述文件位于项目外 `~/.config/yier-release/signing/`，目录权限 0700、文件 0600；不得提交到仓库。
- Widget 首次创建遇 Apple HTTP 500；先回读确认未创建后重试成功，无重复描述文件。

`ExportOptions.plist` 已准备：本地导出 App Store Connect IPA、手动选择两份分发描述文件、CloudKit Production、不自动变更 build 号。工程日常开发仍保留 automatic signing，归档导出阶段才使用此文件。

## Xcode 27 正式版可用后的顺序

1. 核对 Apple 发布公告、正式版 SDK 和当前 macOS 的支持范围；正式版 Xcode 发布并不自动证明当前 Beta macOS 可用于正式发布。
2. 核对待发布工作区和 ASC 全部 build 号，将主 App / Widget 统一设为 2.0 和新的未使用 build 号（当前工程仍为 1.0 / 46）。
3. 复核开发者协议、CloudKit production schema、法律链接、隐私披露、年龄分级、旧用户升级与恢复条件。
4. 使用正式版 Xcode 构建并归档；重新检查归档内主 App / Widget 的版本、显示名、签名、权限和隐私清单。
5. 使用本目录 `ExportOptions.plist` 导出，确认真实产物的 CloudKit 环境为 Production、App Group 正确，再上传 TestFlight。
6. 真机验收同一候选包，完成真实截图和最终商店文案后提交审核；保持手动发布。

## 验证边界

已验证证书身份、描述文件内容、证书匹配和本地安装；使用临时复制的独立二进制完成 `codesign` 签名与 `--verify --strict` 验证，确认私钥可用。尚未执行真实 App 的正式版 archive / export / upload，不能据此声称新版已具备完整分发能力。

Apple Expert Retrieval Evidence：query 为 `Xcode generic iOS destination platform not installed SDK exists distribution signing App Store beta Xcode`；命中 keys 与实际采用记录均无，结果为“无需 Expert Delta”。
