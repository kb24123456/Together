# 小球显示校样

日期：2026-09-08。用户已对本版配色校样反馈“我觉得可以”，配色定稿为浅色黑球、深色柔白球和近黑五官。当前扩充为八种姿势、十六张原生 PNG 的尺寸与静态稿对照，未接入或修改 App；配色认可不等于所有表情定稿或原生真机验收。开心/庆祝仍待复核，流泪沿用暂用 B 版。

## 打开与检查

直接打开离线 `review.html`。旧 `phone-preview-qr.png` 对应此前的临时局域网服务，本轮未验证该服务或地址仍可用；如需手机访问，应使用当前实际运行的预览服务重新生成入口。

打开 `review.html`，初始为深色柔白球。可切换“柔白球 / 原黑球”直接比较；浅色固定使用原黑球。首页比较球体 36 / 40 / 44pt，编辑页比较 40 / 48 / 56pt。首页 40pt、编辑 48pt 仅作比较起点，尚未经用户验收。直达参数支持 `theme=dark&appearance=white` 或 `appearance=black`。

1. 在 iPhone 默认页面缩放下使用“本机尺寸查看”。预览不整体缩放；桌面浏览仅用于比较比例，不能证明手机物理尺寸。此页按当前代码重建顶部内容布局，不是 App 真机截图；Safari 与原生导航栏的安全区域表现仍须接入后验收。
2. 切换常驻、持笔、思考、担忧、开心/庆祝、单眨眼、流泪、打盹，观察两条眼线、笔、手、汗滴与泪水是否能辨认，标题和取消/保存是否仍清楚。显示边界用于检查留白，不属于最终 UI。
3. 切换浅色/深色，在正常和较低屏幕亮度下观察主体轮廓、手与身体的分离、柔白球是否过亮以及眼线和汗滴是否清楚。页面使用 App 实际白底和深灰黑底，没有用 CSS 滤镜假装调低设备亮度。
4. 下方每个姿势依次展示浅色原黑球、深色原黑球、深色柔白球。静态降级素材可按场景比较，最终使用哪些表情仍以 App 映射为准；加载失败应独立加载对应主题的常驻 PNG。此页展示素材，不模拟或宣称已通过 Rive 加载失败、Reduce Motion 或真机交互测试。

## 新增五种表情

| 姿势 | Rive 原生取样 | 浅色 / 深色素材 |
| --- | --- | --- |
| 思考 | Thinking，第 120 帧 | assets/thinking.png / thinking-white.png |
| 开心/庆祝（待复核） | Celebrate，第 30 帧 | assets/happy.png / happy-white.png |
| 单眨眼 | Expression_Wink，第 38 帧 | assets/wink.png / wink-white.png |
| 流泪（暂用） | Expression_Tears，第 90 帧 | assets/tears.png / tears-white.png |
| 打盹 | Doze，第 120 帧 | assets/doze.png / doze-white.png |

新增素材来自同一 `TogetherSphere` 主画板（0-2），保留表情取样并统一球体 root 为中心 (256,240)、100% 等比缩放、0° 旋转；因而可与原六图共用球径 368 的标尺。它们是静态姿势校样，不能用来判断动态幅度或动画最大边界。流泪的浅色泪水为 #88CFF3，深色为 #347FA6，其他主题延续已有配色。

`expression-source-manifest.json` 记录新增十图的动画 ID、取帧、归一化、哈希与像素结果；原 `source-manifest.json` 及六张已认可 PNG 保持原样。庆祝的双手使非透明边界扩展到 [33,56]–[477,424]，40pt 球体时总宽约 48.26pt，需注意手部留白；其余新增姿势边界为 [72,56]–[440,424]。

本轮静态检查见 `verification-expressions-static.json`：31 项通过，包含旧六图哈希不变、新十图 512×512 RGBA 与透明边缘、八对黑白图逐像素 alpha 一致，以及离线页素材一致性、标记结构和 JavaScript 语法检查。离线页已嵌入全部十六张 PNG，无外部资源依赖。浏览器校样已通过 CUA 完成下列五组检查，见 `verification-expressions-browser.json`；旧 `verification-preview.json` 的 129 项只代表此前六素材页面，不作为本次十六素材页面的验收。

重建离线页：`python3 docs/design/brand-mascot/2026-09-08-display-review/build-review.py`。直达姿势支持 `pose=idle|holding|thinking|concerned|happy|wink|tears|doze`；例如 `review.html?pose=tears&theme=dark&appearance=white`。

## 新增表情的浏览器校样

记录于 2026-09-09。主任务通过 CUA 实际检查以下静态网页组合：

| 浏览器视口 | 页面 | 配色 | 姿势与球径 |
| --- | --- | --- | --- |
| 402×874 | 首页 | 深色白球 | 开心/庆祝 44pt、流泪 36pt |
| 402×874 | 首页 | 浅色黑球 | 单眨眼 36pt |
| 375×812 | 编辑页 | 浅色黑球 | 开心/庆祝 56pt |
| 375×812 | 编辑页 | 深色白球 | 流泪 48pt |

上述五组均目视确认角色没有裁切、没有遮挡标题，编辑页取消与保存仍清楚；浏览器 warning/error 均为 0。已保留三张浏览器截图：`expressions-home-dark-tears-36.png`、`expressions-editor-light-happy-56.png`、`expressions-editor-dark-tears-48.png`。截图尺寸与哈希记录于验证文件。

这些结果只覆盖列出的五组组合，不是八种姿势与所有尺寸、主题的完整视觉矩阵，也不是 App 或物理 iPhone 验收。页面不运行 Rive，尚不能确认动态切换、Reduce Motion、原生安全区域、动态字体、触摸范围、设备亮度或性能。开心/庆祝的布局已检查，表情审美仍待复核。

