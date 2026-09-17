# 时间 Sheet 同心布局与中央球面放大

2026-09-18 当前实现位于 `Together/Features/Shared/TaskTimePickerSheet.swift`。

## 当前球面放大（2026-09-18，真机待验收）

用户纠正后确认：中央一小片刻度整体放大，像贴在向外鼓起的球面上。本轮取代仅上下位移的波峰，保持 Sheet 底色。

- `TaskTimeRulerLens` 的放大从中央 1.24 倍，以升余弦曲线在两侧各 50pt 内平滑恢复到 1；对齐时 9 根刻线参与渐变，中央几根更明显。边界及峰顶斜率为零。
- 基础刻线仍为 3×34pt、中心距 10pt；中央刻线围绕自身中心等比放大到约 3.72×42.16pt，同时中心的横向投影为 `distance × scale`，邻线间距协调展开。所有刻线的水平中线保持不动，没有竖直平移。
- `TaskTimeRulerMark.visualEffect` 直接按实际滚动位置连续计算缩放与水平偏移，不写入逐帧 State，不改变滚动目标布局、5 分钟吸附或日期语义。顶部时间数字、指针及底部读数布局保持稳定。
- tracking / interacting 启用形变，按下约 160ms 放大、松手约 240ms 恢复；惯性阶段不持续放大。没有新增手势、位移采样状态或私有滚动结构。
- 逐根提亮保持最多 18% 白色覆盖、100/160/440ms 的升亮/回落/衰减时序；底线持续保留，不使用描边或光晕。释放停止新光，清除、系统滚轮、程序定位和失活继续重置光层。
- Reduce Motion 取消球面放大和瞬态提亮，增强对比度取消提亮，Reduce Transparency 取消边缘柔化。

