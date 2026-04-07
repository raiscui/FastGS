## [2026-03-27 19:20:12 UTC] [Session ID: 64a33e57-aa0e-4613-b103-207945436fa5] 主题: 删帧实验必须用 fair surviving-subset 对照, 不能直接拿完整基线均值比较

### 发现来源
- 在整理 `my5` 的 `filter_drop_v7_f3to6` 对照时发现.
- 如果直接把 `widecontext` 的 `12` 帧均值拿去对 `v4` 的 `8` 帧均值, 会天然把已删除的高抖动帧混进基线.

### 核心问题
- 这种比较会放大“删掉坏帧后均值变好”的错觉.
- 它并不能回答真正的问题:
  - 剩下来的帧有没有更健康.

### 为什么重要
- 这是删帧类 COLMAP 对照的通用量尺问题.
- 如果量尺不对, 后续很容易把“样本变少”误判成“几何变好”.

### 未来风险
- 如果以后继续做 `view 7` 或别的机位筛帧实验, 但忘了用 fair surviving-subset 口径, 报告会再次高估删帧收益.

### 当前结论
- 更稳的固定口径应该是:
  - 基线也只取与删帧结果相同的 surviving frames
  - 再只统计其中真实 contiguous transitions
- 在这个口径下, `filter_drop_v7_f3to6` 的真实形态是:
  - rotation 略平
  - 但 step、更低点支持和更差的 pair distance 同时出现

### 后续讨论入口
- 如果后面继续做筛帧:
  - 先看 [comparison_summary.json](/root/autodl-tmp/home/rais/FastGS/specs/my5_local_colmap_compare_assets/comparison_summary.json) 里的 `fair_subset_compare`
  - 再决定新的删帧规则是否值得继续尝试
