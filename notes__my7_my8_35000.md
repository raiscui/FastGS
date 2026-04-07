## [2026-03-28 11:48:07 UTC] [Session ID: codex-20260328-1148] 笔记: `my7` / `my8` 的输入结构与复用口径

## 来源

### 来源1: `EXPERIENCE.md` 回读

- 已验证可复用口径:
  - `12` 视角生成视频目录默认走 `nomask`
  - `rendering_4D_maps/merged_mask.mp4` 不接训练 mask 语义
  - `--video-fps 5.333333333333`
  - `35000` 训练口径继续沿用:
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

### 来源2: `my7` / `my8` 目录静态核查

- 路径:
  - `/root/autodl-fs/my7`
  - `/root/autodl-fs/my8`
- 已观察到的事实:
  - 都存在 `0..11` 共 `12` 个视角目录.
  - 每个视角目录都存在:
    - `generated_videos/generated_video_0.mp4`
    - `rendering_4D_maps/merged_mask.mp4`
  - 当前 `data/` 和 `output/` 下还没有对应的中间产物目录.

## 综合发现

### 现象
- `my7` / `my8` 与 `my5/my6` 属于同一类输入结构.
- 因此它们更像“同一工作流下的新样本”, 不是新格式.

### 当前主假设
- `my5/my6` 的稳定口径可以直接迁移到 `my7` / `my8`.

### 当前还缺的证据
- 还没有做 `my7` / `my8` 的单视角抽帧动态验证.
- 也还没有拿到任一套数据的真实 `prepare` 结果.

## [2026-03-28 11:48:07 UTC] [Session ID: codex-20260328-1148] 笔记: `my7` / `my8` 的单视角抽帧动态验证

## 来源

### 来源1: `my7` 单视角验证

- 命令:
  - `ffmpeg -i /root/autodl-fs/my7/0/generated_videos/generated_video_0.mp4 -vf fps=5.333333333333 ...`
- 结果:
  - `count=27`

### 来源2: `my8` 单视角验证

- 命令:
  - `ffmpeg -i /root/autodl-fs/my8/0/generated_videos/generated_video_0.mp4 -vf fps=5.333333333333 ...`
- 结果:
  - `count=27`

### 来源3: 视频元信息核查

- `my7/0/generated_video_0.mp4`:
  - `width=1280`
  - `height=720`
  - `avg_frame_rate=16/1`
  - `nb_frames=81`
  - `duration=5.063000`
- `my8/0/generated_video_0.mp4`:
  - `width=1280`
  - `height=720`
  - `avg_frame_rate=16/1`
  - `nb_frames=81`
  - `duration=5.063000`

## 综合发现

### 现象
- `my7` 和 `my8` 的视频时间基准与 `my5/my6` 一致.
- 用 `5.333333333333 fps` 抽帧时, 都稳定落到 `27` 帧.

### 当前结论
- 两套数据都可以继续沿用 `1/3` 图量策略.
- 对 `12` 个视角而言, 这意味着:
  - `my7` 目标图量约 `324`
  - `my8` 目标图量约 `324`

## [2026-03-28 11:48:07 UTC] [Session ID: codex-20260328-1148] 笔记: `my7 prepare` 前暴露的 `COLMAP` 默认路径失效

## 来源

### 来源1: `my7 prepare` 首次启动失败

