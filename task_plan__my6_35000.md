# 任务计划: 复用 `my5` 口径处理 `my6` 并完成 `35000` 训练

## [2026-03-28 08:47:34 UTC] [Session ID: 5957] [记录类型]: 新支线建档

### 目标
- 按 `/root/autodl-fs/my5` 已验证的流程处理 `/root/autodl-fs/my6`.
- 完成 `COLMAP -> FastGS` 的 `35000` 训练.
- 最终产出 `35000` 轮的 train/test 视频与 `3DGS ply`.

### 两种方向
- 方案A(更稳, 最佳):
  - 先做单视角抽帧验证.
  - 再按阶段执行 `prepare -> train -> render`.
  - 每个阶段都核对关键产物, 便于中途失败时直接续跑.
- 方案B(更快, 先能用):
  - 直接用 `--phase all` 一把跑到底.
  - 中间依赖脚本自动衔接, 人工检查更少.

### 当前决定
- 本轮先采用方案A.
- 原因:
  - `my6` 虽然结构看起来和 `my5` 一样, 但还没有做过真实动态验证.
  - 先把抽帧与 `COLMAP` 前半段证据拿到, 再进入长训练, 风险更可控.

### 阶段
- [ ] 阶段1: 核对 `my6` 输入结构与 `my5` 复用参数
- [ ] 阶段2: 做单视角抽帧与环境最小验证
- [ ] 阶段3: 完成 `my6` 的 `prepare`
- [ ] 阶段4: 完成 `my6` 的 `35000` 训练
- [ ] 阶段5: 导出 `35000` 的视频与 `ply`, 并核对落盘结果
- [ ] 阶段6: 回写支线 `notes/WORKLOG`, 收尾交付

### 关键问题
1. `my6` 是否和 `my5` 一样, 只应使用 `generated_videos/generated_video_0.mp4` 作为 RGB 输入?
2. `my5` 的稳定口径是否可以原样迁移:
   - `--video-fps 5.333333333333`
   - 无训练 mask
   - `-r 1`
   - `--densification_interval 500`
   - `--position_lr_max_steps 35000`
   - `--eval`
3. `my6` 是否需要像 `my5` 一样单独导出 `35000` 的 train/test mp4?

### 现象 -> 假设 -> 验证计划
- 现象:
  - `/root/autodl-fs/my6` 的目录结构与 `my5` 高度一致.
  - 根目录下同样存在 `0..11/generated_videos/generated_video_0.mp4` 和 `rendering_4D_maps/merged_mask.mp4`.
- 当前主假设:
  - `my5` 的稳定处理口径可以直接迁移到 `my6`, 不需要再造新入口.
- 最强备选解释:
  - `my6` 虽然结构相同, 但视频长度或素材质量可能不同, 导致 `5.333333333333 fps` 不一定仍然对应 `324` 张总图量.
- 推翻主假设的证据:
  - 如果单视角抽帧结果明显不是 `27` 帧左右.
  - 或者 `prepare` 阶段在 `my6` 上暴露出 `my5` 没有的问题.

### 当前状态
- 目前在阶段1.
- 下一步先记录 `my6` 的静态结构和 `my5` 已验证参数, 然后做单视角抽帧验证.

## [2026-03-28 08:51:10 UTC] [Session ID: 5957] [记录类型]: 最小动态验证通过, 转入 `prepare`

### 进度更新
- [x] 阶段1: 核对 `my6` 输入结构与 `my5` 复用参数
- [x] 阶段2: 做单视角抽帧与环境最小验证
- [ ] 阶段3: 完成 `my6` 的 `prepare`
- [ ] 阶段4: 完成 `my6` 的 `35000` 训练
- [ ] 阶段5: 导出 `35000` 的视频与 `ply`, 并核对落盘结果
- [ ] 阶段6: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `my6` 的单视角视频与 `my5` 使用同一时间基准:
  - 原视频: `16 fps`, `81` 帧, `1280x720`, 时长 `5.0625s`
  - 抽帧验证: `ffmpeg -vf fps=5.333333333333` -> `27` 帧
- 因此把总图量目标定为 `324` 张, 仍然成立.

### 当前状态
- 目前进入阶段3.
- 下一步直接启动 `my6` 的真实 `prepare`, 目标目录定为:
  - `data/my6_colmap_fastgs`
  - `output/my6_nomask_v1`

## [2026-03-28 17:53:30 UTC] [Session ID: 5957] [记录类型]: `prepare` 完成, 转入 `35000` 训练