## 原六图素材（历史）

| 文件 | 取样 | 用途 |
| --- | --- | --- |
| assets/idle.png | Idle，0 帧 | 常驻、动画加载失败的默认形象 |
| assets/holding.png | WritingHold，0 帧 | 编辑中关闭动画的持笔姿势 |
| assets/concerned.png | Concerned，0 帧 | 当前逾期的静态担忧姿势 |
| assets/idle-white.png | Idle，0 帧 | 深色柔白常驻候选 |
| assets/holding-white.png | WritingHold，0 帧 | 深色柔白持笔候选 |
| assets/concerned-white.png | Concerned，0 帧 | 深色柔白担忧候选 |

均为 Rive 原生透明 RGBA PNG，512×512。不是 AI 重新生成的形象，也不是动画中途半透明的截图；三种取样的球心、大小和旋转完全一致。每对黑白素材 alpha 逐像素相同，原黑素材哈希未变。素材尚未安装到 App 资产目录。

柔白球体为 #F0F0F0 至 #D5D5D5 的原生径向渐变，眼部 #1B1B1B，汗滴 #686868。圆手采用稍深的柔白渐变；笔杆与笔迹单独改为灰色，保留少量原木色。历史静态捕获属性与临时远手渐变见 `white-appearance.json`，不要把其中的透明旧填充值用于生产。随后已建立Rive同一实例的主题绑定，当前目标ID/颜色以 [theme-v6.json](../2026-09-08-rive-study/theme-v6.json) 为准；Apple runtime尚未接入。本目录六张已认可PNG保留原样。

## 尺寸与对齐

画板 512×512，球体直径 368，球心 (256,240)，因此显示画板边长 = 球体直径 × 512 / 368。不能将整图中心 (256,256) 当成球心，也不能把整张图缩到 40pt 后称为“40pt 球体”。

| 可见球体 pt | 整张图片边长 pt |
| --- | --- |
| 36 | 50.087 |
| 40 | 55.652 |
| 44 | 61.217 |
| 48 | 66.783 |
| 56 | 77.913 |

原生 PNG 的非透明边界：常驻/担忧 [72,56]–[440,424]；持笔 [72,56]–[440,479]，含笔尖与笔迹。因此 40pt 球体下持笔整体可见高度约 45.98pt。图像留白、可见主体与按钮点击范围需要分别处理；首页保留至少44×44pt命中，不沿用头像的圆形裁切。动画的最大边界另见 v6 验证，静态边界不能替代完整动画边界。

## 来源与边界

- 角色：[Together Sphere Motion Study](https://editor.rive.app/file/together-sphere-motion-study/2561771)，画板 TogetherSphere (0-2)；取样来自 motion-v6.json。黑球捕获后核对 184 个 Design 属性；白球捕获后核对含配色在内的 208 个属性并对照部件层级，均与捕获前一致。临时远手填充已删除，原有填充和 ID 保留；没有改动关键帧、状态机或最终 Design 配色。
- 首页：Together/App/AppRootView.swift 的 40pt 头像、44pt 按钮、居中待办/定期切换。正文与编辑区域参照 HomeView.swift、TaskCreationView.swift、TaskDetailView.swift；演示任务明确使用示例文字，没有用户任务数据。
- 背景：Together/Core/DesignSystem/AppTheme.swift:53，浅色 #FFFFFF、深色约 #1C1C1F。
- 按钮命中范围也符合 [Apple 按钮设计指南](https://developer.apple.com/design/human-interface-guidelines/buttons)。页面 CSS 尺寸校验不能替代原生可访问性和触摸测试。
- source-manifest.json 记录素材来源、取帧、哈希与恢复结果；verification-static.json 保留黑球姿态检查，verification-white.json 记录六张素材及原生恢复检查，verification-preview.json 为当前六素材页面的浏览器检查。
- 此前 .riv/.rev 导出套餐限制未在本轮重试。当前为静态素材和浏览器布局校样，不是可运行的 Rive 资产、原生备份或 App 构建。

## 原六图验证（历史）

- 六张原生 PNG 全部为512×512 RGBA，透明留白完整；每对262,144个 alpha 像素全部一致，持笔最大非透明Y为478像素，未触及画板边缘。208项原属性与部件层级捕获后恢复，Rive 动画和状态机未修改。
- 浏览器129项检查通过：桌面及375/402宽度、两种页面、浅色黑球与深色白球、三种姿势、所有候选尺寸；球径换算和球心对齐准确，无横向溢出，标题不被角色遮挡。白/黑切换、浅色强制黑球、主题选择保留、六原生素材嵌入、边界切换、手机展开/返回、直达链接和离线加载正常，无页面脚本错误。
- 已人工检查浏览器桌面与移动视口截图。白球在深色底上轮廓清楚，圆手有柔和层次；原黑球保留对照。低亮度白球是否过亮、主观尺寸选择仍待用户在物理设备确认。
- 默认Playwright随包浏览器未安装，改用本机已安装Chrome完成浏览器检查；没有安装新浏览器、启动iOS Simulator、运行App构建或验收物理设备。
- 当前截图 review-desktop.png、review-mobile-home-light.png、review-mobile-editor-dark.png 为浏览器渲染，不是原生App或iPhone截图。

## 下一步

先结合 Rive 总预览检查表情连续切换，再用本页确认新增五种表情的小尺寸和深浅色可读性。开心/庆祝仍待主观复核；其余沿用现有方向。取得可运行资产后，再接入原生静态加载兜底、Reduce Motion、实际业务与真机验收。首页40pt、编辑48pt继续作为接入比较起点，最终尺寸与低亮度表现由包含实际实现的设备版本验证。
