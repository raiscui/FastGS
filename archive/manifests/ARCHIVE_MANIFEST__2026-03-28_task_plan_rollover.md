# 主线 `task_plan.md` 续档清单

## 续档时间
- 2026-03-28 08:47:34 UTC
- Session ID: 5957

## 触发原因
- 原主线 `task_plan.md` 已达到 `1000` 行.
- 按仓库规则, 后续若继续直接追加, 会超过主线上下文文件的上限.
- 本轮同时要启动新的 `my6` 训练任务, 继续把状态写进旧文件会让主线索引和支线执行记录混在一起.

## 本轮检索覆盖
- 默认组六文件:
  - `task_plan.md`(续档前旧文件)
  - `notes.md`
  - `WORKLOG.md`
  - `LATER_PLANS.md`
  - `EPIPHANY_LOG.md`
- 当前根目录活跃支线:
  - `task_plan__my5_v6_filter_view7_highrot.md`
  - `notes__my5_v6_filter_view7_highrot.md`
  - `WORKLOG__my5_v6_filter_view7_highrot.md`
  - `LATER_PLANS__my5_v6_filter_view7_highrot.md`

## 六文件摘要
- 任务目标:
  - 近期主线主要围绕 `my5` 的 `35000` 训练闭环, 以及后续的 worst-view / COLMAP 位姿诊断.
- 关键决定:
  - `my5` 的稳定复现口径已经明确为:
    - `--video-fps 5.333333333333`
    - 无训练 mask
    - `-r 1`
    - `--densification_interval 500`
    - `--position_lr_max_steps 35000`
    - `--eval`
  - `35000` 的最终交付链路已经验证可复用:
    - checkpoint / ply
    - render
    - mp4
- 关键发现:
  - `my5` 的质量瓶颈更像 `view 7` 的 COLMAP 位姿问题, 不是单纯训练步数不足.
- 实际变更:
  - `EXPERIENCE.md` 已补入可复用的 `my5` 35000 训练口径, 方便后续直接迁移到同类目录.
- 支线组摘要:
  - `__my5_v6_filter_view7_highrot` 仍是活跃支线, 当前主题是继续围绕 `view 7` 做更强筛帧对照.
- 暂缓事项:
  - `my5` 不建议继续盲目堆训练步数, 优先继续位姿与素材质量排查.
- 重大风险 / 规律:
  - 对这种多视角生成视频目录, 真正要避免的是把 `merged_mask.mp4` 误接成训练 mask.

## 归档动作
- 已归档:
  - `task_plan.md` -> `archive/default_history/task_plan_2026-03-28_084734.md`
- 未归档且继续保留:
  - `notes.md`
  - `WORKLOG.md`
  - `LATER_PLANS.md`
  - `EPIPHANY_LOG.md`
  - `task_plan__my5_v6_filter_view7_highrot.md` 等活跃支线文件

## 行动建议
- 当前最值得推进的新任务是把 `my5` 已验证口径平移到 `my6`.
- 执行顺序建议保持:
  1. 先做 `my6` 的最小抽帧验证.
  2. 再跑 `COLMAP -> FastGS` 的 `35000` 训练主链.
  3. 训练结束后立即核对 `35000` 的 `ply` 与 train/test 视频是否落盘.
