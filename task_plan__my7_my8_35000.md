# 任务计划: 复用 `my5/my6` 口径处理 `my7` 与 `my8`

## [2026-03-28 11:48:07 UTC] [Session ID: codex-20260328-1148] [记录类型]: 新支线建档

### 目标
- 按 `/root/autodl-fs/my5` 与 `/root/autodl-fs/my6` 已验证的流程处理 `/root/autodl-fs/my7` 和 `/root/autodl-fs/my8`.
- 为两套数据分别完成:
  - `COLMAP -> FastGS`
  - `35000` 训练
  - `train/test` 视频导出
  - `3DGS ply` 导出

### 两种方向
- 方案A(更稳, 最佳):
  - 先核对 `my7` / `my8` 的动态抽帧结果.
  - 再按数据集分别执行 `prepare -> train -> render`.
  - 每个阶段都核对关键产物, 避免两套长任务互相污染.
- 方案B(更快, 先能用):
  - 直接对两套数据都用同一套脚本参数开跑.
  - 中间只做最低限度检查, 更依赖历史经验和脚本稳定性.

### 当前决定
- 本轮先采用方案A.
- 原因:
  - 用户这次一次性给了两套新数据.
  - 先把输入结构和最小动态证据拿到, 后面才能决定哪些阶段能并行, 哪些必须串行.

### 阶段
- [ ] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [ ] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [ ] 阶段3: 完成 `my7` 的 `prepare`
- [ ] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 关键问题
1. `my7` 和 `my8` 是否都和 `my5/my6` 一样, 只应使用 `generated_videos/generated_video_0.mp4` 作为 RGB 输入?
2. `my5/my6` 已验证的稳定口径是否可以原样迁移:
   - `--video-fps 5.333333333333`
   - 无训练 mask
   - `-r 1`
   - `--densification_interval 500`
   - `--opacity_reset_interval 3000`
   - `--densify_until_iter 15000`
   - `--position_lr_max_steps 35000`
   - `--eval`
3. 两套数据当前是否都还是“全新未处理状态”, 还是其中某一套已经有可复用的中间产物?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `my7` / `my8` 目录结构与 `my5/my6` 一致.
  - `0..11` 共 `12` 个视角目录都包含:
    - `generated_videos/generated_video_0.mp4`
    - `rendering_4D_maps/merged_mask.mp4`
  - 当前 `data/` 与 `output/` 下还没有对应的 `my7` / `my8` 产物目录.
- 当前主假设:
  - `my5/my6` 的稳定 `nomask + 35000` 处理口径可以直接迁移到 `my7` / `my8`.
- 最强备选解释:
  - 虽然结构相同, 但素材质量或时长分布仍可能不同, 导致某一套数据在 `prepare` 或长训练阶段暴露新问题.
- 推翻主假设的证据:
  - 如果最小抽帧验证落不到约 `27` 帧.
  - 或者某一套数据在 `prepare` 阶段就出现不同于 `my5/my6` 的失败形态.

### 当前状态
- 目前在阶段1.
- 下一步先把 `my7` / `my8` 的单视角抽帧动态验证做掉, 再决定两套数据的执行顺序.

## [2026-03-28 11:48:07 UTC] [Session ID: codex-20260328-1148] [记录类型]: 最小动态验证通过, 先转入 `my7 prepare`

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [ ] 阶段3: 完成 `my7` 的 `prepare`
- [ ] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my7` 与 `my8` 的单视角视频元信息都与 `my5/my6` 一致:
  - `16 fps`
  - `81` 帧
  - `1280x720`
  - 时长约 `5.063s`
- 抽帧验证结果:
  - `my7`: `ffmpeg -vf fps=5.333333333333` -> `27` 帧
  - `my8`: `ffmpeg -vf fps=5.333333333333` -> `27` 帧
- 因此两套数据都可以继续沿用:
  - `12 * 27 = 324` 张总图量目标
  - `nomask + 35000` 的既有训练口径

### 当前状态
- 目前进入阶段3.
- 下一步先执行 `my7` 的真实 `prepare`, 目标目录定为:
  - `data/my7_colmap_fastgs`
  - `output/my7_nomask_v1`

## [2026-03-28 13:02:00 UTC] [Session ID: codex-20260328-1148] [记录类型]: `my7 prepare` 仍在进行, 已挂起自动训练接力

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [ ] 阶段3: 完成 `my7` 的 `prepare`
- [ ] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my7 prepare` 已经真实跨过:
  - 抽帧
  - `feature_extractor`
  - `exhaustive_matcher`
