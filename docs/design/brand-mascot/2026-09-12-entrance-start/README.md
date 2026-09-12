# 首页进入编辑的直跳修复

用户最新反馈：首页日常小球动作正常，编辑返回首页能看到轨迹，只有首页进入编辑直接跳动。用户撤销“抵达后才拿笔”的顺序，目标为明确感知同一个小球连续变化。

## 定位与实现

Mac Catalyst 隔离复现使用生产的 SwiftUI toolbar 锚点、Session、导航观察与转场源码，运行 `NavigationStack → fullScreenCover + .zoom`，仅将 Rive 绘制替换为一个蓝色 UIView。旧实现记录 `duration=0.4`、`motionAllowed=true`、`visible=true`，但启动时 `UIView.areAnimationsEnabled=false`；没有采到入场中间位置。最终实现启动时为 true，采到 5 个不同的中间位置，整个流程仅有一个 artwork 身份。

这定位到了与用户现象一致的启动问题：SwiftUI 原生布局临时关闭 UIKit 动画，属性动画在该事务里创建并启动，位置直接生效。Apple 对 [禁用 UIView 动画时立即应用修改](https://developer.apple.com/documentation/uikit/uiview/setanimationsenabled%28_%3A%29?changes=l__2_4_1) 的说明与实测一致。此为隔离环境证据，尚无 iPhone 上的同源诊断日志。

- `MascotVisualTransfer` 检查当前动画上下文，必要时合并安排到主队列，退出禁动画事务后重新读取几何并启动。仍是一条无回弹属性动画；没有人为延时，也没有替换原生 Zoom。
- 排队启动由本次转场 UUID 保护，反向、关闭或重入后，旧启动不能生效。Reduce Motion 等既有降级直接落位。
- `MascotPlaybackSession` 在进入编辑时切入现有拿笔姿态，输入立即驱动书写；实际停靠只更新归属。返回 coordinator 路径保持原样。
- 最终实现沿用原窗口内的非交互 UIView，不新增 UIWindow；没有改 Rive 文件、造型、导航落点或保存取消语义。

## 验证

详见 [verification.json](verification.json)。51 项纯所有权、几何和行为测试执行通过。10 项 UIKit 测试仅编译，其中新增“禁动画布局不得立即移动到终点，排队入场可被返回取代”回归，更新了立即进入编辑姿态与迟到锚点用例。

Xcode 27 beta 3 的 generic iOS 无签名 `build-for-testing` 成功，包含本次源码和测试。现有非本次范围的 actor isolation、弃用与 switch 警告仍存在。未启动 Simulator，未安装或运行 Together 真机，未做性能能耗测量。隔离实验的主队列坐标采样可证明中间位置与实例身份，不能代表 iPhone 的逐帧画面、Rive 质量或手势验收。

```sh
DEVELOPER_DIR='/Users/papertiger/Downloads/Xcode-beta 3.app/Contents/Developer' xcodebuild build-for-testing -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -derivedDataPath /Users/papertiger/Library/Developer/Xcode/DerivedData/Together-djoefdjmosrqzacyvdvtuajwfgik -clonedSourcePackagesDirPath /Users/papertiger/Library/Developer/Xcode/DerivedData/Together-djoefdjmosrqzacyvdvtuajwfgik/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
```

## 真机复验

重新用 Xcode Run 当前根目录工程到 iPhone，再分别进入“新建”和已有任务详情。关注首页右上角的小球能否连续移动、缩小并自然拿笔；检查返回仍连续。再检查快速打开后返回、手势返回取消、移动途中输入、Reduce Motion 及后台恢复。无需先修改任务才能触发跨页移动。

## Retrieval Evidence

Query：`SwiftUI layout disables UIView animations UIViewPropertyAnimator starts inside performWithoutAnimation jumps to final position defer startup main queue areAnimationsEnabled`。命中 keys：无；实际采用记录：无；无需 Expert Delta。前期窗口层调查 query 为 `UIKit UIWindow overlay above fullScreenCover modal transition container z order passthrough non key window scene coordinate conversion shared view continuity`，同样无有效命中；最终未采用额外窗口。
