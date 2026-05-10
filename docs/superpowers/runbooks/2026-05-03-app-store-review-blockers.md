# App Store 送审阻塞清单

本清单记录 2026-05-03 在 App Store Connect、RevenueCat 与本地仓库对照检查中发现的送审阻塞项，并在 2026-05-10 按截图素材、RevenueCat 后台只读复检和当前本地构建号更新。后续完成其他修改后，送审前应先对照本文件逐项复检，再回到 `2026-05-03-app-store-release-readiness.md` 做完整验收。

## 当前结论

当前仍不能直接提交 App Store 审核。仓库内可控的 Pro 旧文案、法律文档产品定位、App 内隐私/条款摘要和 ASC 可粘贴材料已更新；桌面宣传截图已整理出 iPhone 6.9 安全上传包；V1 target 已改为 iPhone-only，避免继续按 Universal App 补 iPad 截图；RevenueCat current offering 与 entitlement 已确认收敛。核心阻塞转为 App Store Connect 后台元数据、截图上传、构建绑定、审核信息、IAP / 订阅元数据、隐私标签保存，以及最终 TestFlight 真机验收。

## 1. App Store 元数据阻塞

- [ ] App 描述中仍包含与当前架构冲突的旧表述。
  - 当前发现：描述里仍写有“数据存于你的 iCloud 私有库，归你所有”。
  - 风险：当前 App 已使用 Supabase / RevenueCat / Apple 平台服务，旧表述与法律文档和真实后端架构冲突。
  - 完成标准：App Store 描述与 `docs/legal/privacy-policy.md`、`docs/legal/terms-of-service.md`、当前代码架构一致。
  - 2026-05-04 本地处理：已新增可粘贴新版描述 `docs/superpowers/runbooks/2026-05-04-app-store-connect-submission-materials.md`，需在 ASC 后台替换保存。

- [ ] Pro 功能文案需要和真实已上线功能对齐。
  - 当前发现：描述里提到“自定义主题与 App 图标”“优先客服支持”。
  - 风险：如果这些功能当前 build 未真实提供，审核和用户预期都会受影响。
  - 完成标准：App Store 描述、Paywall 文案、Profile 会员页和真实功能完全一致。
  - 2026-05-04 本地处理：Profile 会员入口已移除“自定义主题”承诺；法律文档和送审材料不再承诺 App 图标、优先客服支持等未上线功能。仍需在 ASC 后台替换旧描述。

## 2. 截图与版本素材阻塞

- [ ] App Store 版本页未上传 iPhone 截图。
  - 当前发现：iPhone 截图显示 `0/10`。
  - 风险：首次送审必须提供截图。
  - 完成标准：至少上传符合 App Store Connect 尺寸要求的 iPhone 截图，并确认截图反映最新 Release/TestFlight UI。
  - 2026-05-10 本地处理：已将 `/Users/papertiger/Desktop/宣传截图` 下 7 张 `852x1846` PNG 转换整理到 `/Users/papertiger/Desktop/宣传截图_ASC/iPhone-6.9/01.png` 至 `07.png`，尺寸均为 `1320x2868`，符合 iPhone 6.9 portrait 上传规格。
  - 2026-05-10 本地处理：另生成安全上传包 `/Users/papertiger/Desktop/宣传截图_ASC/iPhone-6.9-safe/01.png` 至 `06.png`，已排除原第 6 张含系统 App / 微信等第三方图标风险的素材。

- [x] V1 已改为 iPhone-only，规避 Universal App 的 iPad 截图要求。
  - 2026-05-10 本地处理：`Together.xcodeproj/project.pbxproj` 中 App、Widget、Test targets 的 `TARGETED_DEVICE_FAMILY` 已从 `"1,2"` 改为 `1`。
  - 完成标准：重新 build / archive / upload 后，在 App Store Connect 版本页确认仅要求 iPhone 截图。

## 3. 构建版本绑定阻塞

- [ ] 最新 TestFlight build 未绑定到 iOS 1.0 待提交版本。
  - 当前发现：版本页仍显示“添加构建版本”。
  - 已确认：2026-05-10 当前最终冻结 build `1.0 (46)` 已按 iPhone-only archive 并上传 TestFlight；App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。
  - 完成标准：等待 build 46 processing 完成后，在 iOS 1.0 版本页选择并绑定该 build。
  - 额外风险：若版本页仍要求 iPad 截图，需确认 App Store Connect 已识别新上传的 iPhone-only build。

