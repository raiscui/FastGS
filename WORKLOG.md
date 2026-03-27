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

## [2026-03-27 10:27:38] [Session ID: 80800] 任务名称: 回滚 `merged_mask.mp4` 的错误训练 mask 语义并接上 `my5` 首轮无 mask 训练

### 任务内容
- 修正 `my5` 场景里 `rendering_4D_maps/merged_mask.mp4` 的使用口径.
- 保留已经在跑的 COLMAP prepare, 同时避免后续 FastGS 训练误吃深度辅助 mask.

### 完成过程
- 回读了当前主线记录、`cmd.md`、相关代码与真实后台状态.
- 确认 `prepare` 仍在 `exhaustive_matcher`, 因此错误尚未污染训练结果.
- 修改代码:
  - `convert.py`
    - 撤掉 `merged_mask.mp4 -> masks/` 的默认接线
  - `scene/dataset_readers.py`
    - 自动 mask 探测改为“目录存在且非空”才启用
  - `scripts/run_lyra_colmap_fastgs.sh`
    - 同步收紧自动 mask 识别条件, 并修正文案
  - `tests/test_convert.py`
    - 改成验证 `merged_mask.mp4` 不再介入训练抽帧计划
  - `tests/test_mask_loading.py`
    - 新增空 `masks/` 不自动启用的回归测试
- 完成验证:
  - `python3 -m py_compile convert.py scene/dataset_readers.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m unittest tests.test_convert tests.test_mask_loading`
- 完成运行态处理:
  - 把 `data/my5_colmap_fastgs/masks` 挪到 `depth_masks_from_merged_mask_20260327_102621`
  - 保留 `972` 张深度辅助 mask 帧供后续深度链路参考
  - 新启动无 mask 训练等待器 `96836`, 等 `prepare` 完成后自动起 `output/my5_nomask_v1`

### 总结感悟
- 这次真正该修的不是“mask 缺不缺”, 而是“输入语义有没有被误分类”.
- 对自动发现类入口, 宁可少接一条语义不确定的默认行为, 也不要把不同任务的中间产物共用到同一个 `masks/` 约定里.