### 进度更新
- [x] 阶段1: 核对 `my6` 输入结构与 `my5` 复用参数
- [x] 阶段2: 做单视角抽帧与环境最小验证
- [x] 阶段3: 完成 `my6` 的 `prepare`
- [ ] 阶段4: 完成 `my6` 的 `35000` 训练
- [ ] 阶段5: 导出 `35000` 的视频与 `ply`, 并核对落盘结果
- [ ] 阶段6: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `prepare` 的真实产物已经落盘:
  - `data/my6_colmap_fastgs/images` = `324` 张
  - `data/my6_colmap_fastgs/sparse/0` = `5` 个二进制模型文件
- `matcher` 总耗时约 `40.102` 分钟.
- `mapper` 后续已推进到 undistort, 并完成最终 `images + sparse/0` 导出.

### 当前状态
- 目前进入阶段4.
- 下一步启动 `my6_nomask_v1` 的 `35000` 训练, 继续复用 `my5` 的同口径参数:
  - `-r 1`
  - `--densification_interval 500`
  - `--position_lr_max_steps 35000`
  - `--eval`
  - `--video-iterations 35000`

## [2026-03-28 17:54:10 UTC] [Session ID: 5957] [记录类型]: 全量直跑在约 `7940` 失败, 改切 guarded 分段训练

### 现象
- `my6` 按 `my5` 同口径直接跑 `0 -> 35000` 时, 在全局约 `7940` 左右报错退出.
- 已观察到的真实异常是:
  - `torch.AcceleratorError: CUDA error: an illegal memory access was encountered`
- 当前未落盘任何 checkpoint, 因为这轮只计划在 `35000` 保存.

### 当前主假设
- 当前更像仓库历史里已经出现过的“长跑随机 CUDA 非法访问”.
- 这只是候选判断, 还不是已确认根因.

### 最强备选解释
- 也可能 `my6` 的数据分布在前半段某个 densify / rasterize 路径上更容易触发扩展层问题.
- 这同样还缺更细的动态证据.

### 已有可复用证据
- 项目历史已经验证过一条可交付策略:
  - `1000` 步一段
  - 每段强制保存 checkpoint / point cloud
  - 某段失败就从最近稳定锚点重试
  - 同时换 seed 规避坏路径

### 当前状态
- 目前阶段4仍未完成.
- 下一步先不用改代码, 先按历史已验证策略启动 guarded 分段训练, 看能否把 `my6` 稳定推进到 `35000`.

## [2026-03-28 10:02:42 UTC] [Session ID: codex-20260328-1002] [记录类型]: 接手支线并确认 guarded 训练已完成

### 进度更新
- [x] 阶段1: 核对 `my6` 输入结构与 `my5` 复用参数
- [x] 阶段2: 做单视角抽帧与环境最小验证
- [x] 阶段3: 完成 `my6` 的 `prepare`
- [x] 阶段4: 完成 `my6` 的 `35000` 训练
- [ ] 阶段5: 导出 `35000` 的视频与 `ply`, 并核对落盘结果
- [ ] 阶段6: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- `guarded` 日志尾部已经出现:
  - `Saving Gaussians`
  - `Saving Checkpoint`
  - `Training complete.`
  - `[guard-my6] completed through 35000`
- 产物侧也已经对上:
  - `output/my6_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my6_nomask_v1/point_cloud/iteration_35000`
- 当前没有看到仍在运行的 `my6` 训练相关进程.

### 当前状态
- 目前进入阶段5.
- 下一步执行渲染导出:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase render --model-path output/my6_nomask_v1 --video-iterations 35000 --video-sets both --overwrite`

## [2026-03-28 10:04:49 UTC] [Session ID: codex-20260328-1002] [记录类型]: 视频导出与最终交付核查完成

### 进度更新
- [x] 阶段1: 核对 `my6` 输入结构与 `my5` 复用参数
- [x] 阶段2: 做单视角抽帧与环境最小验证
- [x] 阶段3: 完成 `my6` 的 `prepare`
- [x] 阶段4: 完成 `my6` 的 `35000` 训练
- [x] 阶段5: 导出 `35000` 的视频与 `ply`, 并核对落盘结果
- [x] 阶段6: 回写支线 `notes/WORKLOG`, 收尾交付

### 已验证结论
- 最终四个交付物均已存在并核对通过:
  - `output/my6_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my6_nomask_v1/point_cloud/iteration_35000/point_cloud.ply`
  - `output/my6_nomask_v1/videos/train_iter35000.mp4`
  - `output/my6_nomask_v1/videos/test_iter35000.mp4`
- 视频元信息已确认:
  - `train_iter35000.mp4` 时长 `11.792s`
  - `test_iter35000.mp4` 时长 `1.709s`

### 当前状态
- 这条支线已经完成交付.
- 本轮未新增需要延期处理的事项, 也没有出现需要单独升级到 `EPIPHANY_LOG__my6_35000.md` 的新灾难点.
