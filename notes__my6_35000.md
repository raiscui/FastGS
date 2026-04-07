## [2026-03-28 08:47:34 UTC] [Session ID: 5957] 笔记: `my6` 静态结构与 `my5` 复用口径

## 来源

### 来源1: `my5` 既有结果回读

- 文件:
  - `WORKLOG.md`
  - `task_plan.md`(续档前)
  - `cmd.md`
  - `EXPERIENCE.md`
- 关键要点:
  - `my5` 最终使用的是 `nomask` 路线.
  - 最终稳定口径是:
    - `--video-fps 5.333333333333`
    - `-r 1`
    - `--densification_interval 500`
    - `--opacity_reset_interval 3000`
    - `--densify_until_iter 15000`
    - `--position_lr_max_steps 35000`
    - `--loss_thresh 0.1`
    - `--grad_thresh 0.0002`
    - `--grad_abs_thresh 0.0012`
    - `--highfeature_lr 0.005`
    - `--lowfeature_lr 0.0025`
    - `--dense 0.001`
    - `--mult 0.5`
    - `--optimizer_type default`
    - `--eval`

### 来源2: `my6` 目录静态核查

- 路径:
  - `/root/autodl-fs/my6`
- 已观察到的事实:
  - 存在 `0..11` 共 `12` 个视角目录.
  - 每个视角目录下都存在:
    - `generated_videos/generated_video_0.mp4`
    - `rendering_4D_maps/merged_mask.mp4`
    - 多个不应送进 COLMAP 的辅助视频
  - 结构层面与 `my5` 属于同一输入类型.

## 综合发现

### 现象
- `my6` 和 `my5` 的目录形态是一致的.
- 因此它更像“同一类数据的新样本”, 不是另一种新格式.

### 当前主假设
- `my5` 的稳定口径可以直接迁移到 `my6`.

### 当前还缺的证据
- 还没有做 `my6` 的单视角抽帧动态验证.
- 还没有拿到 `my6` 的真实 `prepare` 日志.

### 当前结论
- 在没有新反证之前, `my6` 的最合理起步方式就是完整复用 `my5` 的 `nomask + 35000` 训练链.

## [2026-03-28 08:51:10 UTC] [Session ID: 5957] 笔记: `my6` 的单视角抽帧动态验证

## 来源

### 来源1: 单视角抽帧验证

- 命令:
  - `ffmpeg -i /root/autodl-fs/my6/0/generated_videos/generated_video_0.mp4 -vf fps=5.333333333333 ...`
- 结果:
  - `count=27`

### 来源2: 视频元信息核查

- 命令:
  - `ffprobe ... /root/autodl-fs/my6/0/generated_videos/generated_video_0.mp4`
- 结果:
  - `width=1280`
  - `height=720`
  - `avg_frame_rate=16/1`
  - `duration=5.062500`
  - `nb_frames=81`

## 综合发现

### 现象
- `my6` 的单视角视频时长和帧率口径与 `my5` 一致.
- 用 `5.333333333333 fps` 抽帧时, 会稳定落到 `27` 帧.

### 当前结论
- `my5` 的 `1/3` 图量策略可以原样迁移到 `my6`.
- 对 `12` 个视角而言, 这意味着 `my6` 也应落在 `324` 张总图量附近.

## [2026-03-28 17:53:30 UTC] [Session ID: 5957] 笔记: `my6 prepare` 的真实动态结果

## 来源

### 来源1: `prepare` 主日志

- 日志文件:
  - `/tmp/fastgs_logs/my6_prepare_20260328_0854.log`
- 关键输出:
  - `Discovered 12 video(s)`
  - `feature_extractor` 跑到 `324/324`
  - `exhaustive_matcher` 完成, 耗时 `40.102 [minutes]`
  - `mapper` 持续注册, 后段可见 `num_reg_frames` 推到 `315+`
  - `image_undistorter` 完成 `324/324`
  - 末尾出现 `Done.`

### 来源2: 产物侧核查

- 命令结果:
  - `data/my6_colmap_fastgs/images` 下有 `324` 张图
  - `data/my6_colmap_fastgs/sparse/0` 下存在:
    - `cameras.bin`
    - `frames.bin`
    - `images.bin`
    - `points3D.bin`
    - `rigs.bin`

## 综合发现

