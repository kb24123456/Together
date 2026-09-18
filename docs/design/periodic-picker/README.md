# 定期日期选择器

2026-09-18，当前版本按用户最新反馈扩充可见数字，并简化年度选择。

## 当前布局

- 月度 / 季度数字按视窗七等分，普通手机宽度与默认字号完整显示七项。每格至少 44pt，并随 Dynamic Type 扩宽；不为凑足七项压缩文字或命中区。首尾不循环，特殊中文选项保留完整文字空间。
- 数字边缘渐隐收窄至约 2%，最外侧完整数字的基础可见度提高。日期仍然平直，只用明暗与固定中心指针表达选择；已验收的时间刻度球面动效不变。
- 年度移除 1–365 天数带，改为两排五个直接选项：年初、年末、首个工作日、最后工作日、年末前30天。底部只显示结果，取消重复菜单与箭头。大字号放不下时，长选项整行排列。
- 已有年度特殊规则（例如第183天）仍完整回显，用户选择新规则前保持原值。没有迁移、删除或改写历史规则；既有周期计算与最终保存路径不变。
- 底部日期保留 Rounded Medium，分组间距 16pt、同心按钮圆角与外缘留白保持现有设计。

## 图片与验证边界

- [月度七项](seven-monthly.png)
- [季度七项](seven-quarterly.png)
- [年度直接选择](annual-presets.png)

以上是当前 SwiftUI 组件的 **macOS 原生隔离布局截图**。预览适配 iPhone 默认语义字号、项目浅色颜色与 34pt 底部安全区；外壳宽 390pt、连续圆角 44pt，使用假数据及无持久化的 ViewModel 桩。内容实测月 / 季 255pt，年度 275pt，另加底部安全区。不是 iPhone 系统 Sheet / 真机截图，不证明触摸、原生 Zoom、深色或辅助功能布局已验收。旧 refined 图片仅留作上一版对照。

当前完整面板测量：月度显示 4–10，季度显示 42–48，各七个完整槽位；选中值分别为 7 / 45，中心偏差均为 0pt。布局密度已收敛，继续减小间距会损害读数与点击区域。

## 定位与检查

自适应槽宽使旧 LazyHStack 在 342→280pt 变化后残留约 2pt 边界偏差；改为有限日期集的 HStack，精确测量内容。ScrollPosition 在首次有效布局、视窗 / 字号变化时按中心重新定位。没有移动箭头、延时补偿、UIKit offset 读写或逐帧根状态。程序定位不回写 Draft。

- 原生隔离检查覆盖月 / 季首次定位、月末 / 第1天程序定位、342→280pt、窄宽中间值及恢复宽度；中心偏差小于 0.5pt，Draft 回写为 0。探针及日志：`/tmp/together-periodic-seven/`。
- 当前规则映射与时间相关测试共 23 项、3 个 suite 在临时 macOS Swift Package 通过；其中年度测试检查五个默认选项及第183天旧规则、提醒值保持不变。日志：`/tmp/together-periodic-seven-tests.log`。
- Swift parse、git diff --check、Xcode 27 RC generic iOS 无签名 build-for-testing 通过。构建日志：`/tmp/together-periodic-seven-build-final.log`。仅保留既有编译警告。
- 未启动 iOS Simulator、未安装设备、未提交或推送。需最新源码真机构建验收：初次居中、连续拖动 / 反向 / 点击、月末与特殊规则、年度选择 / 清除 / 保存 / 取消、深浅色、Dynamic Type、VoiceOver、Reduce Motion 与系统 Sheet 安全区。

构建命令：

```sh
xcodebuild -project Together.xcodeproj -scheme Together -destination 'generic/platform=iOS' -derivedDataPath /tmp/together-periodic-picker-build -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build-for-testing
```

Apple Retrieval Evidence：query `SwiftUI horizontal date selector seven visible cells viewAligned center ScrollPosition dynamic type fade mask touch target widths`；命中 keys / 实际采用记录：无（无需 Expert Delta）。当前 ScrollPosition 行为以 SDK 声明、编译和原生隔离检查为依据。
