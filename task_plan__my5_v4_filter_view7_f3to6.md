# 任务计划: `my5` `v4` 筛帧对照整理与正式结论

## [2026-03-27 19:20:12 UTC] [Session ID: 64a33e57-aa0e-4613-b103-207945436fa5] [记录类型]: 支线任务建档

### 目标
- 读取 `view 7 frame 3~6` 筛帧对照 `v4` 的真实资产.
- 用 `contiguous` 口径判断删帧后是否真的改善了 `view 7` 的几何稳定性.
- 把 `v4` 的结果正式写回汇总 JSON、总报告和支线六文件.

### 阶段
- [x] 阶段1: 回读 `v4` 资产与当前汇总状态
- [x] 阶段2: 形成 `现象 -> 假设 -> 验证计划 -> 已验证结论`
- [x] 阶段3: 更新 `comparison_summary.json` 与正式报告
- [x] 阶段4: 回写支线 `notes/WORKLOG/EPIPHANY_LOG` 并做收尾检查

### 关键问题
1. `comparison_summary.json` 当前到底有没有真正写入 `filter_drop_v7_f3to6`?
2. `contiguous` 口径下, `view 7` 和 `6-7` / `7-8` 的指标是改善了, 还是只是换了一种退化方式?
3. 焦距漂到 `423.4673` 该被写成改善信号, 还是新代价?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `v4` 子集已经真实重建成功.
  - `44/44` 全注册, `2995` 个 3D 点.
  - 但此前还没有把 `contiguous` 口径下的正式结论整理完.
- 当前主假设:
  - 删掉 `view 7 frame 3~6` 可能会让 `view 7` 的局部连续性略有改善.
  - 但这种改善未必意味着整体几何更健康, 因为点支持和相邻机位约束可能同时变弱.
- 最强备选解释:
  - `v4` 看起来更平滑的部分, 只是因为高波动帧被删除了.
  - 剩余帧并没有变得更可信, 只是样本更少了.
- 推翻主假设的关键证据:
  - 如果 `contiguous` 口径下 `view 7` 的 step / rotation 没有稳定下降, 或者 `6-7` / `7-8` 的 pair 约束更差, 那么“删帧带来真正改善”就不成立.

### 当前状态
- 目前已完成本支线整理.
- 已完成:
  - [x] 读取 `v4` pose 资产与 `pycolmap_run_summary.json`
  - [x] 确认 `comparison_summary.json` 当前真实结构
  - [x] 用公平口径重算 `v3` surviving frames `{1,2,7,8,9,10,11,12}` 对照
  - [x] 更新正式报告与汇总 JSON
  - [x] 完成支线 `notes/WORKLOG/EPIPHANY_LOG` 回写
  - [x] 校验 mermaid 与 JSON 结构
- 当前已确认的事实:
  - `v4` 不是空模型, 而是 `44/44` 全注册、`2995` 点.
  - `comparison_summary.json` 已经包含 `filter_drop_v7_f3to6`, 只是旧读取口径把结构读错了.
  - 用相同 surviving frames 公平比较时:
    - `view 7 rot_mean`: `3.2582 -> 2.9710`
    - `view 7 step_mean`: `2.1123 -> 4.3881`
    - `6-7 delta_dist_mean`: `1.2609 -> 2.5726`
    - `7-8 delta_dist_mean`: `1.4163 -> 2.4108`
- 当前结论:
  - `v4` 改变了误差形态, 但没有把剩余帧真正修顺.
  - 这版更适合作为反证, 不适合直接接回主线当默认筛帧方案.
- 下一步:
  - 如果继续 `my5`, 优先做更保守的 mapper / BA 参数对照.
  - 如果继续筛帧, 必须继续沿用 fair surviving-subset 比较口径.

## [2026-03-27 19:42:43 UTC] [Session ID: bec3884b-8f95-44f1-a6b3-efb9959efacb] [记录类型]: 新开支线 `__my5_v5_conservative_mapper`, 目标是在 `v3_widecontext` 同一批 `48` 张图上只改 mapper / BA 参数, 验证更保守的重建口径能否改善 `view 7`.
