# 改期结果短注视 · Rive 交付

正式项目仍为 fileId `2564580`，Artboard `TogetherSphere`，状态机 `Mascot`，ViewModel `TogetherSphereModel`。本轮仅新增 `noticeResult` Trigger 和 `LightActions` 中的 `Action_NoticeResult`，原造型、A4 书写、随机表情池、球面视线、眨眼与深浅色绑定均保留。

- 动作长 0.9 秒；约 0.30 秒自然进入、0.18 秒停留、0.42 秒恢复。位移轨道使用零端点速度的五次平滑曲线，没有回弹或身体跳动。
- `FaceMotion` 父层向左 14、向下 30 画板单位，随后精确回到 0。它在当前球面姿态上增加一次向下的注意力变化，不重置底层眼型、朝向或随机动画进度。若底层恰在极端向上注视，最终眼心不一定落在球的下半部。
- 仅 `mode=0`（日常）或 `mode=2`（逾期）允许触发；后者保留原流汗表达。进入编辑、OCR 或其他模式时，100ms 退出至现有 `Action_Rest`。不新增 Active Bool；App 在暂停时使用既有消耗一次性动作的推进方式，避免恢复补播。
- 原有 138 条动画共 353177 个关键帧按 ID、属性、值、时间与插值逐项核对未改；所有旧状态、转换与条件未改。增加 1 条时间线、248 关键帧、1 状态、4 转换和 1 Trigger。细节见 `rive-diff-verification.json` 与 `result-glance.json`。

## 资源与回退

App 正式资源与 `deliverables/together_sphere_motion_study.riv` 一致：4269590 bytes，SHA256 `7eb9ed8e1ee821322c2a12d70832e0ab969e0d4c394f5450b8e8c18c1eb72bd8`。

`deliverables/together_sphere_motion_study.rev` 是完成后的完整可编辑文件。修改前实时完整文件为 `backups/before-continuity.rev`，原 App 的已验收资源为 `backups/app-before.riv`。各文件指纹见 `rive-resource-manifest.json`，原动画逐键快照保存在 `backups/all-keyframes.json.gz`。没有提交或推送 Git。

重新打开当前正式项目后的修改前 `.riv` 导出为 `1204c11d…`，与原 App 的 `8dfea4c3…` 字节顺序不同。核对现行 `Writing` 的全部 3267 个关键帧后，ID、时序、数值与插值均与上轮 `writing-after.json` 相同；整台状态机也与上轮快照相同。该修改前导出独立保留，不能将两个哈希写成一致。

## 已完成验证与限制

- `notice-result-runtime-verification.json`：53/53 原生状态机检查通过，覆盖准入、被禁止时不延迟触发、编辑/OCR 中断和任意阶段暂停清理。
- `notice-40pt-light/` 与 `notice-40pt-dark/`：各 900 帧 Apple Rive Runtime 原生回放，包含日常注视、逾期注视、书写中断与恢复。48 张关键 PNG 边界检查通过，入场、停留、结束与编辑姿态抽查未见裁切或形状突变；视频为各目录的 `preview.mov`。
- 本次未运行 iOS Simulator、未安装 Together、未测性能或能耗；跨页真实观感与 App 原生导航交接仍需真机验收。
- 既有 Metal 回放工具使用异步 Worker，同一 `.riv` 重跑也可能产生不同的逐帧采样结果，因此回放用于视觉内容核对，不能用其帧哈希证明动画精确同步。状态轨迹来自单独的原生 inspection 实例，不能冒充画面实例的内部轨迹。

## 复核入口

`add-result-glance.py` 为本轮限定范围的作者记录，禁止在已添加动作的项目上重复执行。`verify-result-glance.swift` 是独立原生状态回放检查；通过现有 macOS RiveRuntime.framework 编译后，用两个参数运行：正式 `.riv` 路径与输出 JSON 路径。小尺寸回放沿用 `../2026-09-09-expression-system/runtime-qa/build-renderer.sh` 和 `sequence.swift`，故事输入为 `notice-40pt-light.json` / `notice-40pt-dark.json`。
