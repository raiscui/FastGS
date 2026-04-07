## [2026-03-27 21:29:13 UTC] [Session ID: unknown-env-missing] 笔记: `v6` 删 `view 7 frame 3/4/5` 的连续性复核

### 现象

- 用户希望验证:
  - `view 7 rotation_mean` 偏高的素材图, 能不能直接不要.
- 已知删除候选来自 `v5` 的逐帧 rotation 排序:
  - `frame 3 = 5.8614`
  - `frame 5 = 5.4133`
  - `frame 4 = 5.1270`
- 本轮实际删除:
  - `010_7_generated_videos_generated_video_0_000003.jpg`
  - `010_7_generated_videos_generated_video_0_000004.jpg`
  - `010_7_generated_videos_generated_video_0_000005.jpg`

### 当前主假设

- 如果 `view 7` 前段高 rotation 主要是由这 3 帧主导, 那么删掉它们之后:
  - `rotation_mean` 应该下降.
  - 而且在不继续漂焦距的前提下, `step_mean` 和邻机位 pair continuity 最好也别恶化.

### 最强备选解释

- 高 rotation 帧只是症状帧, 不是主因.
- 真正的问题可能在:
  - 剩余帧之间的几何本来就更跳.
  - 或者删帧后 `2 -> 6` 大断口把 surviving 序列整体拉坏.

### 验证动作

- 跑 `v6` 的 `contiguous` 连续性分析:
  - `python3 scripts/analyze_colmap_pose_continuity.py --images-bin data/my5_local_pose_compare_v6_filter_view7_highrot/distorted/sparse/0/images.bin --output-dir specs/my5_local_pose_compare_v6_filter_view7_highrot_assets --focus-views 5 6 7 8 --transition-summary-mode contiguous`
- 跑 `v6` 的 `all` 连续性分析:
  - `python3 scripts/analyze_colmap_pose_continuity.py --images-bin data/my5_local_pose_compare_v6_filter_view7_highrot/distorted/sparse/0/images.bin --output-dir specs/my5_local_pose_compare_v6_filter_view7_highrot_assets_all --focus-views 5 6 7 8 --transition-summary-mode all`
- 额外核对最终相机参数:
  - `v5` 与 `v6` 的 `cameras.bin` 都是 `SIMPLE_PINHOLE [592.1701367226717, 640, 360]`

### 动态证据

- `v6` mapper 结果:
  - `45/45` 全注册
  - `4950` points
- `v6 contiguous`:
  - `view 7 obs_mean = 452.2222`
  - `view 7 ratio_mean = 0.2399`
  - `view 7 step_mean = 2.5121`
  - `view 7 rotation_mean = 3.5943`
  - `6-7 delta_dist_mean = 1.1773`
  - `6-7 delta_rot_mean = 1.6937`
  - `7-8 delta_dist_mean = 1.6193`
  - `7-8 delta_rot_mean = 2.2360`
- `v6 all`:
  - `view 7 step_mean = 3.9305`
  - `view 7 rotation_mean = 5.5587`
  - 最大断口出现在 `frame 2 -> 6`:
    - `step = 13.8591`
    - `rotation = 19.3099`

### 公平对照口径

- 不能直接拿 `v6` 的 9 帧和 `v5` 的完整 12 帧均值直接比.
- 更公平的是:
  - 用 `v5` 里相同 surviving frame 集合:
    - `{1,2,6,7,8,9,10,11,12}`
  - 再分成两种统计:
    - `contiguous`: 只统计真正邻帧
    - `all`: 把 `2 -> 6` 的跳跃也算进去

### 公平对照结果

- `view 7 contiguous`
  - `v5 simulated remove 3/4/5`
    - `obs_mean = 482.7778`
    - `ratio_mean = 0.2553`
    - `step_mean = 1.9306`
    - `rotation_mean = 3.6314`
  - `v6`
    - `obs_mean = 452.2222`
    - `ratio_mean = 0.2399`
    - `step_mean = 2.5121`
    - `rotation_mean = 3.5943`
- `6-7 contiguous`
  - `v5 simulated remove 3/4/5`
    - `delta_dist_mean = 0.9451`
    - `delta_rot_mean = 1.7793`
  - `v6`
    - `delta_dist_mean = 1.1773`
    - `delta_rot_mean = 1.6937`
- `7-8 contiguous`
  - `v5 simulated remove 3/4/5`
    - `delta_dist_mean = 1.2826`
    - `delta_rot_mean = 2.3157`
  - `v6`
    - `delta_dist_mean = 1.6193`
    - `delta_rot_mean = 2.2360`
- `view 7 all`
  - `v5 simulated remove 3/4/5`
    - `step_mean = 3.0099`
    - `rotation_mean = 5.6012`
  - `v6`
    - `step_mean = 3.9305`
    - `rotation_mean = 5.5587`

### 结论

- 已验证结论:
  - 删除 `view 7 frame 3/4/5` 后, `rotation` 类指标确实略有下降.
  - 但下降幅度不大.
  - 与此同时:
    - 点支持下降
    - `step_mean` 变大
    - 邻机位 `delta_dist_mean` 变差
  - 如果按 surviving 序列整体看, `2 -> 6` 是一个非常重的断口.
- 因此更稳的口径是:
  - 这些图可以作为“实验性剔除对象”.
  - 但当前证据不支持把它们直接设为主线默认剔除素材.
