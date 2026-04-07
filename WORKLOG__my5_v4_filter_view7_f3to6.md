## [2026-03-27 19:20:12 UTC] [Session ID: 64a33e57-aa0e-4613-b103-207945436fa5] 任务名称: 完成 `my5` `v4` 筛帧对照的正式整理与结论回写

### 任务内容
- 继续整理 `view 7 frame 3~6` 筛帧对照 `v4`.
- 明确它到底有没有把 `view 7` 剩余帧修顺.
- 把结果正式写回报告与汇总资产, 并把取证过程落到支线文件.

### 完成过程
- 先新建支线上下文:
  - `task_plan__my5_v4_filter_view7_f3to6.md`
  - `notes__my5_v4_filter_view7_f3to6.md`
  - `WORKLOG__my5_v4_filter_view7_f3to6.md`
  - `EPIPHANY_LOG__my5_v4_filter_view7_f3to6.md`
- 再复查 `v4` 原始资产:
  - `pycolmap_run_summary.json`
  - `pose_continuity_data.json`
  - `comparison_summary.json`
- 中途修正了一个分析口径错误:
  - 一开始把 `comparison_summary.json` 误按 `variants` 层读取
  - 复查后确认真实结构是:
    - `views`
    - `pairs`
    - `local_camera_params`
    - `reconstruction_summary`
- 然后补做了最关键的公平比较:
  - 不再拿 `widecontext` 的完整 `12` 帧去比 `v4` 的 `8` 帧
  - 而是从 `widecontext` 中抽同样 surviving frames:
    - `{1,2,7,8,9,10,11,12}`
  - 并只统计真实 contiguous transitions:
    - `2,8,9,10,11,12`
- 最后完成正式落盘:
  - 更新 [my5_local_colmap_compare_20260328.md](/root/autodl-tmp/home/rais/FastGS/specs/my5_local_colmap_compare_20260328.md)
  - 更新 [comparison_summary.json](/root/autodl-tmp/home/rais/FastGS/specs/my5_local_colmap_compare_assets/comparison_summary.json)
    - 新增 `fair_subset_compare`
  - 用 `beautiful-mermaid-rs` 校验文内 `2` 个 mermaid block
  - 用 `python3 -m json.tool` 校验 JSON 结构

### 总结感悟
- 这轮最重要的收获不是“又补了一版实验”, 而是把删帧实验的比较口径修正到了可信状态.
- 当前 `v4` 的真实结论不是“删帧成功”, 而是:
  - rotation 类指标略平
  - 但 step、更低点支持和更差的 pair distance 同时出现
- 这意味着 `filter_drop_v7_f3to6` 更像反证材料, 不是可以直接接回主线的默认预处理方案.
