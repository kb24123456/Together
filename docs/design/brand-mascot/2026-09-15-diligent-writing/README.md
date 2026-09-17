# 专注苦写 · 2026-09-15

后续用户确认眼距收紧、眼线加粗并导出安装真机。当前资源以[眼部精修接入记录](eye-refinement-review/README.md)为准，下文保留第一轮实现与离线验证记录。

用户选择三张概念图中的第一张，并确认落实到实际小球。造型基准为 `approved-concept.png`；本目录的 `final-*` 是生产 Rive 资源的真实离线渲染，不是概念图动画。

## 当前实现

- 保持正圆主体、黑白主题、无细臂圆手、原有30pt编辑导航球体与跨页承接。
- 眼睛略向笔尖下压，眼线缩短、加粗并错开高度；停笔时角度略放松。近手直径108、远手100画板单位，保留非对称姿态。笔杆延长到178单位，浅色笔杆从米白改为灰色 `#B6B2AA`，Rive默认配色与App Palette同步。
- `Writing` 保留3.6秒循环，改为三组不等长短笔画，包含轻重落笔、短暂停顿、提笔归位。球体随落笔轻微下压，最大纵向压缩0.8%，不增加夸张摇摆、汗滴或表情部件。
- `WritingEnter / Writing / WritingHold / WritingExit` 四段统一姿态，并将笔迹显隐设为0，消除停笔时底部杂线。输入停止约0.9秒后的持笔切换仍由现有App控制，未新增计时器或等待整段循环的逻辑。
- 139条时间轴中只改上述四条；另外135条、完整状态机、对外接口与时间轴长度回读一致。另改一个既有ViewModel配色默认值。历史评审片不改动。

## 文件与预览

- App资源：`Together/Resources/BrandMascot/together_sphere_motion_study.riv`（仓库根目录下）。
- [运行资源](deliverables/together_sphere_motion_study.riv)、[完整可编辑文件](deliverables/together_sphere_motion_study.rev)、[修改前完整备份](backups/before.rev)。
- [浅色完整流程](final-flow-512-light/preview.mov)、[深色完整流程](final-flow-512-dark/preview.mov)。
- [30pt浅色](final-flow-126-light/preview.mov)、[30pt深色](final-flow-126-dark/preview.mov)：126px完整画板约对应30pt球体@3x，播放器放大不能代表设备物理尺寸。
- [边界切换](final-edges/preview.mov)：进入中退出、快速停续、书写转逾期/思考、返回首页。
- `MascotHolding` 两主题PNG直接取自最终资源的 `final-holding-*` 透明渲染帧。
- `apply-writing.py` 为一次性制作记录，需要匹配修改前快照；默认笔色另由Rive既有实例属性 `0-169109 / 555` 从 `#FFF2EEE6` 改为 `#FFB6B2AA`。

## 验证与边界

- `verification.json`：四条时间轴回读、其余135条不变、状态机不变、循环首尾一致、四段笔迹隐藏、最终资源哈希。
- 官方 Rive Apple 6.25.1 New Runtime / Metal 离线渲染4082帧，287张PNG均未触边，最小边距9px；抽查书写/持笔、两尺寸、两主题与退出静帧。连续视频供审阅，不将抽样检查扩写为逐帧人工验收。
- 当前资源SHA256：`b90393c6a35a1c21dd29f11ae7e4a8b6c1451725464134daba3d5e238e72e42a`，4269185 bytes。
- Swift解析及diff检查通过；无签名App构建结果见 `verification.json`。系统默认Xcode26.6首次因iOS平台配置无法选择generic设备，后续使用已有 `Downloads/Xcode-beta 3.app`（Xcode27 / 27A5218g），不修改系统默认工具链。
- 未启动Simulator、未安装真机、未提交或推送。真机需用包含上述资源哈希的新构建验收实际连续输入/中文输入、停顿续写、取消保存返回、深浅色与Reduce Motion切换；未测量帧率或能耗。
- Rive首轮运行格式导出卡住；保存后重启编辑器、重新打开同一文件并确认四段关键帧数值保留，随后成功导出。最终REV确认内嵌资产；加载早期导出的不完整备份没有用作交付。
- Apple Knowledge query：`Rive native animation state transitions interruption Reduce Motion static fallback validation`；无命中、未采用记录，`无需 Expert Delta`。