- 当前卡在 `colmap mapper`, 但它不是静止:
  - 仍在持续注册新图像
  - 最近一次已观测到 `num_reg_frames=233`
- 同时已经额外挂起一条自动接力链:
  - 等 `my7 prepare` 结束后
  - 自动验证 `images + sparse/0`
  - 自动进入 guarded `35000` 训练
  - 自动导出 `35000` 轮视频

### 当前状态
- 当前真正的耗时点是 `my7 prepare` 的 `mapper`.
- 下一步不是改代码, 而是继续等待 `mapper -> undistort -> 导出` 完成, 然后让自动接力进入训练.

## [2026-03-28 13:46:53 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my7 prepare` 已完成, 训练已推进到 `32000`

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [ ] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my7 prepare` 会话 `32908` 已跑完最终导出:
  - `Undistorting image [324/324]`
  - `Writing reconstruction...`
  - `Writing configuration...`
  - `Writing scripts...`
  - `Done.`
- 自动接力会话 `78972` 已成功接上:
  - 自动校验通过 `images=324`, `sparse_files=5`
  - 已从 `0->1000` 一直推进到更高训练段
- 当前落盘证据表明 `my7` 已至少完成到 `32000`:
  - `output/my7_nomask_v1/checkpoints/ckpt_32000.pth`
  - `output/my7_nomask_v1/point_cloud/iteration_32000/point_cloud.ply`
- `my8` 仍未启动:
  - `data/my8_colmap_fastgs/input = 0`
  - `output/my8_nomask_v1/checkpoints = 0`
  - `output/my8_nomask_v1/videos = 0`

### 当前状态
- 当前进入阶段4.
- 下一步继续等待 `my7` 从 `32000` 跑到 `35000`, 然后自动执行视频导出.
- `my7` 全部产物完成后, 再开始 `my8 prepare`.

## [2026-03-28 13:47:50 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my7` 的 `35000` 训练已完成, 当前进入最终渲染

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [ ] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my7` 的最终训练产物已经落盘:
  - `output/my7_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my7_nomask_v1/point_cloud/iteration_35000/point_cloud.ply`
- 自动接力脚本当前已从训练切到渲染:
  - 活跃进程为 `bash scripts/run_lyra_colmap_fastgs.sh --phase render`
  - `pixi run python render.py -m ... --iteration 35000 --mult 0.5`
- 当前渲染仍在进行, 还没有最终 mp4:
  - `train/ours_35000/renders = 154`
  - `test/ours_35000/renders = 0`
  - `output/my7_nomask_v1/videos = 0`

### 当前状态
- `my7` 现在只差最终渲染与视频封装.
- 下一步继续等待 `train/test` 两套渲染完毕并生成 mp4.
- `my7` 视频落盘后, 立即开始 `my8 prepare`.

## [2026-03-28 15:08:50 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: 按上次未完成步骤继续, 先收尾 `my7` 再切 `my8`

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [ ] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 本轮动作
- 先重新核对 `my7` 的 render / video 实时状态.
- 如果 `my7` 视频已经落盘, 立即启动 `my8 prepare`.
- 如果 `my7` 还在渲染, 就继续观察到阶段切换完成.

### 当前状态
- 当前仍处于阶段4, 但要先确认它是否已经自然推进到可开启阶段5.

## [2026-03-28 15:09:26 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my7` 已完整完成, 转入 `my8 prepare`

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [x] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my7` 自动接力会话已明确输出:
  - `my7 pipeline completed successfully`
- `my7` 最终产物已齐:
  - `output/my7_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my7_nomask_v1/point_cloud/iteration_35000/point_cloud.ply`
  - `output/my7_nomask_v1/videos/train_iter35000.mp4`
  - `output/my7_nomask_v1/videos/test_iter35000.mp4`
- 当前 `my7` 渲染总数也已齐:
  - `train/ours_35000/renders = 283`
  - `test/ours_35000/renders = 41`

### 当前状态
- 当前正式进入阶段5.
- 下一步立即启动 `my8 prepare`, 并复用 `my7` 的 guarded 自动接力策略.

## [2026-03-28 15:10:35 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my8 prepare` 与自动接力已启动

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [x] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已执行动作
- 已启动 `my8 prepare`:
  - 会话 `99442`
  - `prepare_pid=712127`
