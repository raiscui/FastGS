## [2026-03-29 09:21:05 UTC] [Session ID: 019d38e4-25b6-7442-96f0-f2e4c43ccb82] 任务名称: 分析 `my8` 空中棉絮状 3DGS 漂浮的处理方向

### 任务内容
- 回读 `my7` / `my8` 已完成训练支线, 判断 `my8` 漂浮伪影是否更像数据、位姿还是训练口径问题.
- 查找仓库里是否已有针对这类问题的现成处理工具和文档入口.

### 完成过程
- 回读了 `task_plan__my7_my8_35000.md`、`WORKLOG__my7_my8_35000.md` 与 `EXPERIENCE.md`, 确认 `my7` / `my8` 使用的是同一条已验证训练链.
- 对照了 `cfg_args`、`input.ply` 与最终 `point_cloud.ply`, 确认 `my8` 的初始稀疏点和最终 Gaussian 数量都显著高于 `my7`.
- 回读了 `README.md`、`scripts/generate_particle_masks.py` 与 `scripts/run_lyra_colmap_fastgs.sh`, 确认仓库已经提供“先生成粒子 mask, 再用 --mask-dir 训练”的正式处理方式.
- 用现成颗粒检测逻辑对 `my7` / `my8` 做了最小帧级抽查, 结果没有支持“`my8` 一定比 `my7` 更脏”这一条假设.

### 总结感悟
- 这类“空中棉絮漂浮”问题, 最危险的动作不是“不知道怎么修”, 而是还没区分数据颗粒、位姿外点、训练口径就直接硬调超参.
- 当前仓库已经给了一个非常明确的第一优先处理方向: 对可疑漂浮颗粒先做 mask, 再训练. 这是比盲目拉训练步数更稳的路线.

## [2026-03-29 09:29:40 UTC] [Session ID: 019d38e4-25b6-7442-96f0-f2e4c43ccb82] 任务名称: 落地 `my8` 的 particle mask v1, 完成带 mask 训练与渲染对照

### 任务内容
- 为 `my8` 生成针对空中颗粒/小亮点的训练 mask.
- 验证带 mask 训练链是否可用.
- 在这台机器上把带 mask 版本真正推进到 `35000` 并导出视频.
- 对照无 mask 版本的结果, 判断这条路线是否已经构成有效修复.

### 完成过程
- 先对 `data/my8_colmap_fastgs/images` 跑了 `scripts/generate_particle_masks.py`, 成功生成 mask、debug 预览与 summary JSON.
- 用 `output/my8_mask_particle_smoke` 做了 `100` 轮短训练, 确认 `--mask-dir` 链路可用.
- 随后尝试完整直跑 `35000`, 在约 `21320` 触发 CUDA 运行时错误.
- 没有把这次失败误当成“mask 路线无效”, 而是切换到项目里已经验证过的 guarded 分段训练策略:
  - `1000` 步一段
  - 每段保存 checkpoint / point cloud
  - 失败自动换 seed 重试
- 最终成功交付:
  - `output/my8_mask_particle_v1/checkpoints/ckpt_35000.pth`
  - `output/my8_mask_particle_v1/point_cloud/iteration_35000/point_cloud.ply`
  - `output/my8_mask_particle_v1/videos/train_iter35000.mp4`
  - `output/my8_mask_particle_v1/videos/test_iter35000.mp4`
- 最后补跑了对照统计与标准指标, 用来判断这版方案是否已经形成明确改进.

### 总结感悟
- 这次最有价值的不是“把 mask 路线跑通”, 而是验证了两件事:
  - 带 mask 版本在这台机器上同样需要 guarded 分段训练
  - `particle mask v1` 跑通不等于质量一定更好, 不能只因它更符合直觉就直接宣布问题解决
- 当前更诚实的结论是:
  - 这是一条已经验证可执行的改良方向
  - 但它还不是终局解法

## [2026-03-29 11:11:55 UTC] [Session ID: c1ad2430-46ff-4852-89ec-356e70f96f49] 任务名称: 基于删图后的 `my8 input` 重新跑一版 nomask `35000`

### 任务内容
- 接手用户对 `data/my8_colmap_fastgs/input` 的删图修改.
- 避免覆盖旧版 `my8` 数据根与训练结果.
- 用新的 pruned 输入重跑 COLMAP.
- 再用 nomask guarded 分段训练跑到 `35000`, 并导出视频与指标.

### 完成过程
- 先核对了当前现场:
  - `input = 277`
  - 旧 `images = 324`
  - 旧 `sparse/0 = 6`
- 没有直接覆盖旧 `my8_colmap_fastgs`, 而是新建了:
  - `data/my8_colmap_fastgs_input_pruned_v1`
  - `output/my8_nomask_input_pruned_v1`
- 对新的图片模式 `input` 直接运行了 `convert.py`, 成功得到:
  - `registered_images = 277`
  - `points = 8515`
- 随后复用项目里已经验证过的 guarded `1000` 步分段训练链, 一路推进到 `35000`, 再自动 render 并封装 train/test 视频.
- 最后补跑 `metrics.py`, 并和旧 `my8_nomask_v1` 做了几何规模与标准指标对照.

### 总结感悟
- 这次删图动作确实显著收缩了几何规模:
  - 初始 sparse points 从 `20789` 降到 `8515`
  - 最终高斯数从 `52683` 降到 `27220`
- 但这不能自动等价成“结果更好”.
- 当前真实结论是:
  - pruned 版已经完整跑通
  - 但质量指标明显差于旧版
  - 所以下一步更像“有针对性的删/筛视角”, 而不是继续粗暴整组删除
