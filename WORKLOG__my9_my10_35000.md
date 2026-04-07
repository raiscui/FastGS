## [2026-03-29 11:31:47 UTC] [Session ID: codex-20260329T112615Z-af86adb4] 任务名称: 启动 `my9 -> my10` 顺序 guarded 自动接力链

### 任务内容
- 按 `my5/my6/my7` 已验证的训练方式和配置, 为:
  - `/root/autodl-fs/my9`
  - `/root/autodl-fs/my10`
  启动顺序执行的 `prepare -> guarded train -> render` 全链路.
- 在真正把长任务交给后台继续跑之前, 先核对:
  - `my10` 的输入结构和抽帧口径
  - `my9` 的旧半截现场是否应该重跑
  - 新接力脚本是否真的进入了 `my9 prepare`

### 完成过程
- 回读了 `EXPERIENCE.md`、`my6` / `my7` / `my8` / `my9` 历史支线, 收敛出当前稳定口径:
  - `nomask`
  - `--video-fps 5.333333333333`
  - guarded `35000`
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
- 确认了 `my10` 与前几套数据同构:
  - `12` 视角
  - `generated_videos/generated_video_0.mp4`
  - `16 fps / 81 帧 / 5.063s`
  - `5.333333333333 fps -> 27` 帧
- 确认了 `my9` 当前只有半截 `prepare` 现场:
  - `input=324`
  - 但没有 `images/` 和 `sparse/0`
- 因此没有强行续旧现场, 而是新建顺序自动接力脚本:
  - `/tmp/fastgs_logs/my9_my10_pipeline_20260329_112744.sh`
  - 总日志:
    - `/tmp/fastgs_logs/my9_my10_pipeline_20260329_112744.log`
  - PTY Session:
    - `34295`
- 已经动态验证到:
  - `my9` 重抽帧完成
  - `feature_extractor 324/324`
  - `exhaustive_matcher` 至少推进到 `Processing block [1/7, 4/7]`

### 总结感悟
- 这次真正需要先修正的不是训练参数, 而是任务编排方式.
- 对“已经留下半截现场”的长任务, 最稳的不是赌它能否继续, 而是把受控目录重新接管, 再把完整自动接力链挂起来.
- 当前这条 `my9 -> my10` 顺序链已经真实跑起来了, 后续只需要继续观察 `my9 prepare` 进入 `mapper`、再推进到训练即可.
