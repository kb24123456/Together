# 定稿小球接入 App

2026-09-09，用户确认加宽写字眼型后，已将定稿资源接入现有 App。

- 动画：[App 内 `.riv`](/Users/papertiger/Desktop/Together/Together/Resources/BrandMascot/together_sphere_motion_study.riv)，3,848,190 bytes，SHA-256 `dcff4246a01a85142f605b33238437ad239422e8fb8d5916e0d34b27102223c3`。
- 静态降级：`MascotHolding.imageset` 的浅／深色持笔 PNG 同步为同一资产的实际运行库渲染，512×512 透明背景；保留原文件名和主题匹配。
- 备份：[接入前资源](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/app-integration/backups)，包含旧 `.riv` 和两张持笔图；`before.json` 记录哈希及相关生产代码快照哈希。

沿用 `TogetherSphere / Mascot / TogetherSphereModel` 与既有业务控制。首页、创建、编辑页加载同一个新版文件，布局与取消／保存语义不变。128 条时间轴、24 个模型属性已随资产打包；新表情层默认 `expression=0`，保留原行为，不自行增加 28 种表情与 4 种轻动作的业务触发。

## 验证

- 官方 Rive Runtime 6.25.1：57/57 资产与接口检查、90/90 反馈打断检查通过。已实际进入待机、写字、持笔、流汗、思考、打盹；单眨眼与庆祝可用，12 色与 App 调色板一致。
- 两主题持笔图经过实际渲染与目视检查，透明边界均为 `(72,56)–(440,479)`，保持原画板占位。
- Xcode 27 beta 3，通用 iOS 无签名 `build-for-testing` 成功；资产目录重新编译，构建包内 `.riv` 与定稿字节及哈希一致。相关 19 个生产 Swift 文件与接入前一致。
- 仍有既有 `ProfileViewModel.swift:44` 主执行器隔离警告，本轮未改该文件。

具体证据见 [verification.json](/Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-expression-system/app-integration/verification.json)、`asset-verification.json` 和 `feedback-verification.json`。

iOS 测试仅编译未执行；未启动 Simulator、签名安装或验收真机。需从当前工程重新运行并安装到 iPhone，检查实际输入／停笔、浅深色及“减弱动态效果”的静态持笔姿势。此前手机中的已安装版本不会因本地资源替换而自动更新。
