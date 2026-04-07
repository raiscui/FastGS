# 任务计划: `my5` `v5` 保守 mapper / BA 参数对照

## [2026-03-27 19:42:43 UTC] [Session ID: bec3884b-8f95-44f1-a6b3-efb9959efacb] [记录类型]: 支线任务建档

### 目标
- 复用 `v3_widecontext` 的同一批 `48` 张图.
- 只调整 `pycolmap` 的 mapper / BA 参数, 做一版更保守的局部重建对照.
- 判断“内参漂移 + 较松阈值”是不是 `widecontext` 失稳的重要成分.

### 两种方向
- 方案A(更保守, 我先执行这条):
  - 固定 `v3` database 里的相机 prior `592.1701, 640, 360`
  - 关闭 focal / extra params refine
  - 收紧初始化、绝对位姿和重投影过滤阈值
  - 保持同一批 `48` 张图不变
- 方案B(更温和, 备用):
  - 保留 focal refine
  - 只收紧 reprojection / triangulation / inlier 阈值
  - 用来区分“主要是内参漂移问题”还是“主要是观测过滤问题”

### 阶段
- [ ] 阶段1: 固化 `v5` 参数组并准备实验目录
- [ ] 阶段2: 跑 `pycolmap` 重建并收集动态证据
- [ ] 阶段3: 跑同口径连续性分析并和 `v3` / `v4` 对照
- [ ] 阶段4: 更新报告与支线记录

### 关键问题
1. `v3_widecontext` 的 database 是否确实带了 prior 相机, 可以直接复用?
2. 更保守的参数如果让焦距不再漂移, `view 7` 的 `step_mean` 会不会一起改善?
3. 如果 rotation / step / 点支持继续互相打架, 该如何判断这版参数是否真的更好?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `v3_widecontext` 在 `48` 张图上成功重建, 但焦距漂到 `488.9067`.
  - `v4` 删帧后 rotation 类指标略平, 但平移和点支持更差.
  - 当前还没有做“同一批 `48` 张图, 只改 mapper / BA 参数”的对照.
- 当前主假设:
  - `widecontext` 的问题里, 至少有一部分可能来自:
    - focal / extra params 继续自由漂移
    - 以及 mapper / triangulation 过滤阈值偏松
  - 如果把这些变量收紧, `view 7` 也许会比 `v3` 更稳.
- 最强备选解释:
  - 即便参数更保守, `view 7` 的困难仍主要来自素材本身.
  - 那么这版实验最多只会改变误差形态, 不会把它根本修顺.
- 推翻主假设的关键证据:
  - 如果焦距不漂了, 但 `view 7 step_mean` / `6-7` `7-8` 的 pair distance 仍然没有改善, 那就不能再把重点放在 mapper 参数上.

### 当前状态
- 目前在阶段1.
- 下一步先做:
  - 确认 prior 相机参数
  - 固化 `v5` 参数组
  - 准备 `data/my5_local_pose_compare_v5_conservative_mapper`

## [2026-03-27 21:21:39 UTC] [Session ID: ab193163-bc82-41a9-a59a-16ae44fbac63] [记录类型]: 基于 `v5` 逐帧结果继续新开支线 `__my5_v6_filter_view7_highrot`

### 新现象
- `v5` 已经把相机 prior 固定回 `592.1701`.
- 但 `view 7 rotation_mean` 仍偏高.
- 逐帧最高 rotation 的前几帧是:
  - `frame 3 = 5.8614`
  - `frame 5 = 5.4133`
  - `frame 4 = 5.1270`

### 当前判断
- 如果要删素材图, 更应该删“具体高 rotation_step 的帧”.
- 不能直接对 `rotation_mean` 这个聚合值下手.
- 为了避免重复 `v4` 那种 gap 太大的问题, 先做最小删帧:
  - 删 `view 7 frame 3 / 4 / 5`
  - 暂时保留 `frame 6`