### 现象
- `my6` 的 `prepare` 主链路已经完整跑通.
- 中间虽然出现过 `Gauge` 与 `Eigen failure` 警告, 但没有阻断注册和最终导出.

### 当前结论
- 现在 `data/my6_colmap_fastgs` 已经是可直接喂给 FastGS 的训练根目录.
- 下一步不需要再纠结数据入口, 直接进入 `35000` 训练阶段即可.

## [2026-03-28 17:54:10 UTC] [Session ID: 5957] 笔记: `my6` 全量直跑训练在约 `7940` 处失败

## 来源

### 来源1: 训练日志

- 日志文件:
  - `/tmp/fastgs_logs/my6_train_20260328_1754.log`
- 关键现象:
  - 训练正常进入迭代
  - 在全局约 `7940` 左右退出
  - 抛出:
    - `torch.AcceleratorError: CUDA error: an illegal memory access was encountered`

### 来源2: 产物目录核查

- 当前 `output/my6_nomask_v1` 里只有:
  - `cameras.json`
  - `cfg_args`
  - `input.ply`
- 没有 checkpoint 与 point cloud 分段产物
- 说明这次失败发生在首个保存点之前

### 来源3: 项目历史经验回读

- `EXPERIENCE.md` 与历史 `notes/task_plan` 都表明:
  - 这套 FastGS 在当前机器上曾多次出现随机 `illegal memory access`
  - `1000` 步分段 + checkpoint + 换 seed 已被动态验证为有效交付策略

## 综合发现

### 现象
- `my6` 的错误形态与项目历史里的随机 CUDA 非法访问高度相似.

### 当前主假设
- 当前更像是运行时稳定性问题, 不像数据入口或 `prepare` 逻辑错误.

### 当前还缺的证据
- 还没有拿到“同一数据在分段训练下是否稳定”的动态结果.
- 因此还不能把“长跑不稳定”升级成最终根因结论.

### 当前结论
- 现阶段最正确的动作不是立刻改代码.
- 先用历史已验证的 guarded 分段训练策略做最小证伪:
  - 如果分段能推进并落稳定锚点, 说明当前更适合走交付型守护方案.

## [2026-03-28 10:04:49 UTC] [Session ID: codex-20260328-1002] 笔记: `my6` guarded 训练与 `35000` 渲染交付验证

## 来源

### 来源1: guarded 训练日志尾部核查

- 日志文件:
  - `/tmp/fastgs_logs/my6_guarded_train_20260328_1800.log`
- 关键输出:
  - `[ITER 35000] Saving Gaussians`
  - `[ITER 35000] Saving Checkpoint`
  - `Training complete.`
  - `[guard-my6] completed through 35000`

### 来源2: 产物路径核查

- 已确认文件:
  - `output/my6_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my6_nomask_v1/point_cloud/iteration_35000/point_cloud.ply`
  - `output/my6_nomask_v1/videos/train_iter35000.mp4`
  - `output/my6_nomask_v1/videos/test_iter35000.mp4`
- 文件尺寸:
  - `ckpt_35000.pth` = `53,873,141` bytes
  - `point_cloud.ply` = `18,452,234` bytes
  - `train_iter35000.mp4` = `6,248,120` bytes
  - `test_iter35000.mp4` = `1,523,920` bytes

### 来源3: 视频元信息核查

- 命令:
  - `ffprobe -show_entries format=duration,size ... train_iter35000.mp4`
  - `ffprobe -show_entries format=duration,size ... test_iter35000.mp4`
- 结果:
  - `train_iter35000.mp4`:
    - `duration=11.792000`
    - `size=6248120`
  - `test_iter35000.mp4`:
    - `duration=1.709000`
    - `size=1523920`

## 综合发现

### 现象
- guarded 分段训练已经实际推进到 `35000`, 不是停在中间段.
- 渲染阶段也已经完整跑完 train/test 两套图片与 mp4 封装.

### 已验证结论
- `my6` 已按 `my5` 同口径完成:
  - `nomask`
  - `35000` 训练
  - `3DGS ply` 导出
  - `train/test` 视频导出
- 本轮不需要再续训, 也不需要重跑渲染.

### 当前交付判断
- 用户要求的核心产物已经齐全.
- 后续若要继续, 更像是做质量评估或追加指标统计, 而不是补救当前交付缺口.
