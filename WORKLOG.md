## [2026-03-27 17:55:35] [Session ID: 28616] 任务名称: 支持 `my5` 多镜头视频目录走 `COLMAP -> FastGS`

### 任务内容
- 让现有 `COLMAP -> FastGS` 脚本真正支持 `/root/autodl-fs/my5` 这种多镜头生成视频目录.
- 保持训练口径向 `cmd.md` 中 `my4_mask_guarded_v4` 靠齐, 尤其是 mask 训练入口和正式训练参数链路.

### 完成过程
- 先回读主线六文件, 因为默认上下文文件超过 1000 行, 先执行了续档与持续学习:
  - 归档主线旧 `task_plan.md`、`notes.md`、`WORKLOG.md`
  - 新增 `EXPERIENCE.md`
  - 在 `AGENTS.md` 补长期知识索引
- 然后定位 `my5` 与旧 `rgb/*.mp4` 布局的真实差异:
  - `generated_videos/generated_video_0.mp4`
  - `rendering_4D_maps/merged_mask.mp4`
  - 以及一批不该喂给 COLMAP 的辅助视频
- 接着完成代码改造:
  - `convert.py`
    - 优先发现 `generated_videos`
    - 自动把 `merged_mask.mp4` 配成同名 mask 帧
    - 为 COLMAP 3.x / 4.x 动态选择 GPU 选项名
  - `scripts/run_lyra_colmap_fastgs.sh`
    - 自动优先读取 `<fastgs-root>/masks`
    - 默认 CUDA COLMAP 路径失效时回退到 PATH `colmap`
  - `tests/test_convert.py`
    - 新增 3 条回归测试
- 最后用真实 `my5` 数据启动 `prepare`, 已确认:
  - 抽出了 `972` 张训练图
  - 抽出了 `972` 张 mask
  - 已进入 COLMAP `feature_extractor` 与 `exhaustive_matcher`

### 总结感悟
- 对这类多镜头生成视频目录, 真正危险的不是“视频太多”, 而是“辅助视频和 RGB 视频混在一起, 但文件扩展名都一样”.
- 最稳的修法不是再造一条新 pipeline, 而是把现有 `convert.py` 的发现规则和抽帧规则补到足够懂业务语义.

### 当前运行态
- COLMAP prepare 正在后台继续跑:
  - 已完成 `feature_extractor`
  - 当前在 `exhaustive_matcher`
- 训练接力也已启动:
  - 一旦 `sparse/0` 产出
  - 自动开始 `output/my5_mask_guarded_v1` 的正式 FastGS 训练
