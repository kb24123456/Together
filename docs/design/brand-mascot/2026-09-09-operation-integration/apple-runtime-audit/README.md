# Apple runtime 资产验收

2026-09-09，使用官方 `rive-ios 6.25.1`（2026-09-02 稳定版）在独立 macOS 命令行中读取已导出的 `.riv`。47 项检查通过，详见 `verification.json`。未创建视图、启动 Simulator、修改 App/Xcode 工程或改写 Rive 资产。

- 文件仅导出 `TogetherSphere`，包含 30 条时间轴，默认状态机为 `Mascot`。
- `TogetherSphereModel` 的 17 个属性完整；5 种持续 mode（书写/持笔各一例）均进入对应动画。
- `acknowledge` 播放 `Expression_Wink` 后回到 Idle；`celebrateRequested` 播放庆祝后清零。
- 12 个语义颜色分别写入深浅主题后读回一致，保留同一个绑定实例及书写 mode。

使用同一官方包内的 Legacy 对象 API，是因为它同时公开线性动画列表和逐帧状态变化，适合此次无界面资产检查。`stateChanges()` 对动画状态返回引用的动画名，而非编辑器节点名；例如 `Acknowledge` 对应 `Expression_Wink`。实际 App 集成仍应独立选择并验证运行时视图接口。

本轮未渲染像素，颜色属性往返不等同于对最终画面颜色的独立验证；也不覆盖 iOS 真机、布局、性能或商业发布授权。

## 复验

将本目录的 `Package.swift`、`Package.resolved` 和 `Sources` 复制到一个新建的 `/private/tmp` 目录。在该临时目录运行以下命令，依赖和构建结果会留在临时目录中：

```sh
swift run TogetherRiveAssetAudit \
  /Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-09-operation-integration/runtime-source/together_sphere_motion_study.riv \
  /Users/papertiger/Desktop/Together/docs/design/brand-mascot/2026-09-08-rive-study/expression-integration/theme-integrated.json \
  ./verification.json
```

使用同一规范化路径，不在同一构建中混用 `/tmp` 和 `/private/tmp`。本次曾因二者混用触发 `_DarwinFoundation1` 重复模块缓存错误，统一路径并仅重建本任务模块缓存后通过，未更换 SDK。

来源、资产 SHA-256、工具链、全部轨迹和检查结果均记录于 `verification.json`。Apple Knowledge Runtime 检索结果为“无需 Expert Delta”。

## App 接入增量验证

实际 App 采用 New Runtime。`verify-app-runtime.py` 对五个精确生产文件执行官方 6.25.1 API 类型检查，结果 `new-runtime-api-verification.json` 为零诊断；另由 `feedback-interruption-audit.swift` 使用同包 inspection API 观察状态轨迹，90/90 组暂停/恢复通过，见 `feedback-interruption-verification.json`。轨迹检查与 New Runtime API 编译是两项独立证据，不代表像素或真机表现。

复验脚本在临时目录产生并清理二进制与模块缓存，显式配对编译器和 SDK；调用方式见脚本 `--help`。完整 App 已额外在 Xcode 27 beta 3 下通过通用 iOS 无签名 `build-for-testing`，资源已打包，详见上级 [接入结果](../README.md) 与 [验证记录](../app-integration-verification.json)。此增量取代前文资产验收阶段的“未修改 App”状态，iOS 测试执行和真机验收仍待完成。
