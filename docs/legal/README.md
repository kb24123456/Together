# Together 法律文件

本目录是法律文件的 source of truth；公开发布版同步在独立 repo
[github.com/kb24123456/together-app-legal](https://github.com/kb24123456/together-app-legal)
（GitHub Pages 部署），URL 已写入 `Together/Services/Premium/LegalURLs.swift`。

## 文件清单

| 文件 | 用途 | 状态 |
|---|---|---|
| `terms-of-service.md` | 服务条款 | ✅ 正式版（含 grace period § 3.4；2026-05-03 已部署）|
| `privacy-policy.md` | 隐私政策 | ✅ 正式版（2026-05-03 已部署）|

## 正式 URL

- **Privacy Policy**: https://kb24123456.github.io/together-app-legal/privacy-policy
- **Terms of Service**: https://kb24123456.github.io/together-app-legal/terms-of-service

> Phase 2（正式上架前）：升级到自定义域名 `together.app/legal/...`（Cloudflare Pages 接 GitHub repo 自动部署），仅需替换 `LegalURLs.swift` 一处。

## 同步到 App Store Connect

提审前还需要在 App Store Connect 后台：

1. **App 信息 → 隐私政策 URL** 填入 Privacy Policy URL
2. **App 信息 → 最终用户许可协议（EULA）** 可选择使用自定义 EULA（填入 Terms URL）或使用 Apple 默认 EULA
3. **App 隐私 → Privacy Nutrition Label** 按照隐私政策内容填写数据收集类别

## 维护流程

每次修订法律文件：

1. 改 `docs/legal/*.md`（main repo source of truth）
2. 更新文件末尾"生效日期" + "历史版本"
3. **同步 push 到 `together-app-legal` repo**（GitHub Pages 自动部署）
4. 考虑是否需要应用内通知用户"隐私政策已更新，请重新同意"

> ⚠️ 法律顾问复核：当前为开发者自审版本，正式商用前建议由律师复核一次（特别是
> § 八免责声明上限 / § 十法律适用条款是否符合中国大陆法律实践）。
