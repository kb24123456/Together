# App Store 上架前人工核对清单

本清单用于仓库内代码验证完成后，在 App Store Connect、RevenueCat、Supabase 和 TestFlight 真机上做最终人工核对。不做模拟器测试。

## 代码与构建冻结

- [ ] `main` 已包含本轮法律文案、权限、Privacy Manifest、订阅状态和赠权 runbook 修复。
- [ ] `git diff --check` 通过。
- [ ] `xcodebuild build -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过。
- [ ] `xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -quiet` 通过。
- [ ] TestFlight 安装的是本轮上传的新 build `1.0 (36)`；Profile 不显示 `开发者 (DEBUG)` 区域。

## App Store Connect

- [ ] 将 `docs/legal/privacy-policy.md` 与 `docs/legal/terms-of-service.md` 同步 push 到 `together-app-legal` GitHub Pages 仓库，并确认线上 URL 已显示 2026-05-04 版本。
- [ ] 使用 `docs/superpowers/runbooks/2026-05-04-app-store-connect-submission-materials.md` 更新 App 描述、关键词、宣传文本、IAP 元数据和审核备注。
- [ ] App 隐私标签与 `Together/PrivacyInfo.xcprivacy` 一致：姓名、邮箱、用户 ID、头像照片、用户内容、购买历史均用于 App 功能，不用于追踪。
- [ ] 隐私政策 URL 指向 `https://kb24123456.github.io/together-app-legal/privacy-policy/`。
- [ ] 使用条款 URL 指向 `https://kb24123456.github.io/together-app-legal/terms-of-service/`。
- [ ] Sign in with Apple 已配置并可用于正式登录。
- [ ] 账号注销路径可达：Profile → 账号注销。
- [ ] 订阅组、月订阅、年订阅、终身权益的产品 ID、价格、本地化、审核状态均正确。
- [ ] 自动续订订阅的价格、周期、续订说明、取消方式在 Paywall CTA 附近可见。
- [ ] 审核备注说明测试账号、订阅入口、恢复购买入口、账号注销入口和双人协作测试路径。

## RevenueCat

- [ ] Project 为 Together。
- [ ] App Store app、products、entitlement `pro`、offering/package 映射正确。
- [ ] Production / Sandbox API key 与 build 配置一致。
- [ ] Webhook integration 指向 Supabase `revenuecat-webhook`。
- [ ] Webhook Authorization 与 Supabase Edge Function secret 一致。

## Supabase

- [ ] `premium_entitlements` 可接收 RevenueCat webhook 并写入 active `pro` entitlement。
- [ ] `premium_grants` 仅 service role / Dashboard / 受控后台可写；用户只能读自己的有效授权。
- [ ] 个人跨设备同步的后端 gate 与 Pro / 免费 iPhone 恢复例外一致。
- [ ] Edge Functions 不依赖硬编码 secret；所有 secret 来自 Supabase secrets 或私有表。

## TestFlight 真机验收

- [ ] Free → 月订阅购买 → Apple 系统购买弹窗 → 购买成功 → App 显示 Pro。
- [ ] RevenueCat customer 出现 active `pro`。
- [ ] Supabase `premium_entitlements` 出现 active `pro`。
- [ ] 退出登录、杀 App、重新登录同一账号后仍显示 Pro。
- [ ] 恢复购买入口可用。
- [ ] 开发者赠权账号不购买也能显示 Pro；撤销赠权后降回 Free，除非仍有 active App Store entitlement。
- [ ] Profile / About / Paywall / SignIn 的隐私政策与使用条款入口均可打开。
