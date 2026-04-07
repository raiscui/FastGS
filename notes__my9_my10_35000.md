## [2026-03-29 11:27:44 UTC] [Session ID: codex-20260329T112615Z-af86adb4] 笔记: `my9` 当前残留状态与 `my10` 复用口径核查

## 来源

### 来源1: 历史稳定口径回读

- 文件:
  - `EXPERIENCE.md`
  - `task_plan__my6_35000.md`
  - `notes__my6_35000.md`
  - `task_plan__my7_my8_35000.md`
  - `notes__my7_my8_35000.md`
  - `task_plan__my9_35000.md`
  - `notes__my9_35000.md`
- 已验证可复用结论:
  - 这类 `12` 视角生成视频目录, 当前稳定入口是:
    - 只取 `generated_videos/generated_video_0.mp4` 做 RGB
    - 不把 `rendering_4D_maps/merged_mask.mp4` 接成训练 mask
    - `--video-fps 5.333333333333`
    - `nomask`
    - guarded `35000`

### 来源2: `my9` 当前落盘状态核查

- 路径:
  - `data/my9_colmap_fastgs`
  - `output/my9_nomask_v1`
- 已观察到的事实:
  - 当前只有:
    - `input = 324`
    - `distorted/database.db`
  - 仍缺:
    - `images/`
    - `sparse/0/`
    - `checkpoints/`
    - `videos/`
- 旧自动接力脚本:
  - `/tmp/fastgs_logs/my9_pipeline_20260328_1714.sh`
  - 脚本逻辑要求 `images=324` 与 `sparse_files>=5` 后才会继续训练
- 当前机器上没有观察到仍在运行的 `my9` / `my10` 相关训练或渲染进程

### 来源3: `my10` 静态结构与最小动态验证

- 路径:
  - `/root/autodl-fs/my10`
- 已观察到的事实:
  - 存在 `0..11` 共 `12` 个视角目录
  - 每个视角目录都包含:
    - `generated_videos/generated_video_0.mp4`
    - `rendering_4D_maps/merged_mask.mp4`
  - 顶层也有 `shared/`, 但这与 `my9` 的额外顶层目录形态一致, 不影响现有 RGB 发现规则
- 视频元信息:
  - `width=1280`
  - `height=720`
  - `avg_frame_rate=16/1`
  - `nb_frames=81`
  - `duration=5.063000`
- 最小动态抽帧结果:
  - `5.333333333333 fps -> 27` 帧

## 综合发现

### 现象
- `my10` 与 `my5` 到 `my9` 的数据结构和时间基准一致.
- `my9` 当前不是“训练失败后留下了完整模型”, 而是“只跑了一半的 `prepare` 现场”.

### 当前主假设
- `my10` 可以直接沿用既有稳定口径.
- `my9` 更适合清理受控目录后重新 `prepare`, 而不是把半截 `distorted/database.db` 当成可继续的可靠锚点.

### 最强备选解释
- `my9` 的半截状态也可能只是会话中断造成的, 重新 `prepare` 未必说明数据本身有问题.

### 当前结论
- 这次最稳的执行顺序是:
  - 先重跑 `my9 prepare`
  - 再让 guarded 链接管 `my9 train/render`
  - 最后用同一套口径处理 `my10`

## [2026-03-29 11:31:47 UTC] [Session ID: codex-20260329T112615Z-af86adb4] 笔记: `my9` 顺序自动接力链的真实启动证据

## 来源

### 来源1: 顺序自动接力脚本

- 路径:
  - `/tmp/fastgs_logs/my9_my10_pipeline_20260329_112744.sh`
- 关键策略:
  - 顺序执行 `my9 -> my10`
  - 每套数据都走:
    - `prepare --overwrite`
    - guarded `1000` 步分段训练到 `35000`
    - `render --video-iterations 35000 --video-sets both`
  - guarded 训练参数与 `my5/my6/my7` 保持一致:
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

### 来源2: PTY 会话与总日志

- PTY Session:
  - `34295`
- 总日志:
  - `/tmp/fastgs_logs/my9_my10_pipeline_20260329_112744.log`
- 已观察到的真实输出:
  - `===== my9: prepare start =====`
  - 自动回退到:
    - `/home/rais/.local/opt/colmap-env/bin/colmap`
  - `12` 路视频按 `5.333333333333 fps` 完成重抽帧
  - `feature_extractor` 推进到 `324/324`
  - 进入:
    - `INFO: Running feature matching`
    - `Processing block [1/7, 1/7]`

## 综合发现

### 现象
- `my9` 现在不是停留在旧的半截目录上.
- 当前是一次新的、受控的真实 `prepare` 执行.

### 当前结论
- 旧 `my9` 半截现场已经被本轮 `--overwrite` 接管.
- 当前最重要的是继续观察 `matcher` 和 `mapper` 是否稳定推进.