- 命令:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase prepare --source-path /root/autodl-fs/my7 ...`
- 首次真实报错:
  - `[lyra-colmap-fastgs] ERROR: 文件不存在: /workspace/colmap-cuda-install-3.12.6/bin/colmap`

### 来源2: 环境路径核查

- 当前机器结果:
  - `/workspace/colmap-cuda-install-3.12.6/bin/colmap` 不存在
  - `$HOME/.local/opt/colmap-env/bin/colmap` 存在且可执行
  - `PATH` 中没有 `colmap`

### 来源3: 修复后的动态验证

- 对 `scripts/run_lyra_colmap_fastgs.sh` 做了收敛修复:
  - 当默认 `/workspace/.../colmap` 不存在时
  - 先尝试 `$HOME/.local/opt/colmap-env/bin/colmap`
  - 再回退到 `PATH` 的 `colmap`
- 修复后同一条 `my7 prepare` 命令已实际推进到:
  - `feature_extractor 324/324`
  - `exhaustive_matcher`

## 综合发现

### 现象
- 这次失败不是 `my7` 数据坏了, 而是 wrapper 的默认 `COLMAP` 安装前缀和当前机器环境脱节了.

### 已验证结论
- 当前机器更稳的默认回退顺序应当是:
  - `/workspace/colmap-cuda-install-3.12.6/bin/colmap`
  - `$HOME/.local/opt/colmap-env/bin/colmap`
  - `PATH` 中的 `colmap`
- 这个修复已经被 `my7 prepare` 的真实动态启动成功所验证.

## [2026-03-28 13:02:00 UTC] [Session ID: codex-20260328-1148] 笔记: `my7 prepare` 的当前运行态

## 来源

### 来源1: `my7 prepare` 实时会话

- 已观测到的阶段切换:
  - `feature_extractor 324/324`
  - `exhaustive_matcher` 全部分块完成
  - 进入 `mapper`
- `mapper` 期间已多次看到:
  - `incremental_pipeline.cc:524 Registering image ...`
  - `Retriangulation and Global bundle adjustment`
- 最近一次动态证据:
  - `num_reg_frames=233`

### 来源2: 产物目录核查

- 当前目录状态:
  - `data/my7_colmap_fastgs/input` 已有 `324` 张抽帧图
  - `data/my7_colmap_fastgs/images` 仍为 `0`
  - `data/my7_colmap_fastgs/sparse/0` 仍未落盘最终模型文件
- 这说明:
  - `prepare` 仍停留在 `mapper` 内部
  - 还没有进入最终的 undistort / 导出完成态

### 来源3: 自动接力会话

- 已启动一条独立的 `my7 pipeline` 会话.
- 它当前只做等待:
  - 每 `30s` 轮询一次 `prepare` 进程是否结束
  - `prepare` 一结束就会自动执行:
    - 数据目录校验
    - guarded `35000` 训练
    - `render --video-iterations 35000 --video-sets both`

## 综合发现

### 现象
- `my7 prepare` 并没有失败退出.
- 它只是比 `my6` 更慢地停留在 `mapper` 阶段.

### 当前主假设
- 当前更像素材几何更难, 导致 `mapper` 收敛和注册都更慢.
- 这仍然只是候选判断, 还不是最终根因结论.

### 最强备选解释
- 也可能是当前 `mapper` 参数在 `my7` 上过于保守, 让 BA 花了更长时间.
- 这同样还缺“改参数前后对照”的动态证据.

### 当前结论
- 当前不应该贸然中断或重跑 `my7 prepare`.
- 更合理的是:
  - 继续让当前 `mapper` 跑完
  - 等自动接力进入 `my7` 训练
  - 再决定 `my8` 是否沿用完全相同的策略

## [2026-03-28 13:46:53 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my7` 已从 `prepare` 切换到正式训练, 当前至少到 `32000`

## 来源

### 来源1: `my7 prepare` 会话 `32908`

- 会话尾部已出现完整收尾证据:
  - `Undistorting image [324/324]`
  - `Writing reconstruction...`
  - `Writing configuration...`
  - `Writing scripts...`
  - `Done.`
- 这说明:
  - `mapper` 阶段已经结束
  - 数据集导出已经成功完成

### 来源2: 自动接力会话 `78972`

- 会话中已看到自动切换:
  - `prepare pid exited, validating dataset root`
  - `dataset counts: images=324 sparse_files=5`
  - 随后进入 guarded 分段训练
- 同一会话后续已出现:
  - `segment 28000->29000 success`
  - 启动 `29000->30000`
  - 之后继续推进到更高分段

### 来源3: 文件系统落盘核查

- 当前 `my7` 数据目录:
  - `data/my7_colmap_fastgs/input = 324`
  - `data/my7_colmap_fastgs/images = 324`
  - `data/my7_colmap_fastgs/sparse/0 = 6`
- 当前 `my7` 训练产物已落到:
  - `ckpt_32000.pth`
  - `point_cloud/iteration_32000/point_cloud.ply`
- 当前还没有最终视频:
  - `output/my7_nomask_v1/videos = 0`
- 当前 `my8` 仍未开始:
  - `data/my8_colmap_fastgs/input = 0`
  - `output/my8_nomask_v1/checkpoints = 0`

## 综合发现

### 现象
- `my7` 不再停留在 `COLMAP mapper`.
- 它已经完成 `prepare`, 并顺利进入 guarded 分段训练.

### 当前主假设
- 现阶段主风险已经从 `prepare` 切换为“等待 `35000` 全段完成并导出视频”.
- 这个判断有静态证据和动态证据共同支撑, 不再只是候选猜测.

### 最强备选解释
- 训练后半段仍可能在某个分段出现中断, 例如资源波动或单段续训失败.
- 但截至当前, 还没有看到这类失败证据.

### 当前结论
- `my7` 当前属于“进行中但健康”的状态.
- 当前最合理策略仍然是:
  - 继续让 `my7` 自动跑完到 `35000`
  - 等 `ply + 视频` 全部落盘
  - 然后再启动 `my8`

## [2026-03-28 13:47:50 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my7` 已拿到 `35000` checkpoint 和 ply, 当前卡点只剩渲染

## 来源

### 来源1: `my7` 产物核查

