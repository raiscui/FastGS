# 任务计划: 支持 `my5` 多镜头视频目录走 `COLMAP -> FastGS`

## [2026-03-27 09:41:03] [Session ID: 28616] [记录类型]: 新任务建档

### 目标
- 让现有脚本支持 `/root/autodl-fs/my5` 这种“多视角目录 + 每视角生成视频 + 每视角 mask 视频”的输入结构.
- 先按 `cmd.md` 中 `my4_mask_guarded_v4` 的参数口径, 跑通一版 `COLMAP -> FastGS / 3DGS` 训练.
- 优先做最正确的入口改造, 不要求这轮就把所有调优都做完.

### 两种方向
- 方案A(不惜代价, 最佳):
  - 让 `convert.py` 直接识别 `generated_videos/*.mp4` 与配套 `merged_mask.mp4`.
  - 让 `run_lyra_colmap_fastgs.sh` 自动接住这类目录, 产出可直接训练的 `images + sparse/0 + masks`.
- 方案B(先能用, 后面再优雅):
  - 新增一个只面向 `my5` 的 wrapper 或预处理分支.
  - 先把 `generated_videos` 和 `merged_mask` 抽成帧图与 mask 图, 再复用现有训练入口.

### 阶段
- [x] 阶段1: 回读上下文, 做持续学习与续档
- [x] 阶段2: 核对 `my5` 目录结构与 `cmd.md` 参数口径
- [ ] 阶段3: 设计并实现输入发现 / mask 抽帧改造
- [ ] 阶段4: 用最小验证确认 `prepare` 产物正确
- [ ] 阶段5: 按 `my4_mask_guarded_v4` 参数启动训练并记录结果

### 关键问题
1. `/root/autodl-fs/my5` 里真正该给 COLMAP 的视频, 是不是只有 `*/generated_videos/generated_video_0.mp4`?
2. `rendering_4D_maps/merged_mask.mp4` 是否与 RGB 视频逐帧对齐, 能否直接抽成训练 mask?
3. 改动最稳的挂载点是在 `convert.py`, 还是只在 wrapper 层做结构归一化?
4. 如何保证多视角 RGB 帧名和 mask 帧名严格一一对应?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `/root/autodl-fs/my5` 每个视角目录下同时存在:
    - `generated_videos/generated_video_0.mp4`
    - `rendering_4D_maps/merged_mask.mp4`
    - 以及多种深度 / 背景 / 4D map 视频
  - 现有 `convert.py` 会在缺少 `rgb/` 时退到全局递归发现视频.
- 当前主假设:
  - 如果不改发现规则, 现有流程会把 `depth` / `background` / `mask` 之类的视频一并送进 COLMAP, 导致输入脏掉.
- 备选解释:
  - 即便只抽对了 RGB 视频, 训练阶段如果没有同步准备 mask 图, 也无法真正按 `my4_mask_guarded_v4` 的口径开跑.
- 推翻主假设的证据:
  - 如果当前发现逻辑已经只会命中 `generated_videos`, 那就不需要改视频发现规则, 只要补 mask 入口.

### 当前状态
- 目前在阶段3.
- 下一步先实现:
  - `generated_videos` 优先发现
  - 可选的并行 mask 视频抽帧
  - wrapper 对 `my5` 的默认 mask 目录识别

## [2026-03-27 17:55:35] [Session ID: 28616] [记录类型]: 代码改造完成, 进入真实动态验证

### 进度更新
- [x] 阶段3: 设计并实现输入发现 / mask 抽帧改造
- [ ] 阶段4: 用最小验证确认 `prepare` 产物正确
- [ ] 阶段5: 按 `my4_mask_guarded_v4` 参数启动训练并记录结果

### 已完成的实现
- `convert.py`
  - 新增 `generated_videos` 优先发现, 避免误扫 `rendering_4D_maps/*.mp4`
  - 新增 VerseCrafter 风格 `merged_mask.mp4` 自动配对
  - 新增 RGB / mask 同步抽帧, 输出到:
    - `input/*.jpg`
    - `masks/*.png`
  - 新增 COLMAP 3.x / 4.x GPU 参数兼容层
- `scripts/run_lyra_colmap_fastgs.sh`
  - 训练阶段自动优先识别 `<fastgs-root>/masks`
  - 新增默认 COLMAP 路径缺失时回退到 PATH `colmap` 的逻辑
- 测试:
  - `tests/test_convert.py` 已补 3 条回归测试

### 动态证据
- 静态验证:
  - `python3 -m py_compile convert.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m unittest tests.test_convert`
- 真实 `my5` 验证:
  - `prepare` 已成功走到:
    - `feature_extractor`
    - `exhaustive_matcher`
  - 已确认中间产物:
    - `input`: 972 张
    - `masks`: 972 张
    - `distorted/database.db`: 已生成, 当前约 289 MB

### 当前判断
- `my5` 这种多镜头生成视频目录已经被脚本正确识别.
- 当前剩余未完成项不再是“结构支持”, 而是等待真实 COLMAP prepare 跑完, 再接正式训练.

## [2026-03-27 17:56:30] [Session ID: 28616] [记录类型]: 已串联后台训练接力

### 新进展
- 已启动真实 `prepare` 会话, 当前已进入 `exhaustive_matcher`.
- 已额外启动训练接力:
  - 等 `data/my5_colmap_fastgs/sparse/0` 出现后
  - 自动按 `my4_mask_guarded_v4` 参数启动 `output/my5_mask_guarded_v1`

### 当前状态
- [x] 阶段4: 已有真实动态证据证明 prepare 主链路正在正常推进
- [ ] 阶段5: 正在等待 COLMAP 完成后自动进入正式训练