## 4. App 审核信息阻塞

- [ ] 审核登录信息未填写完整。
  - 当前发现：“需要登录”已勾选，但用户名、密码为空。
  - 完成标准：提供可供 Apple 审核使用的测试账号，且账号能进入主要功能。

- [ ] 审核联系人未填写完整。
  - 当前发现：联系人姓名、电话、邮箱为空。
  - 完成标准：填写真实可联系的审核联系人信息。

- [ ] 审核备注未填写。
  - 当前发现：备注为空。
  - 建议备注至少包含：
    - 登录测试账号
    - Together Pro 入口
    - 恢复购买入口
    - 账号注销路径：Profile -> 账号注销
    - 双人协作测试路径或说明
    - 订阅 / 终身权益均通过 App Store IAP 处理
  - 2026-05-04 本地处理：已在 `docs/superpowers/runbooks/2026-05-04-app-store-connect-submission-materials.md` 准备审核备注模板。

## 5. 订阅与 IAP 阻塞

- [ ] 月订阅元数据缺失。
  - ASC 当前产品 ID：`com.pigdog.together.monthly1m`
  - 当前状态：元数据丢失
  - 完成标准：产品本地化、价格、说明、审核所需元数据齐全，并可随 iOS 1.0 版本一并提交。
  - 2026-05-04 本地处理：已准备本地化名称、描述和审核备注草案，见 `2026-05-04-app-store-connect-submission-materials.md`。

- [ ] 年订阅元数据缺失。
  - ASC 当前产品 ID：`com.pigdog.together.yearly`
  - 当前状态：元数据丢失
  - 完成标准：产品本地化、价格、说明、审核所需元数据齐全，并可随 iOS 1.0 版本一并提交。
  - 2026-05-04 本地处理：已准备本地化名称、描述和审核备注草案，见 `2026-05-04-app-store-connect-submission-materials.md`。

- [ ] 终身权益元数据缺失。
  - ASC 当前产品 ID：`com.pigdog.together.lifetime`
  - 当前类型：非消耗型项目
  - 当前状态：元数据丢失
  - 完成标准：产品本地化、价格、说明、审核所需元数据齐全，并可随 iOS 1.0 版本一并提交。
  - 2026-05-04 本地处理：已准备本地化名称、描述和审核备注草案，见 `2026-05-04-app-store-connect-submission-materials.md`。

- [ ] 首次 IAP / 订阅需绑定到 App 版本页。
  - 当前 ASC 提示：首个 App 内购买项目 / 首个订阅必须随新的 App 版本提交。
  - 完成标准：在 iOS 1.0 版本页的“App 内购买项目”和“订阅”部分选择对应项目后再提交审核。

## 6. App 隐私标签阻塞

- [ ] App Store Connect 隐私标签与本地 `Together/PrivacyInfo.xcprivacy` 不完全一致。
  - 本地 manifest 当前声明：姓名、邮箱、用户 ID、照片或视频、其他用户内容、购买历史。
  - ASC 当前额外声明：设备 ID、产品交互、崩溃数据、性能数据、其他诊断数据。
  - 风险：隐私标签、manifest、真实 SDK 行为不一致会增加审核风险。
  - 完成标准：重新按真实 SDK / 后端 / 诊断能力核对后，统一 ASC 隐私标签与本地 Privacy Manifest。
  - 2026-05-04 本地处理：隐私政策和 App 内隐私摘要已与本地 manifest 对齐，不额外声明广告、行为分析、崩溃分析或诊断数据采集；ASC 隐私标签仍需人工保存为同一口径。

- [ ] 需要确认是否收集诊断和使用数据。
  - 如果 App / SDK 确实收集崩溃、性能、产品交互等数据，应补齐本地 manifest 与隐私政策说明。
  - 如果没有收集，应从 ASC 隐私标签删除对应项。

## 7. RevenueCat 配置

