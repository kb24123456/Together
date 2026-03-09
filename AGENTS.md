# Repository Instructions

- 本仓库 `Together` 的 GitHub 远端仓库固定为 `https://github.com/kb24123456/Together.git`
- 默认 `origin` 应指向上述地址
- 后续在本仓库内进行提交、推送、分支协作时，均以该远端仓库为唯一目标
- 如需变更远端，必须先得到用户明确确认，不能擅自切换到其他 GitHub 仓库
- 本仓库所有 iOS UI 设计与前端实现，必须优先遵循 Apple 官方设计规范与安全区域约束
- 设计稿、Pencil 线框、高保真视觉稿、SwiftUI 页面实现，均必须预留顶部和底部安全区域，避免与动态岛、状态栏、Home Indicator、底部系统手势区域、Tab Bar 发生遮挡或误触冲突
- 底部导航条、悬浮按钮、顶部返回按钮、胶囊按钮等系统级控件，默认按 iOS 原生布局习惯放置，不允许仅为了视觉效果侵入安全区域
- 液态玻璃风格组件优先复用或贴近 Apple 标准导航和控件行为，避免做出与系统层级冲突的高饱和装饰性假玻璃
- 具体规则与来源维护在 `/Users/papertiger/Desktop/Together/DESIGN_GUIDELINES.md`，后续所有 UI 设计与实现默认遵循该文件