- 已启动 `my8` 自动接力脚本:
  - 会话 `91438`
  - 脚本路径: `/tmp/fastgs_logs/my8_pipeline_20260328_1509.sh`
- 当前策略与 `my7` 一致:
  - 先等待 `prepare` 结束
  - 校验 `images=324` 和 `sparse/0`
  - 再按 `1000` 步一段 guarded 训练到 `35000`
  - 最后自动 render + 视频封装

### 当前状态
- 当前仍处于阶段5.
- 下一步继续观察 `my8 prepare` 是否顺利跨过抽帧、匹配、`mapper`.

## [2026-03-28 15:20:08 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my8 prepare` 已进入 `exhaustive_matcher` 中段

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [x] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my8` 当前已完成:
  - `input=324`
  - `feature_extractor 324/324`
- `my8 prepare` 会话最近已推进到:
  - `Processing block [2/7, 3/7]`
- 自动接力会话仍健康等待, 没有丢链.

### 当前状态
- 当前仍在阶段5.
- 下一步继续等待 `exhaustive_matcher -> mapper -> 导出` 完成.

## [2026-03-28 15:25:10 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my8 prepare` 仍在 matcher, 当前已推进到第二行后段

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [x] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my8 prepare` 仍在持续推进, 当前最新动态证据为:
  - `Processing block [2/7, 6/7]`
- 当前还没有进入 `mapper`, 也还没有落盘:
  - `images = 0`
  - `sparse/0 = 0`
  - `checkpoints = 0`
- 自动接力会话持续健康:
  - 周期性输出 `prepare still running`

### 当前状态
- 当前仍在阶段5.
- 这一步的核心判断不变:
  - `my8` 目前是“正常推进但偏慢”
  - 还没有看到失败证据

## [2026-03-28 16:44:25 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: 继续跟进 `my8` 长任务状态

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [x] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段5: 完成 `my8` 的 `prepare`
- [ ] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [ ] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 本轮动作
- 先核对 `my8` 的会话 `99442` / `91438` 是否仍然活跃.
- 同时核对 `my8` 的 `images` / `sparse/0` / `checkpoints` / `videos` 落盘状态.
- 如果 `prepare` 已结束, 立刻确认自动接力训练是否已经接上.

### 当前状态
- 当前仍处于阶段5, 但需要先刷新现场证据, 再给出准确定义.

## [2026-03-28 16:44:54 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] [记录类型]: `my8` 全链路完成, 支线任务收尾

### 进度更新
- [x] 阶段1: 核对 `my7` / `my8` 输入结构与 `my5/my6` 复用参数
- [x] 阶段2: 做 `my7` / `my8` 的最小动态验证
- [x] 阶段3: 完成 `my7` 的 `prepare`
- [x] 阶段4: 完成 `my7` 的 `35000` 训练与视频/ply 导出
- [x] 阶段5: 完成 `my8` 的 `prepare`
- [x] 阶段6: 完成 `my8` 的 `35000` 训练与视频/ply 导出
- [x] 阶段7: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my8 prepare` 会话已完成:
  - matcher 跑完整个 `7/7`
  - 进入 `mapper`
  - 最终进入 `undistort` 并输出 `Done.`
- `my8` 自动接力会话已明确完成:
  - `my8 pipeline completed successfully`
- `my8` 最终产物已齐:
  - `output/my8_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my8_nomask_v1/point_cloud/iteration_35000/point_cloud.ply`
  - `output/my8_nomask_v1/videos/train_iter35000.mp4`
  - `output/my8_nomask_v1/videos/test_iter35000.mp4`
- `my8` 当前目录计数也已符合完整收尾:
  - `input = 324`
  - `images = 324`
  - `sparse/0 = 6`
  - `checkpoints = 35`
  - `videos = 2`
  - `train renders = 283`
  - `test renders = 41`

### 当前状态
- 当前支线任务已经完成.
- 下一步只剩对外汇报最终结果.