- [x] RevenueCat current offering 未引用历史旧 App Store 产品。
  - 当前旧产品包括：
    - `com.pigdog.together.monthly`
    - `com.pigdog.together.annual`
  - 当前有效产品还包括：
    - `com.pigdog.together.monthly1m`
    - `com.pigdog.together.yearly`
    - `com.pigdog.together.lifetime`
  - 完成标准：RevenueCat current offering 只引用当前 App Store Connect 中准备送审的产品。
  - 2026-05-10 Chrome 后台复核：current offering `default` 下 `$rc_monthly` 绑定 `com.pigdog.together.monthly1m`，`$rc_annual` 绑定 `com.pigdog.together.yearly`，`$rc_lifetime` 绑定 `com.pigdog.together.lifetime`；旧 App Store 产品仍在 products 列表中，但未被 current offering 使用。

- [x] RevenueCat 多余 entitlement 已清理。
  - 原发现：除 `pro` 外，还有 `Create an app called Together Pro`。
  - 完成标准：App 代码只使用 `pro`，RevenueCat offering / products 不错误绑定到多余 entitlement。
  - 2026-05-10 Chrome 后台处理：确认该多余 entitlement 只绑定 Test Store `monthly/yearly/lifetime` 后删除；RevenueCat MCP 复核当前只剩 active entitlement `lookup_key=pro`。

## 8. 已确认正常项

- [x] App Store Connect 已定位到正确 App：`一二：待办清单 提醒事项 双人协作`
- [x] App ID：`6763774768`
- [x] Bundle ID：`com.pigdog.Together`
- [x] 历史 TestFlight build：`1.0 (36)` 已上传；2026-05-10 当前最终冻结 build `1.0 (46)` 已上传并进入 processing
- [x] 隐私政策 URL 指向：`https://kb24123456.github.io/together-app-legal/privacy-policy/`
- [x] RevenueCat project 为 `Together`
- [x] RevenueCat entitlement `pro` 存在
- [x] RevenueCat current offering `default` 存在 monthly / yearly / lifetime 三个 package
- [x] RevenueCat current offering package-product 绑定已在 Chrome 后台确认：`monthly1m` / `yearly` / `lifetime`
- [x] RevenueCat 多余 entitlement `Create an app called Together Pro` 已删除
- [x] 仓库内可粘贴 ASC 材料已准备：`docs/superpowers/runbooks/2026-05-04-app-store-connect-submission-materials.md`
- [x] iPhone 6.9 截图上传包已生成：`/Users/papertiger/Desktop/宣传截图_ASC/iPhone-6.9/`

## 9. 当前本地代码冻结状态

- [x] “逾期任务移到今天”未提交新功能不纳入本次送审。
  - 2026-05-10 本地处理：已移除该功能的 Home UI、ViewModel 和测试改动；当前代码冻结只保留 iPhone-only 与送审文档/截图准备。
  - 完成标准：最终提交前确认 `Together/Features/Home/HomeView.swift`、`Together/Features/Home/HomeViewModel.swift`、`TogetherTests/TogetherTests.swift` 无该功能 diff。

- [x] Xcode destination 环境阻塞已解除，可 archive / upload。
  - 2026-05-10 已恢复：`xcodebuild -showdestinations` 可列出 Any iOS Device 与 iOS 26.4.1 simulators。
  - 验证结果：`git diff --check`、generic build、build-for-testing、Release archive 均通过。
  - 上传结果：`build/TestFlight-20260510-1027-build46/Together.xcarchive` 已通过 `build/exportOptions-TestFlight-upload.plist` 上传，App Store Connect 返回 `Upload succeeded` / `Uploaded package is processing`。

## 10. 复检顺序

1. 先完成本地代码和文案修改，重新 build / upload TestFlight。
2. 在 App Store Connect 版本页核对描述、截图、构建版本、审核信息。
3. 在 App Store Connect 订阅 / App 内购买项目页核对产品元数据状态。
4. 在 RevenueCat 核对 current offering、products、entitlement `pro`。
5. 在 App Store Connect App 隐私页核对隐私标签，并与 `Together/PrivacyInfo.xcprivacy` 对齐。
6. 最后运行 `2026-05-03-app-store-release-readiness.md` 的完整送审前清单。
7. 若本轮法律文档修订被采用，先同步 push 到 `together-app-legal` GitHub Pages 仓库，并确认线上 URL 显示 2026-05-04 版本。
