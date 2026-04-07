# 任务计划: 复用 `my5/my6/my7` 口径处理 `my9` 与 `my10`

## [2026-03-29 11:27:44 UTC] [Session ID: codex-20260329T112615Z-af86adb4] [记录类型]: 新支线建档

### 目标
- 按 `my5/my6/my7` 已验证的稳定训练方式和配置, 处理:
  - `/root/autodl-fs/my9`
  - `/root/autodl-fs/my10`
- 为两套数据分别完成:
  - `COLMAP -> FastGS prepare`
  - guarded `35000` 分段训练
  - `train/test` 视频导出
  - `3DGS ply` 导出

### 两种方向
- 方案A(更稳, 最佳):
  - 先核对 `my9` 当前残留状态.
  - 再核对 `my10` 是否与前几套数据同构.
  - 用已验证过的 guarded 自动接力链, 顺序完成 `my9` 和 `my10`.
- 方案B(更快, 先能用):
  - 直接并行启动 `my9` 和 `my10`.
  - 中间尽量少检查, 更依赖脚本和当前机器资源稳定性.

### 当前决定
- 本轮先采用方案A.
- 原因:
  - `my9` 已经留下一个“只有 `input=324` 的半截现场”, 需要先收敛状态.
  - 当前机器历史上已经出现过随机 CUDA 非法访问, 并行长跑会提高排障复杂度.
  - 顺序 guarded 执行更符合“先做对, 再做快”的目标.

### 阶段
- [x] 阶段1: 回读 `my5` 到 `my9` 的可复用口径与历史证据
- [x] 阶段2: 核对 `my9` / `my10` 输入结构与最小动态抽帧结果
- [ ] 阶段3: 重新启动并完成 `my9 prepare`
- [ ] 阶段4: 完成 `my9` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 启动并完成 `my10 prepare`
- [ ] 阶段6: 完成 `my10` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写 `notes/WORKLOG`, 收尾交付

### 关键问题
1. `my9` 当前这份半截数据目录, 是不是足以直接继续, 还是应该按 `--overwrite` 重新 `prepare`?
2. `my10` 是否和 `my5` 到 `my9` 一样, 应继续走:
   - `nomask`
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
3. 两套数据是否应该并行执行, 还是顺序 guarded 更稳?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `my10` 已经存在, 并且与 `my5` 到 `my9` 一样都有 `0..11/generated_videos/generated_video_0.mp4`.
  - `my10/0/generated_video_0.mp4` 的动态证据是:
    - `1280x720`
    - `16 fps`
    - `81` 帧
    - `duration=5.063s`
    - `5.333333333333 fps -> 27` 帧
  - `my9` 当前只落盘到:
    - `data/my9_colmap_fastgs/input = 324`
    - `data/my9_colmap_fastgs/distorted/database.db`
  - 但 `my9` 仍缺:
    - `data/my9_colmap_fastgs/images`
    - `data/my9_colmap_fastgs/sparse/0`
    - `output/my9_nomask_v1/*`
- 当前主假设:
  - `my10` 可以直接复用 `my5/my6/my7` 的稳定口径.
  - `my9` 当前最正确的动作不是强行续用半截现场, 而是用 `--overwrite` 重跑 `prepare`, 再重新挂 guarded 接力.
- 最强备选解释:
  - `my9` 也可能只是旧 `prepare` 仍在别处运行, 或者曾经被外部中断, 半截现场不一定代表数据有问题.
- 推翻主假设的证据:
  - 如果重新 `prepare` 的 `my9` 立刻在同一位置再次失败.
  - 或者 `my10` 在 `prepare` 早段就暴露与 `my5` 到 `my9` 明显不同的错误形态.

### 当前状态
- 当前进入阶段3.
- 下一步先为 `my9` / `my10` 启动顺序 guarded 自动接力链, 并验证 `my9 prepare` 已经真正进入执行态.

## [2026-03-29 11:31:47 UTC] [Session ID: codex-20260329T112615Z-af86adb4] [记录类型]: `my9` 顺序接力链已启动, `prepare` 已推进到 matcher

### 进度更新
- [x] 阶段1: 回读 `my5` 到 `my9` 的可复用口径与历史证据
- [x] 阶段2: 核对 `my9` / `my10` 输入结构与最小动态抽帧结果
- [ ] 阶段3: 重新启动并完成 `my9 prepare`
- [ ] 阶段4: 完成 `my9` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 启动并完成 `my10 prepare`
- [ ] 阶段6: 完成 `my10` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写 `notes/WORKLOG`, 收尾交付

### 已执行动作
- 已启动顺序自动接力会话:
  - PTY Session: `34295`
  - 脚本: `/tmp/fastgs_logs/my9_my10_pipeline_20260329_112744.sh`
  - 总日志: `/tmp/fastgs_logs/my9_my10_pipeline_20260329_112744.log`
- 当前执行顺序:
  - 先 `my9`
  - `my9` 全链路完成后再切 `my10`

### 已验证结论
- `my9` 当前已经完成:
  - 受控目录清理
  - `12` 路视频重新抽帧
  - `feature_extractor 324/324`
- `my9 prepare` 最近已推进到:
  - `exhaustive_matcher`
  - `Processing block [1/7, 1/7]`

### 当前状态
- 当前仍处于阶段3.
- 下一步继续观察 `my9` 是否顺利跨过 `matcher -> mapper -> undistort`.

## [2026-03-29 11:35:07 UTC] [Session ID: codex-20260329T112615Z-af86adb4] [记录类型]: `my9 matcher` 持续推进, 当前未见停滞

### 进度更新
- [x] 阶段1: 回读 `my5` 到 `my9` 的可复用口径与历史证据
- [x] 阶段2: 核对 `my9` / `my10` 输入结构与最小动态抽帧结果
- [ ] 阶段3: 重新启动并完成 `my9 prepare`
- [ ] 阶段4: 完成 `my9` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 启动并完成 `my10 prepare`
- [ ] 阶段6: 完成 `my10` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写 `notes/WORKLOG`, 收尾交付

### 已验证结论
- 当前 `my9` 还没有进入 `images/` 与 `sparse/0` 导出阶段, 所以阶段3尚未完成.
- 但 `matcher` 已经从:
  - `Processing block [1/7, 1/7]`
  连续推进到:
  - `Processing block [1/7, 6/7]`
- GPU 当前占用约 `611 MiB`, 更符合 `COLMAP` 匹配阶段的资源画像, 还没有切到 FastGS 训练.

### 当前状态
- 当前仍处于阶段3.
- 下一步继续让顺序接力链在后台推进, 等 `my9 prepare` 真正落出 `images=324` 与 `sparse/0`.