- 已确认存在:
  - `output/my7_nomask_v1/checkpoints/ckpt_35000.pth`
  - `output/my7_nomask_v1/point_cloud/iteration_35000/point_cloud.ply`
- 这说明:
  - `35000` 训练本体已经结束
  - 3DGS 的最终 `ply` 已经具备

### 来源2: 进程核查

- 当前活跃进程不再是 `train.py`, 而是:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase render --model-path output/my7_nomask_v1 --video-iterations 35000 --video-sets both --overwrite`
  - `pixi run python render.py -m ... --iteration 35000 --mult 0.5`
- 这说明自动接力已经自然切换到了渲染阶段

### 来源3: 渲染目录与实时会话

- 文件数核查:
  - `train/ours_35000/renders = 154`
  - `test/ours_35000/renders = 0`
  - `videos = 0`
- 会话 `78972` 的实时输出也已进入:
  - `Rendering progress: ...`
- 因此当前并不是“还没开始导视频”, 而是“导视频前的逐帧渲染正在进行”

## 综合发现

### 现象
- `my7` 的训练目标已经达到 `35000`.
- 现在剩余的只是渲染与 mp4 生成, 不是再训练更多轮.

### 当前主假设
- 如果当前渲染进程保持稳定, `my7` 会先生成 train 视角渲染, 再生成 test 视角渲染, 最后封装 mp4.
- 这个判断是根据活跃 `render.py` 进程和目录写入行为做出的.

### 最强备选解释
- 也可能渲染阶段在中途暴露显存或 ffmpeg 封装问题.
- 但截至当前, 还没有看到报错或退出证据.

### 当前结论
- `my7` 目前已经拿到两项核心成果:
  - `ckpt_35000.pth`
  - `iteration_35000/point_cloud.ply`
- 尚未完成的只有:
  - 最终视频文件
  - `my8` 的整条处理链

## [2026-03-28 15:09:26 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my7` 已完整收尾, `my8` 可以沿同口径接棒

## 来源

### 来源1: `my7` 自动接力会话尾部

- 已出现明确完成信号:
  - `my7 pipeline completed successfully`
- 在完成前还可见:
  - `train_iter35000.mp4` 已完成封装
  - `test_iter35000.mp4` 已完成封装

### 来源2: `my7` 最终产物核查

- 产物文件都已存在:
  - `ckpt_35000.pth` 大小约 `25M`
  - `iteration_35000/point_cloud.ply` 大小约 `8.5M`
  - `videos/train_iter35000.mp4` 大小约 `5.8M`
  - `videos/test_iter35000.mp4` 大小约 `1.2M`

### 来源3: 渲染目录核查

- `train/ours_35000/renders = 283`
- `test/ours_35000/renders = 41`
- 这和自动封装出的 train/test 两个 mp4 是一致的

## 综合发现

### 现象
- `my7` 的整条处理链已经完全闭环.
- 这意味着同一套 guarded 训练与渲染策略可以继续迁移到 `my8`.

### 当前主假设
- `my8` 将继续使用和 `my7` 完全一致的:
  - `prepare` 入口
  - guarded `1000` 步分段训练
  - `35000` 后自动 render + ffmpeg 封装

### 最强备选解释
- `my8` 也可能在 `COLMAP mapper` 阶段比 `my7` 更慢.
- 但只要不出现新的错误证据, 当前无需提前改参数.

### 当前结论
- 现在最合理的动作不是再回头碰 `my7`.
- 而是直接启动 `my8 prepare`, 并保持相同的串行资源策略.

## [2026-03-28 15:10:35 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my8` 已进入真实执行态, 自动接力链已挂起

## 来源

### 来源1: `my8 prepare` 启动输出

- 已拿到真实 `prepare_pid=712127`
- 活跃会话:
  - `99442`
- 启动输出已确认:
  - 自动回退到 `/home/rais/.local/opt/colmap-env/bin/colmap`
  - `convert.py` 已开始对 `my8` 的 `12` 路视频做抽帧

### 来源2: `my8` 自动接力脚本

- 新建脚本:
  - `/tmp/fastgs_logs/my8_pipeline_20260328_1509.sh`
- 活跃会话:
  - `91438`
- 当前行为:
  - 轮询等待 `prepare_pid=712127` 结束
  - 结束后自动核验 `images` / `sparse/0`
  - 之后沿用 `my7` 同口径进入 guarded 训练和渲染

## 综合发现

### 现象
- `my8` 现在不是“计划要做”, 而是已经真正开跑.
- 自动接力链也已经预先挂好, 不需要等 `prepare` 结束后手工补启动.

### 当前主假设
- 只要 `my8 prepare` 不暴露新错误, 它会像 `my7` 一样自然切到训练链.

