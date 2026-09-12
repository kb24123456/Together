# 任务修改：左侧表情的原高度胶囊

用户最终选择左侧表情，并授权正式接入。首页小球在自身原高度横向展开为等高胶囊，宽度随单行结果自适应、最终屏幕水平居中；收回沿相同几何过程反向返回。该实现取代底部任务修改提示。

## 实现

- `AppRootView` 将原有修改反馈交给 `MascotPlaybackSession`，移除底部重复提示与旧的改期左下注视调用。覆盖范围及成功保存才反馈的语义沿用既有 `TaskUpdateFeedback`。
- `MascotVisualTransfer` 复用原window非交互承接层，将唯一 `MascotArtworkView` 临时放入原生 `TaskUpdateNotice` 左端，再整体展开和居中。Rive与静态资源未改，表情、眼睛和文字不横向缩放；胶囊渐变使用角色现有两主题主体配色。未新增角色实例或窗口，未更改原生导航/编辑所有权。
- 位置由真实原生锚点画板的球体边界计算，原高度与直径保持不变；最大宽度以窗口左右至少28pt或更大的安全边距限制。顶部模式标题保留原布局、淡出并禁用交互/无障碍焦点；个人页入口在小球展开期间禁用，复位后恢复。
- `MascotNoticeState` 用事件UUID管理替换、取消和迟到结束；UIView动画另有完成代次保护。正常展开与收回各320ms，展开完成后阅读2.6秒；VoiceOver公告完整任务名及结果、停留5秒。连续结果在现有胶囊上更新并重置阅读计时，不先收回再重新展开。
- 若详情原生返回仍在完成，最新结果等待小球实际停靠首页再展开。开始导航、后台、锁定、窗口隐藏、首页锚点消失或位置变化时立即取消，不回前台补播。Reduce Motion和现有系统禁播状态取消空间运动。禁动画的SwiftUI布局事务结束后才启动属性动画。
- 一行15pt基准结果字体随Dynamic Type增长至24pt上限，以满足原球40pt高度；长结果截断，完整文字保留在无障碍标签和公告。这是等高限制下的明确取舍，真机需检查各字号的可读性。

## 验证

- 17项离线测试运行通过：原有13项真实任务反馈分类/文案测试，以及4项新增结果替换、取消、原高度/居中与横屏安全边距测试。
- 新增4项UIKit测试覆盖唯一角色左端承载/回归原槽、连续替换与导航取消、隐藏后不补播、等待原生返回；包含在测试目标构建中，尚未在iOS设备执行。
- 全部App源码在iPhoneOS SDK下模块编译通过；Xcode 27 beta3的完整无签名 `build-for-testing` 通过，包含本次App与测试源文件。`git diff --check`通过。
- 系统默认Xcode26.6因iOS26.5平台未安装而无法找到generic iOS目的地；改用本机已存在的Xcode27完成验证，未修改全局Xcode选择或安装平台。
- 没有启动Simulator、安装/运行手机或执行原生逐帧视觉及性能验收。构建成功只证明编译链接，不能代替这些结果。

最终构建命令：

```sh
DEVELOPER_DIR='/Users/papertiger/Downloads/Xcode-beta 3.app/Contents/Developer' xcodebuild build-for-testing -project Together.xcodeproj -scheme Together-UnitTests -destination 'generic/platform=iOS' -derivedDataPath /Users/papertiger/Library/Developer/Xcode/DerivedData/Together-djoefdjmosrqzacyvdvtuajwfgik -clonedSourcePackagesDirPath /Users/papertiger/Library/Developer/Xcode/DerivedData/Together-djoefdjmosrqzacyvdvtuajwfgik/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO
```

## 真机验收

使用包含本次修改的当前工程重新签名Run，现有手机安装不代表本次构建。检查详情日期/时间/提醒/标题/备注/子任务保存，列表推迟/优先级/关注，定期任务修改；确认取消及无改动不提示。检查胶囊与原球的表面和表情衔接、顶部等高/水平居中、长文案、深浅色、连续快捷修改、展开期间进入新建/详情、后台恢复、Reduce Motion、VoiceOver及大字号。恢复后模式切换和个人页入口应正常可用。

## Retrieval Evidence

Apple Knowledge query：`UIKit UIViewPropertyAnimator interrupt retarget presentation layer transform bounds overlay SwiftUI toolbar layout animations disabled`。命中keys：无；实际采用记录：无；无需 Expert Delta。

采用既有原生属性动画能力，并核验Apple关于[动态修改属性动画](https://developer.apple.com/documentation/UIKit/UIViewPropertyAnimator)及[受容器限制时的字体缩放上限](https://developer.apple.com/documentation/uikit/uifontmetrics/scaledfont(for:maximumpointsize:compatiblewith:))的文档。未增加第三方依赖或新的制作Skill。
