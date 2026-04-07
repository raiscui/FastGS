## [2026-03-27 21:29:13 UTC] [Session ID: unknown-env-missing] 任务名称: `my5 v6` 删 `view 7` 高 rotation 帧验证

### 任务内容
- 复核 `view 7 frame 3/4/5` 删除后的 COLMAP 连续性表现.
- 补跑 `v6` 的 `contiguous` 与 `all` 两套 pose continuity 资产.
- 对照 `v5_conservative_mapper` 与“相同 surviving 子集”的公平基线.

### 完成过程
- 读取并确认了 `v6` 的输入清单:
  - 实际删除的是 `view 7 frame 3/4/5`
  - 剩余总数 `45` 张
- 跑完并落盘:
  - [pose_continuity_data.json](/root/autodl-tmp/home/rais/FastGS/specs/my5_local_pose_compare_v6_filter_view7_highrot_assets/pose_continuity_data.json)
  - [pose_continuity_data.json](/root/autodl-tmp/home/rais/FastGS/specs/my5_local_pose_compare_v6_filter_view7_highrot_assets_all/pose_continuity_data.json)
- 额外核对了 `v5` 和 `v6` 的 `cameras.bin`:
  - 两者都保持 `SIMPLE_PINHOLE [592.1701367226717, 640, 360]`
  - 这说明本轮差异不是焦距漂移造成的.
- 做了公平 surviving 子集对照:
  - `v5` 用 `{1,2,6,7,8,9,10,11,12}` 重新计算了模拟删帧口径
  - 把 `contiguous` 和 `all` 拆开看, 避免把 `2 -> 6` 的断口误当邻帧平滑

### 总结感悟
- 这轮最明确的结论不是“删掉高 rotation 帧就变好”.
- 更准确的是:
  - rotation 会略微变小
  - 但 translation、pair distance、点支持没有一起变好
  - surviving 序列还会引入一个很重的 `2 -> 6` 断口
- 所以这版适合作为对照实验结果保留.
- 但不适合直接升格成主线默认筛图策略.