### 最强备选解释
- `my8` 仍可能在 `mapper` 阶段比 `my7` 更慢, 或出现新的几何难点.
- 但在真正看到动态失败证据前, 这还只是备选风险, 不是已确认问题.

### 当前结论
- 当前最重要的是继续观察 `my8 prepare` 的阶段推进.
- 现阶段没有必要改参数或中断任务.

## [2026-03-28 15:20:08 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my8 prepare` 已推进到 `exhaustive_matcher` 中段

## 来源

### 来源1: `my8 prepare` 会话 `99442`

- 已确认阶段推进:
  - 抽帧完成, `input = 324`
  - `feature_extractor` 完成到 `324/324`
  - 当前进入 `exhaustive_matcher`
- 最近几次动态输出依次出现:
  - `Processing block [1/7, 7/7]`
  - `Processing block [2/7, 1/7]`
  - `Processing block [2/7, 2/7]`
  - `Processing block [2/7, 3/7]`

### 来源2: `my8` 自动接力会话 `91438`

- 会话仍在健康等待:
  - 每 `30s` 输出一次 `prepare still running`
- 这说明:
  - 自动接力链没有丢
  - 也没有误判 `prepare` 已结束

### 来源3: 当前目录状态

- `data/my8_colmap_fastgs/input = 324`
- `data/my8_colmap_fastgs/images = 0`
- `data/my8_colmap_fastgs/sparse/0 = 0`
- `output/my8_nomask_v1/checkpoints = 0`

## 综合发现

### 现象
- `my8` 当前还没有进入 `mapper`.
- 但 `exhaustive_matcher` 一直在推进 block, 没有停在单个 block 上不动.

### 当前主假设
- `my8` 现在的主要耗时仍在全对匹配阶段.
- 只要 block 编号持续推进, 当前更像“正常但偏慢”, 而不是失败。

### 最强备选解释
- 也可能后续进入 `mapper` 后耗时才会真正拉长.
- 这个风险和 `my7` 类似, 但现在还没有新的异常证据.

### 当前结论
- 继续等待 `my8 prepare` 是合理策略.
- 当前还没有理由中断并重跑.

## [2026-03-28 15:25:10 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my8 prepare` 最新仍在 matcher 第二行后段

## 来源

### 来源1: `my8 prepare` 会话 `99442`

- 在上一次记录后的新动态输出中, 又继续推进到:
  - `Processing block [2/7, 4/7]`
  - `Processing block [2/7, 5/7]`
  - `Processing block [2/7, 6/7]`

### 来源2: `my8` 自动接力会话 `91438`

- 自动接力会话仍周期性输出:
  - `prepare still running`
- 没有出现提前误触发训练或报错退出

## 综合发现

### 现象
- `my8` 的 matcher 比 `my7` 更慢.
- 但 block 编号还在按顺序推进.

### 当前结论
- 到当前时刻为止, 更准确的口径是:
  - `my8` 仍在 `prepare`
  - 主要耗时点在 `exhaustive_matcher`
  - 自动训练链已经挂好, 只是还没到触发时机

## [2026-03-28 16:44:54 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my8` 已完整闭环, `my7/my8` 两套数据都完成

## 来源

### 来源1: `my8 prepare` 会话 `99442`

- 会话尾部已覆盖完整阶段切换:
  - `feature_matching` 从 `2/7, 7/7` 一直跑到 `7/7, 7/7`
  - 之后进入 `mapper`
  - `mapper` 内已真实注册图像
  - 最终进入 `Undistorting image [324/324]`
  - 结束于 `Writing reconstruction...`, `Writing configuration...`, `Writing scripts...`, `Done.`

### 来源2: `my8` 自动接力会话 `91438`

- 会话在 `prepare` 完成后自动接上:
  - guarded `1000` 步分段训练到 `35000`
  - render
  - ffmpeg 视频封装
- 会话尾部明确给出:
  - `my8 pipeline completed successfully`

### 来源3: `my8` 最终产物核查

- 产物文件已存在:
  - `ckpt_35000.pth` 约 `37M`
  - `iteration_35000/point_cloud.ply` 约 `13M`
  - `train_iter35000.mp4` 约 `6.2M`
  - `test_iter35000.mp4` 约 `1.4M`
- 目录计数:
  - `input = 324`
  - `images = 324`
  - `sparse/0 = 6`
  - `checkpoints = 35`
  - `videos = 2`
  - `train renders = 283`
  - `test renders = 41`

## 综合发现

### 现象
- `my8` 最终并没有停在 matcher 或 mapper.
- 它已经像 `my7` 一样, 跑完了从 `prepare` 到 `35000` 再到视频封装的整条链.

### 当前结论
- 这条支线任务现在已经完整完成:
  - `my7` 完成
  - `my8` 完成
- 当前不再有未完成的训练或渲染进程需要继续盯守.
