# 任务计划: `my5` `v6` 删掉 `view 7` 高 rotation 帧

## [2026-03-27 21:21:39 UTC] [Session ID: ab193163-bc82-41a9-a59a-16ae44fbac63] [记录类型]: 支线任务建档

### 目标
- 在 `v5_conservative_mapper` 的同一套参数口径上, 试一版“删掉 `view 7` 高 rotation 素材图”的对照.
- 当前先删:
  - `view 7 frame 3`
  - `view 7 frame 4`
  - `view 7 frame 5`
- 判断这版是否能在不继续漂焦距的前提下, 降低 `view 7` 的 rotation / step.

### 阶段
- [x] 阶段1: 固化删帧列表并准备 `selected_images.txt`
- [x] 阶段2: 复用 `v5` 参数链路重跑 `extract_features -> match_exhaustive -> incremental_mapping`
- [x] 阶段3: 跑连续性分析并和 `v5` / `v4` 对照
- [x] 阶段4: 回写支线记录并给出结论

### 关键问题
1. 删除 `frame 3 / 4 / 5` 后, `frame 2 -> 6` 的 gap 会不会再次把统计口径搞坏?
2. 这版如果 `rotation` 下降, `step` 会不会也跟着改善, 还是继续打架?
3. 如果 `6-7 / 7-8` 的 pair distance 变差, 这版还能不能被视为有效?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `v5` 虽然锁住了焦距, 但 `view 7 rotation_mean` 仍是 `4.1245`.
  - 逐帧最高的 rotation 帧集中在:
    - `3, 4, 5`
  - 这三帧同时点支持偏低.
- 当前主假设:
  - 删掉 `frame 3 / 4 / 5` 之后, `view 7` 的前段 rotation 异常可能会下降.
  - 因为 `frame 6` 仍保留, 这版比删掉 `3~6` 更不容易产生过大的连续性断口.
- 最强备选解释:
  - 即便删掉这三帧, 剩余帧的 step / pair distance 仍可能更差.
  - 那样就只能说明高 rotation 帧是“症状帧”, 不是主因.
- 推翻主假设的关键证据:
  - 如果 `rotation_mean` 降了, 但 `step_mean` / `delta_dist_mean` 继续恶化, 那这版仍不能接回主线.

### 当前状态
- 目前在阶段1.
- 下一步先生成新的 `selected_images.txt`, 然后直接开跑 `v6`.

## [2026-03-28 00:00:00 UTC] [Session ID: unknown-env-missing] [记录类型]: 接手并继续 `v6` 连续性验证

### 当前接手判断
- 已确认:
  - `v6` 的 `extract_features -> match_exhaustive -> incremental_mapping` 已完成.
  - 当前还缺连续性分析与 `v5` / `v4` 的对照整理.
- 本轮不会把“删帧应该更稳”直接当结论.
- 本轮先补动态证据, 再决定这批 `view 7` 素材图是否真的该不要.

### 本轮计划
- [x] 补跑 `v6` 的 pose continuity 分析, 优先看 `contiguous` 口径.
- [x] 对照 `v5` 与旧报告, 核实 `rotation_mean`、`step_mean`、`delta_dist_mean`、`delta_rot_mean`.
- [x] 回写支线记录并给出“能不能不要这些图”的结论.

### 当前状态
- 目前进入阶段3.
- 下一步先检查 `v6` 目录与分析脚本, 然后直接跑 continuity 分析.

## [2026-03-27 21:29:13 UTC] [Session ID: unknown-env-missing] [记录类型]: `v6` 连续性验证完成

### 现象
- `v6` 已成功重建:
  - `45/45` 全注册
  - `4950` points
- 最终相机参数仍锁定在:
  - `SIMPLE_PINHOLE [592.1701367226717, 640, 360]`
- 删除列表确认是:
  - `view 7 frame 3`
  - `view 7 frame 4`
  - `view 7 frame 5`

### 验证结果
- `contiguous` 口径:
  - `view 7 rotation_mean: 3.5943`, 比 `v5` 的同机位 `4.1245` 更低.
  - 但和公平 surviving 子集对照时:
    - `v5 simulated remove 3/4/5 cont step_mean = 1.9306`
    - `v6 cont step_mean = 2.5121`
    - `v5 simulated remove 3/4/5 cont rot_mean = 3.6314`
    - `v6 cont rot_mean = 3.5943`
  - 也就是 rotation 只略好一点, 但 step 明显更差.
- `all` 口径:
  - `view 7 step_mean = 3.9305`
  - `view 7 rotation_mean = 5.5587`
  - 其中 `frame 2 -> 6` 跳跃直接达到:
    - `step = 13.8591`
    - `rotation = 19.3099`
- pair 级别:
  - `contiguous`
    - `6-7 delta_dist_mean = 1.1773`, `delta_rot_mean = 1.6937`
    - `7-8 delta_dist_mean = 1.6193`, `delta_rot_mean = 2.2360`
  - 对公平 surviving 子集的 `v5` 模拟对照:
    - `6-7`: `dist 0.9451 -> 1.1773`, `rot 1.7793 -> 1.6937`
    - `7-8`: `dist 1.2826 -> 1.6193`, `rot 2.3157 -> 2.2360`
  - 仍然是 rotation 略降, distance 变差.

### 当前结论
- 这版不能直接写成“删掉 `view 7` 高 rotation 帧后几何更稳”.
- 更准确的结论是:
  - 删掉 `frame 3 / 4 / 5` 后, `rotation` 类指标有轻微改善.
  - 但 `translation / pair distance / 点支持` 没有同步改善, 反而更差.
  - 如果按 surviving 序列整体看, `2 -> 6` 的断口非常重.
- 因此:
  - 这些图“可以做对照实验地删”.
  - 但“不适合直接当成主线默认删除策略”.

### 当前状态
- 阶段1 到阶段4 已完成.
- 这条支线当前结论已经足够交付.
