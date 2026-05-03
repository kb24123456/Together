# App Store 送审阻塞清单

本清单记录 2026-05-03 在 App Store Connect、RevenueCat 与本地仓库对照检查中发现的送审阻塞项。后续完成其他修改后，送审前应先对照本文件逐项复检，再回到 `2026-05-03-app-store-release-readiness.md` 做完整验收。

## 当前结论

当前不能直接提交 App Store 审核。核心阻塞集中在 App Store Connect 元数据、截图、构建绑定、审核信息、IAP / 订阅元数据、隐私标签与 RevenueCat 历史配置。

## 1. App Store 元数据阻塞

- [ ] App 描述中仍包含与当前架构冲突的旧表述。
  - 当前发现：描述里仍写有“数据存于你的 iCloud 私有库，归你所有”。
  - 风险：当前 App 已使用 Supabase / RevenueCat / Apple 平台服务，旧表述与法律文档和真实后端架构冲突。
  - 完成标准：App Store 描述与 `docs/legal/privacy-policy.md`、`docs/legal/terms-of-service.md`、当前代码架构一致。

- [ ] Pro 功能文案需要和真实已上线功能对齐。
  - 当前发现：描述里提到“自定义主题与 App 图标”“优先客服支持”。
  - 风险：如果这些功能当前 build 未真实提供，审核和用户预期都会受影响。
  - 完成标准：App Store 描述、Paywall 文案、Profile 会员页和真实功能完全一致。

## 2. 截图与版本素材阻塞

- [ ] App Store 版本页未上传 iPhone 截图。
  - 当前发现：iPhone 截图显示 `0/10`。
  - 风险：首次送审必须提供截图。
  - 完成标准：至少上传符合 App Store Connect 尺寸要求的 iPhone 截图，并确认截图反映最新 Release/TestFlight UI。

## 3. 构建版本绑定阻塞

- [ ] 最新 TestFlight build 未绑定到 iOS 1.0 待提交版本。
  - 当前发现：版本页仍显示“添加构建版本”。
  - 已确认：TestFlight 最新 build 为 `1.0 (35)`，状态完成，正在内部测试。
  - 完成标准：iOS 1.0 版本页选择并绑定本轮冻结后的最新 build。

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

## 5. 订阅与 IAP 阻塞

- [ ] 月订阅元数据缺失。
  - ASC 当前产品 ID：`com.pigdog.together.monthly1m`
  - 当前状态：元数据丢失
  - 完成标准：产品本地化、价格、说明、审核所需元数据齐全，并可随 iOS 1.0 版本一并提交。

- [ ] 年订阅元数据缺失。
  - ASC 当前产品 ID：`com.pigdog.together.yearly`
  - 当前状态：元数据丢失
  - 完成标准：产品本地化、价格、说明、审核所需元数据齐全，并可随 iOS 1.0 版本一并提交。

- [ ] 终身权益元数据缺失。
  - ASC 当前产品 ID：`com.pigdog.together.lifetime`
  - 当前类型：非消耗型项目
  - 当前状态：元数据丢失
  - 完成标准：产品本地化、价格、说明、审核所需元数据齐全，并可随 iOS 1.0 版本一并提交。

- [ ] 首次 IAP / 订阅需绑定到 App 版本页。
  - 当前 ASC 提示：首个 App 内购买项目 / 首个订阅必须随新的 App 版本提交。
  - 完成标准：在 iOS 1.0 版本页的“App 内购买项目”和“订阅”部分选择对应项目后再提交审核。

## 6. App 隐私标签阻塞

- [ ] App Store Connect 隐私标签与本地 `Together/PrivacyInfo.xcprivacy` 不完全一致。
  - 本地 manifest 当前声明：姓名、邮箱、用户 ID、照片或视频、其他用户内容、购买历史。
  - ASC 当前额外声明：设备 ID、产品交互、崩溃数据、性能数据、其他诊断数据。
  - 风险：隐私标签、manifest、真实 SDK 行为不一致会增加审核风险。
  - 完成标准：重新按真实 SDK / 后端 / 诊断能力核对后，统一 ASC 隐私标签与本地 Privacy Manifest。

- [ ] 需要确认是否收集诊断和使用数据。
  - 如果 App / SDK 确实收集崩溃、性能、产品交互等数据，应补齐本地 manifest 与隐私政策说明。
  - 如果没有收集，应从 ASC 隐私标签删除对应项。

## 7. RevenueCat 配置风险

- [ ] RevenueCat 存在历史旧产品，需要确认是否仍被引用。
  - 当前旧产品包括：
    - `com.pigdog.together.monthly`
    - `com.pigdog.together.annual`
  - 当前有效产品还包括：
    - `com.pigdog.together.monthly1m`
    - `com.pigdog.together.yearly`
    - `com.pigdog.together.lifetime`
  - 完成标准：RevenueCat current offering 只引用当前 App Store Connect 中准备送审的产品。

- [ ] RevenueCat 存在多余 entitlement，需要清理或确认无引用。
  - 当前发现：除 `pro` 外，还有 `Create an app called Together Pro`。
  - 完成标准：App 代码只使用 `pro`，RevenueCat offering / products 不错误绑定到多余 entitlement。

## 8. 已确认正常项

- [x] App Store Connect 已定位到正确 App：`一二：待办清单 提醒事项 双人协作`
- [x] App ID：`6763774768`
- [x] Bundle ID：`com.pigdog.Together`
- [x] TestFlight 最新 build：`1.0 (35)`，状态完成
- [x] 隐私政策 URL 指向：`https://kb24123456.github.io/together-app-legal/privacy-policy/`
- [x] RevenueCat project 为 `Together`
- [x] RevenueCat entitlement `pro` 存在
- [x] RevenueCat current offering `default` 存在 monthly / yearly / lifetime 三个 package

## 9. 复检顺序

1. 先完成本地代码和文案修改，重新 build / upload TestFlight。
2. 在 App Store Connect 版本页核对描述、截图、构建版本、审核信息。
3. 在 App Store Connect 订阅 / App 内购买项目页核对产品元数据状态。
4. 在 RevenueCat 核对 current offering、products、entitlement `pro`。
5. 在 App Store Connect App 隐私页核对隐私标签，并与 `Together/PrivacyInfo.xcprivacy` 对齐。
6. 最后运行 `2026-05-03-app-store-release-readiness.md` 的完整送审前清单。
