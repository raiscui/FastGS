## [2026-03-27 19:20:12 UTC] [Session ID: 64a33e57-aa0e-4613-b103-207945436fa5] 笔记: `v4` 筛帧对照资产复核与公平口径比较

## 来源

### 来源1: `v4` 重建摘要

- 文件:
  - `data/my5_local_pose_compare_v4_filter_view7_f3to6/pycolmap_run_summary.json`
- 已确认:
  - `reconstruction_ids = [0]`
  - `num_images = 44`
  - `num_reg_images = 44`
  - `num_points3D = 2995`

### 来源2: `comparison_summary.json` 的真实结构

- 文件:
  - `specs/my5_local_colmap_compare_assets/comparison_summary.json`
- 先前误判:
  - 我一开始按不存在的 `variants` 层读取, 得到了“没有写入 `filter_drop_v7_f3to6`”的假象.
- 复查后确认:
  - 顶层真实结构是:
    - `reconstruction_summary`
    - `local_camera_params`
    - `views`
    - `pairs`
  - `filter_drop_v7_f3to6` 已经真实存在于:
    - `reconstruction_summary`
    - `local_camera_params`
    - `views`
    - `pairs`

### 来源3: `v4` 连续性资产

- 文件:
  - `specs/my5_local_pose_compare_v4_filter_view7_f3to6_assets/pose_continuity_data.json`
- 结构确认:
  - `view_summary` / `pair_summary` 是 list
  - `frame_details` / `pair_details` 是按 `view` 或 `pair` 分组的 dict
  - `transition_summary_mode = contiguous`

## 综合发现

### 现象

- `v4` 的局部子集不是空模型.
- 它是真实成功重建的筛帧对照:
  - 删除 `view 7 frame 3~6`
  - 其余范围仍是 `view 5 / 6 / 7 / 8 + frame 1~12`
- 焦距继续下漂:
  - `widecontext_result = 488.9067`
  - `filter_drop_v7_f3to6_result = 423.4673`

### 当前主假设

- 删掉 `view 7 frame 3~6` 之后, 可能会让剩余帧的朝向连续性更平.
- 但这还不等于几何整体更健康.

### 最强备选解释

- `v4` 看起来更平的部分, 只是删除了高抖动帧之后的统计结果.
- 剩余帧的平移稳定性和跨机位约束可能反而更差.

### 直接对比: `widecontext` 全 12 帧 vs `v4` surviving 8 帧

- `view 7`
  - `obs_mean`: `490.9167 -> 418.1250`
  - `ratio_mean`: `0.2575 -> 0.2226`
  - `step_mean`: `2.3200 -> 4.3881`
  - `rot_mean`: `3.4714 -> 2.9710`
- `6-7`
  - `delta_dist_mean`: `1.2944 -> 2.5726`
  - `delta_rot_mean`: `1.8286 -> 1.5900`
- `7-8`
  - `delta_dist_mean`: `1.5666 -> 2.4108`
  - `delta_rot_mean`: `2.3023 -> 1.6864`

### 更公平的比较口径: 用 `widecontext` 同样保留下来的帧集合重算

- 为避免把已删除的 `3~6` 帧直接混入基线, 额外用 `widecontext` 的 surviving frames:
  - `{1, 2, 7, 8, 9, 10, 11, 12}`
  - 且只统计真实 contiguous transitions:
    - `2, 8, 9, 10, 11, 12`
- 公平口径下的 `view 7`:
  - `obs_mean`: `536.5000 -> 418.1250`
  - `ratio_mean`: `0.2889 -> 0.2226`
  - `step_mean`: `2.1123 -> 4.3881`
  - `rot_mean`: `3.2582 -> 2.9710`
- 公平口径下的 `6-7`:
  - `delta_dist_mean`: `1.2609 -> 2.5726`
  - `delta_rot_mean`: `1.8143 -> 1.5900`
- 公平口径下的 `7-8`:
  - `delta_dist_mean`: `1.4163 -> 2.4108`
  - `delta_rot_mean`: `2.0900 -> 1.6864`

### 逐帧证据: surviving frames 并没有整体变健康

- `view 7` 同帧对照 `v3 -> v4`
  - `frame 2`: `step 1.6521 -> 3.1120`, `rot 2.9345 -> 2.6272`
  - `frame 8`: `step 1.0115 -> 1.9623`, `rot 1.5562 -> 1.4410`
  - `frame 9`: `step 2.0880 -> 4.5406`, `rot 3.1548 -> 2.8661`
  - `frame 10`: `step 2.7423 -> 6.0687`, `rot 4.1952 -> 3.9571`
  - `frame 11`: `step 2.7753 -> 6.0050`, `rot 4.1108 -> 3.7812`
  - `frame 12`: `step 2.4048 -> 4.6400`, `rot 3.5975 -> 3.1531`
- `6-7` 同帧 pair 对照
  - `frame 10`: `delta_dist 1.3458 -> 3.1719`, `delta_rot 1.8081 -> 1.6977`
  - `frame 12`: `delta_dist 1.6420 -> 3.6895`, `delta_rot 2.1667 -> 2.0320`
- `7-8` 同帧 pair 对照
  - `frame 9`: `delta_dist 2.1251 -> 4.4549`, `delta_rot 3.1014 -> 2.7639`
  - `frame 10`: `delta_dist 2.4155 -> 4.6294`, `delta_rot 3.6210 -> 3.0937`

## 当前结论

- 不能把 `rotation_mean` 下降直接写成“删帧成功”.
- 当前更稳的结论是:
  - `v4` 让 rotation 类指标略有下降
  - 但同时让点支持、平移连续性和跨机位距离连续性明显变差
- 因此现有证据不支持:
  - “删掉 `view 7 frame 3~6` 以后, 剩余帧几何明显改善”
- 更合理的写法应是:
  - 删帧改变了误差形态
  - 没有把问题真正修顺