Apple [VisualEffect](https://developer.apple.com/documentation/swiftui/visualeffect) 用于改变外观而不影响布局；[ScrollPhase.tracking](https://developer.apple.com/documentation/swiftui/scrollphase/tracking) 对应触摸但尚未滚动，[decelerating](https://developer.apple.com/documentation/swiftui/scrollphase/decelerating) 对应交互停止后的减速。这是自定义凸透镜式形变，不称为原生 Liquid Glass，也不绑定未采集的手指坐标。

## 保留的布局与交互

- 静止基础刻线继续使用 AppTheme.title 与连续位置明暗；常规对比度下不透明度范围由 0.24–0.72 提高为 0.34–0.86，增加刻线可见度，保留边缘渐隐；原生 numericText 滚动保持不变。高光单独由触摸阶段和刻线穿越中心驱动，不改变时间业务语义。
- 外缘 inset 统一取 `max(24, bottomSafeArea)`；内容底部只补足不足的部分，系统底部安全区不重复计入。Sheet 高度由完整内容实测，内容不侵入安全区。
- 清除按钮使用系统 `ConcentricRectangle`。大时间不加底框：以同一 Rounded 等宽数字字体的稳定 `00:00` CoreText 字形边界移除字体空白，保留原生 Text，按可见底边对齐，再用 `containerCornerOffset` 避让左下角；日期与时间共用左轴。数字变化不按当前字形反复改宽度；极大字号先按可用宽度整体适配，再测量字形边界，避免截断时间。额外以 320pt 宽、140pt 请求字号做离线压力绘制，完整时间保持可见；这不是实际 iOS Dynamic Type 验收。
- 指针下的选值改为各节点在命名视窗中的真实位置。初始居中留白进入刻度内容 padding，在首次目标布局时即存在。

## 初始定位回归

原 `.contentMargins` 实现已在 macOS 原生 SwiftUI 隔离窗口复现：请求 index 183（15:15），初始实际居中 index 175（14:35）。首次定位时 content inset 为 0，后续变为 158pt，位置偏移 8 格。这与用户截图约 40 分钟偏差相符；这是共享框架隔离证据，不是 iPhone 实测。

改为内容 padding 后，初始 183、00:00 的 0、23:55 的 287、中间 135，以及宽度从 384pt 缩到 320pt 后的 135，共 5 次居中断言通过。缩放过程允许系统重新布局，断言检查稳定后的中心。脚本 `verify-native-ruler.swift` 可用 `swift docs/design/time-picker/verify-native-ruler.swift` 复跑，会短暂显示约 5 秒的原生 macOS 检查窗口，然后自动关闭；不启动 iOS Simulator。

## 本轮验证范围

- macOS 临时 Swift Package 运行当前生产组件相关测试，共 16 项通过：2 项球面放大测试覆盖有界/对称/单峰、边缘连续、投影顺序及相邻刻线始终不重叠；7 项原受光状态、7 项时间语义继续通过。
- macOS 原生 SwiftUI 隔离窗口复用生产组件的只读日志副本，通过正反向逐根接续、释放停止新光及实际 keyframeAnimator 的峰值/插值/回零检查。
- 实际 NSHostingView 的 2× 捕获验证：中央刻线从约 68px 增至 84px 高，宽度与相邻中心距同步增加；所有刻线的垂直中心保持不动，中心刻线无新增偏移，刻线之间没有重叠。顶部标签及下方指针在静止/按下捕获中逐像素相同。释放后恢复原刻线尺寸与间距。
- `ruler-lens-native-pressed.png` 是本轮生产组件的 macOS 隔离绘制，不是 iPhone 截图或完整 Sheet；合成接触与程序滚动不代表真实手感验收。
- Xcode27 beta3 generic iOS 无签名 `build-for-testing` 通过，只有既有 ProfileViewModel 和测试文件警告；diff / 空白检查通过。日志位于 `/tmp/together-time-ruler-lens/`。

## 历史绘制与验证

此前 3.5pt 上下平移波峰和强白光均为历史方案，不代表当前球面形变；`ruler-wave-native-crest.png` 仅保留历史对照。以下为先前白光验证记录。

刻线加深后，当前组件 Swift 6 编译、深浅色静态绘制、diff 检查及 generic iOS 无签名 build 通过，未新增警告；日志 `/tmp/together-time-ruler-darker/build.log`。只调整基础不透明度，未重复动画 / 业务测试；真机观感待验收。

本次细节微调：线宽 2.6→3pt，总时长 580→700ms，移除灰色轮廓和暗色阴影，并让深色底线同步淡出。状态与手势逻辑不变，未重复业务单测或新增测试。Swift 6 模式下当前绘制组件编译无诊断；隔离动画检查通过正反向接续、释放停止新光、峰值 / 插值 / 回零。Xcode27 beta3 generic iOS 无签名 App build 通过，本次文件无新警告；日志 `/tmp/together-time-ruler-light-refinement/`。后面的 14 项测试属于上一版基线，不代表本轮重新运行。

历史 `ruler-contact-light-states.png` 使用当时的生产 `TaskTimeRulerLightStroke` 在 macOS ImageRenderer 中绘制浅色 / 深色的静止、半亮、峰值，用于检查整线受光与静止线宽。它不是 iPhone 截图，不证明按压或拖动手感。旧三张 Sheet / 高光图保留为历史阶段，不能作为当前光色依据。

- 7 项 `TaskTimeRulerLightTests` 实际通过：无接触定位不亮、按下未移动即亮、两根刻线独立余光与反向、快速跨过中心、松手后的惯性阶段不触发、懒加载不误闪、中心区域边界不重叠。临时 macOS Swift Package 直接使用生产光层文件，同时既有 7 项时间语义测试通过，共 14 项。
- macOS 原生 SwiftUI 隔离窗口按生产组件附加只读日志，使用合成接触状态与程序位移，验证初始几何（含 offset 的中间分割线）、只点亮中央一根、连续正向序列 100→101→102→103→104、反向 103→102→101→100，以及释放后继续位移不触发新光；对五根实际 keyframeAnimator 的逐帧值采样，也确认达到白光峰值、经过中间亮度并最终衰减为零。它验证共享框架的几何、动画执行和身份衔接，不验证 iPhone 的真实触摸阶段或流畅度。
- Swift parse、diff 检查与 Xcode27 beta3 generic iOS 无签名 build-for-testing 通过。首次测试目标编译因新测试缺 Foundation import 失败，补齐后通过；主 App 没有新的编译警告，仍有既有 ProfileViewModel 及测试文件警告。日志位于 `/tmp/together-time-ruler-contact-light/`（`tests-final.log`、`geometry-final.log`、`build-final.log`）。

未启动 iOS Simulator、未安装或运行 Together iOS App。真机需 Xcode Run 包含本次源码的新构建，检查：按下未拖动的整体球面放大、松手平滑恢复、持续慢拖、快速反向、甩动松手后衰减、惯性中再次按下、清除 / 打开系统滚轮中断、首次打开与首尾端点、深浅色、Reduce Motion / Reduce Transparency / 增强对比度。保留的底部布局与原生数字滚动也应随本轮顺带确认。编译与隔离检查不代表真机视觉或帧率验收通过。

## Apple Retrieval Evidence

- 本轮 Query: `SwiftUI visualEffect scaleEffect offset continuous scroll fisheye magnification preserve layout scroll target geometry selection`
- 命中 keys：无；采用记录：无；无需 Expert Delta。采用当前 SDK 的 visualEffect / scaleEffect / offset，未新增图形依赖。

此前竖直波峰检索：

- 本轮 Query: `SwiftUI visualEffect offset continuous scroll geometry local wave crest animation value layout unchanged`
- 命中 keys：无；采用记录：无；无需 Expert Delta。依据上述 Apple 官方 VisualEffect 文档和当前 SDK，采用仅改变外观的位移。

此前受光检索：

- Query: `SwiftUI ScrollView onScrollPhaseChange tracking interacting decelerating touch down per-item keyframe animation highlight`
- 命中 keys：无；采用记录：无；无需 Expert Delta。接触阶段语义按上述 Apple 官方文档及当前 SDK 核对。

此前布局检索：

- Query: `SwiftUI ScrollGeometry contentMargins contentInsets horizontal centered ruler selected index offset mismatch sheet safe area concentric corners optical text bounds`
- 命中 keys：无；采用记录：无；无需 Expert Delta。
- 官方依据：[ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle)、[containerCornerOffset](https://developer.apple.com/documentation/swiftui/view/containercorneroffset(_:sizetofit:))、[CoordinateSpaceProtocol](https://developer.apple.com/documentation/swiftui/coordinatespaceprotocol)、[numericText(value:)](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:))。
