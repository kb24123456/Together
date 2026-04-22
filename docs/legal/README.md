# Together 法律文件

本目录存放正式发布前需要托管到公开 URL 的法律文件草案。

## 文件清单

| 文件 | 用途 | 状态 |
|---|---|---|
| `terms-of-service.md` | 服务条款 | 🟡 草案（待补联系方式、法律顾问复核） |
| `privacy-policy.md` | 隐私政策 | 🟡 草案（待补联系方式、Supabase region、法律顾问复核） |

## 正式发布前必做

- [ ] 补全两份文件中所有 `[待填写]` 占位符
- [ ] 请律师或法律顾问对完整内容复核
- [ ] 确认 Supabase 数据中心 region（更新隐私政策 § 2.2）
- [ ] 选择托管方案并生成可访问 URL：
  - 自建域名子页面（最专业）
  - GitHub Pages（免费、Apple 接受，建议路径 `legal.together-app.com` 或类似）
  - Notion 公开页（最简单但不够正式）
- [ ] 将最终 URL 记录到：
  - 本 README 下方
  - 项目 `CLAUDE.md` 或 `README.md`
  - Phase 3 付费墙 UI 的 SwiftUI 代码中（作为常量）

## 正式托管 URL（填入后即生效）

- **Terms of Service**: `https://<待填写>`
- **Privacy Policy**: `https://<待填写>`

## 同步到 App Store Connect

正式 URL 确定后，还需要在 App Store Connect 后台：

1. **App 信息 → 隐私政策 URL** 填入 Privacy Policy URL
2. **App 信息 → 最终用户许可协议（EULA）** 可选择使用自定义 EULA（填入 Terms URL）或使用 Apple 默认 EULA
3. **App 隐私 → Privacy Nutrition Label** 按照隐私政策内容填写数据收集类别

## 维护

每次修订这两份文件：

1. 在文件末尾"历史版本"章节追加版本号与修订说明
2. 更新"生效日期"
3. 重新生成 / 同步托管 URL 的内容
4. 考虑是否需要应用内通知用户"隐私政策已更新，请重新同意"
