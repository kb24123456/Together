# App Store Connect 送审材料草案

本文件用于把仓库内已确认的产品、隐私和订阅事实整理成 App Store Connect 可粘贴材料。后台保存前仍需人工核对价格、截图、测试账号和 IAP 状态。

## App 描述

一二是一款专注 Today、清单、项目和日历的待办效率应用。它帮助你把临时事项快速收集起来，整理到清单和项目中，并在每天打开应用时看清今天应该先做什么。

你可以用它管理个人任务、项目推进、例行事项、纪念日和提醒。应用保留克制、清晰的 iOS 原生体验，适合高频记录、整理、完成和回看。

如果你需要和另一位协作者一起处理生活或任务安排，也可以自愿启用双人模式。双人模式支持共享任务、留言、提醒对方接受任务，以及配对空间内的数据同步；不使用双人模式时，个人待办主链路依然完整可用。

Together Pro 可解锁更多能力，包括跨设备同步、更多项目与纪念日额度、全量 Logbook 历史，以及后续持续扩展的 Pro 功能。所有订阅和终身权益均通过 App Store 内购处理，可在 Apple ID 订阅设置中管理或取消。

## 关键词

待办,任务,清单,项目,日历,提醒,例行事项,纪念日,协作,效率

## 宣传文本

把今天要做的事、长期项目和重要日子放在一个清晰的 iOS 待办应用里。

## IAP 元数据

### 月订阅

- Product ID: `com.pigdog.together.monthly1m`
- 参考显示名称：Together Pro 月度会员
- 参考描述：解锁 Together Pro：跨设备同步、更多项目与纪念日额度、全量 Logbook 历史。按月自动续订，可随时在 Apple ID 订阅设置中管理或取消。
- 审核备注：自动续订订阅。购买入口位于 Profile -> Together Pro；恢复购买入口位于 Paywall 底部。

### 年订阅

- Product ID: `com.pigdog.together.yearly`
- 参考显示名称：Together Pro 年度会员
- 参考描述：解锁 Together Pro：跨设备同步、更多项目与纪念日额度、全量 Logbook 历史。按年自动续订；如 App Store Connect 配置了免费试用，以 App Store 显示为准。可在 Apple ID 订阅设置中管理或取消。
- 审核备注：自动续订订阅。购买入口位于 Profile -> Together Pro；恢复购买入口位于 Paywall 底部。

### 终身权益

- Product ID: `com.pigdog.together.lifetime`
- 参考显示名称：Together Pro 终身权益
- 参考描述：一次性购买 Together Pro 终身权益，解锁跨设备同步、更多项目与纪念日额度、全量 Logbook 历史及后续持续扩展的 Pro 功能。该项目不是订阅，不会自动续费。
- 审核备注：非消耗型 App 内购买项目。购买入口位于 Profile -> Together Pro；恢复购买入口位于 Paywall 底部。

## 审核备注模板

需要登录：是

测试账号：
- Apple Sign In 测试账号：`[填写 Apple 审核可用账号或测试说明]`
- 测试账号密码：`[如适用填写；Sign in with Apple 通常可说明使用审核员 Apple ID 登录]`

主要功能路径：
- 任务创建：底部创建按钮 -> 输入任务 -> 保存。
- 清单 / 项目 / 日历：底部 toolbar 切换对应页面。
- Together Pro 入口：Profile -> Together Pro。
- 恢复购买入口：Profile -> Together Pro -> Paywall 底部“恢复购买”。
- 账号注销入口：Profile -> 账号注销。
- 隐私政策 / 使用条款：SignIn、Profile、About、Paywall 中均提供入口。
- 双人协作测试：Profile 中进入双人模式 / 配对入口，创建或接受配对后可创建共享任务、留言，并在待接受双人任务上使用“提醒”。

订阅说明：
- 月订阅、年订阅和终身权益均通过 App Store IAP 处理。
- 自动续订订阅可在 Apple ID 订阅设置中管理或取消。
- 开发者赠权仅用于早期用户、TestFlight、开发者支持或问题补偿，不作为 App 外部销售、公开兑换码或绕过 App Store 内购的付费渠道。

后台依赖：
- 账号、同步和配对使用 Supabase。
- 订阅状态同步使用 RevenueCat。
- 支付由 Apple App Store 处理。

## App 隐私标签填写口径

本地 `Together/PrivacyInfo.xcprivacy` 当前声明的数据类型：

- Name：用于 App Functionality，Linked to User，Not Tracking。
- Email Address：用于 App Functionality，Linked to User，Not Tracking。
- User ID：用于 App Functionality，Linked to User，Not Tracking。
- Photos or Videos：用于 App Functionality，Linked to User，Not Tracking。仅用户主动选择或拍摄头像时使用。
- Other User Content：用于 App Functionality，Linked to User，Not Tracking。包括任务、清单、项目、纪念日、备注、留言等用户内容。
- Purchase History：用于 App Functionality，Linked to User，Not Tracking。RevenueCat 官方文档要求使用 RevenueCat 时在 App Store Connect 披露 Purchases / Purchase History。

送审前需要在 App Store Connect App Privacy 页面核对：

- 不要选择 Tracking。
- 不要额外选择 Device ID、Product Interaction、Crash Data、Performance Data、Other Diagnostic Data，除非后续确实新增了对应采集或 SDK。
- 如果 App Store Connect 当前仍保留这些额外项，应删除，或同步补齐本地 Privacy Manifest、隐私政策和 App 内文案。

参考：RevenueCat Apple App Privacy 文档 `https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy`。

## 仍需人工后台完成

- 在 App Store Connect 保存 App 描述、关键词、宣传文本和审核备注。
- 上传 `/Users/papertiger/Desktop/宣传截图_ASC/iPhone-6.9-safe/` 中已整理的 iPhone 6.9 截图。
- 本地 target 已改为 iPhone-only；build 46 已重新上传 TestFlight，processing 完成后在 App Store Connect 确认版本页不再要求 iPad 截图。
- 等 build 46 processing 完成后绑定到 iOS 1.0 版本页。
- 补齐三个 IAP / 订阅项目的本地化、价格、说明、审核元数据，并随 iOS 1.0 一起提交。
- RevenueCat 后台已确认 current offering 三个 package 只绑定 `monthly1m`、`yearly`、`lifetime`，不引用历史 App Store 产品。
- RevenueCat 多余 entitlement `Create an app called Together Pro` 已删除；当前只保留 `pro`。
