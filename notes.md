## [2026-03-27 09:41:03] [Session ID: 28616] 笔记: `my5` 输入结构与现有脚本差异

## 来源

### 来源1: `/root/autodl-fs/my5` 目录核查

- 已观察到目录结构:
  - `0..11/generated_videos/generated_video_0.mp4`
  - `0..11/rendering_4D_maps/merged_mask.mp4`
  - `0..11/rendering_4D_maps/background_*.mp4`
  - `0..11/rendering_4D_maps/3D_gaussian_*.mp4`
  - 根目录还有 `manifest.json`
- 关键发现:
  - 这不是旧的 `rgb/*.mp4` 布局.
  - 每个视角目录里同时放了“应该喂给 COLMAP 的 RGB 视频”和“绝对不该喂给 COLMAP 的辅助视频”.

### 来源2: 动态媒体信息核查

- 命令:
  - `ffprobe ... /root/autodl-fs/my5/0/generated_videos/generated_video_0.mp4`
  - `ffprobe ... /root/autodl-fs/my5/0/rendering_4D_maps/merged_mask.mp4`
- 关键结果:
  - 两者都是:
    - `1280x720`
    - `16 fps`
    - `81 frames`
    - `5.0625 s`
- 结论:
  - `merged_mask.mp4` 可以作为训练 mask 的直接视频来源.
  - 只要抽帧策略一致, RGB 与 mask 可以稳定一一对应.

### 来源3: 现有脚本源码核查

- `convert.py`
  - 当前优先级:
    - 根目录直接视频
    - 递归 `rgb/`
    - 全局递归
  - 当前没有:
    - `generated_videos/` 语义优先级
    - mask 视频抽帧能力
- `scripts/run_lyra_colmap_fastgs.sh`
  - 当前只会在训练阶段尝试:
    - 读取显式 `--mask-dir`
    - 或读取 `<source>/masks`
  - 当前不会在 `prepare` 阶段主动从 mask 视频生成 mask 图.

## 综合发现

### 现象

- `/root/autodl-fs/my5` 不是“现有脚本能直接安全识别”的目录.
- 现有全局递归兜底对这类目录过宽.

### 当前假设

- 最稳的改造方式是:
  - 在 `convert.py` 层补 `generated_videos` 的优先发现
  - 同时支持一套“RGB 视频 -> input/`, `mask 视频 -> masks/`”的成对抽帧
  - 然后让 `run_lyra_colmap_fastgs.sh` 自动把生成的 `masks/` 接给训练

### 为什么更倾向这个方向

- 这样改动能复用现有主链路:
  - `feature_extractor`
  - `matcher`
  - `mapper`
  - `image_undistorter`
  - `train.py --mask_dir`
- 也更符合“改良胜过新增”:
  - 不是再造一条 `my5` 特例训练链
  - 而是把现有 COLMAP 入口变得真正认识这类多视角生成视频目录

## [2026-03-27 17:55:35] [Session ID: 28616] 笔记: 真实 `my5` 动态验证进展

## 来源

### 来源1: 单元与静态验证

- 命令:
  - `python3 -m py_compile convert.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m unittest tests.test_convert`
- 结果:
  - 均已通过

### 来源2: 真实 `prepare` 日志

- 真实命令:
  - `bash scripts/run_lyra_colmap_fastgs.sh --source-path /root/autodl-fs/my5 --fastgs-root data/my5_colmap_fastgs --colmap-bin /root/autodl-tmp/home/rais/.local/opt/colmap-env/bin/colmap --phase prepare --video-fps 16`
- 已观察到的关键输出:
  - `Discovered 12 video(s) ... using generated_videos_recursive mode`
  - `Extracted 972 frames into .../input`
  - `Extracted 972 masks into .../masks`
  - `Running feature extraction: ... colmap feature_extractor ... --FeatureExtraction.use_gpu 1`
  - `Running feature matching: ... colmap exhaustive_matcher ... --FeatureMatching.use_gpu 1`

### 来源3: 旁路文件核查

- 命令:
  - 统计 `data/my5_colmap_fastgs/input`
  - 统计 `data/my5_colmap_fastgs/masks`
  - 检查 `data/my5_colmap_fastgs/distorted/database.db`
- 结果:
  - `input = 972`
  - `masks = 972`
  - `database.db` 已存在, 当前约 `289M`

## 综合发现

### 现象

- 入口层已经不再误扫 `rendering_4D_maps` 里的辅助视频.
- COLMAP 4.0.2 已经接受新的 GPU 参数命名:
  - `--FeatureExtraction.use_gpu`
  - `--FeatureMatching.use_gpu`

### 当前结论

- 这轮代码改造已经把两个真正的阻塞点打通了:
  - 多镜头生成视频目录识别
  - COLMAP 4.x CLI 兼容
- 当前未完成项只剩“让真实 prepare 跑完并接正式训练”, 不再是代码路径不通.

## [2026-03-27 10:20:15] [Session ID: 80800] 笔记: `merged_mask.mp4` 语义纠正后的处理判断

## 来源

### 来源1: 用户新增说明

- 用户明确指出:
  - `rendering_4D_maps/merged_mask.mp4` 是“非深度数据区域”的 mask.
  - 它服务的是深度图链路, 不是普通训练 mask.

### 来源2: 当前代码路径复核

- `convert.py`
  - `build_video_extraction_plans()` 会自动调用 `find_generated_mask_video()`.
  - `prepare_input_directory()` 会把这类视频抽到 `<source_path>/masks`.
- `scripts/run_lyra_colmap_fastgs.sh`
  - 训练阶段会自动尝试识别 `<fastgs-root>/masks`.
- `scene/dataset_readers.py`
  - 即使 wrapper 不显式传 `--mask_dir`, 只要 `<scene_root>/masks` 存在, 仍会自动启用 mask.

### 来源3: 动态状态

- 后台 `prepare` 会话 `26742` 仍在 `exhaustive_matcher`.
- 这意味着当前错误只落在“提前抽出了 `masks/`”, 还没有污染训练结果.

## 综合发现

### 现象

- `merged_mask.mp4` 被自动抽成 `<fastgs-root>/masks` 后, 训练入口会把它当 alpha mask.
- 这会改变 photometric loss 的有效区域.

### 当前结论

- 之前那条“自动把 `merged_mask.mp4` 当训练 mask”的结论已经被用户证据推翻.
- 当前最正确的处理是:
  - 取消默认自动接线
  - 当前 `my5` 首轮训练按“无训练 mask”执行
  - 等后续如果真的要做深度辅助, 再单独设计它的挂载位置, 不和 RGB 训练 mask 共用 `masks/` 语义

## [2026-03-27 10:27:38] [Session ID: 80800] 笔记: 代码回滚与训练接力的验证结果

## 来源

### 来源1: 静态与单测验证

- 已执行:
  - `python3 -m py_compile convert.py scene/dataset_readers.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m unittest tests.test_convert tests.test_mask_loading`
- 结果:
  - 全部通过
  - 单测统计: `Ran 11 tests ... OK`

### 来源2: 当前数据目录状态

- `data/my5_colmap_fastgs` 当前可见目录:
  - `distorted`
  - `input`
  - `depth_masks_from_merged_mask_20260327_102621`
- 已把原 `masks/` 挪走.
- 挪走后的深度辅助 mask 帧数量:
  - `972`

### 来源3: 后台进程状态

- `prepare` 会话: `26742`
  - 仍在 `exhaustive_matcher`
- 训练等待器: `96836`
  - 会在 `images + sparse/0` 就绪后自动起 `output/my5_nomask_v1`

## 综合发现

### 已验证结论

- 当前仓库已经不再把 `merged_mask.mp4` 默认转换成训练 mask.
- 空的 `masks/` 目录也不会再被自动探测成有效训练 mask 目录.
- 当前 `my5` 数据根里的深度辅助 mask 已经被隔离出训练约定路径, 不会误伤首轮训练.

## [2026-03-27 12:13:40] [Session ID: 80800] 笔记: `my5` 图量降到 1/3 的参数换算

## 来源

### 来源1: 当前输入统计

- 当前 `my5` 抽帧结果:
  - 每视角 `81` 帧
  - `12` 个视角
  - 总计 `972` 张

### 综合换算

- 用户要求改成原图量 `1/3`.
- 因此目标应为:
  - 每视角 `27` 帧
  - 总计 `324` 张
- 原视频帧率是 `16 fps`.
- 目标抽帧率推导为:
  - `16 / 3 = 5.333333333333 fps`

## [2026-03-27 12:16:04] [Session ID: 80800] 笔记: `my5` 1/3 图量重跑的动态证据

## 来源

### 来源1: 单视角最小验证

- 命令:
  - `ffmpeg -y -i /root/autodl-fs/my5/0/generated_videos/generated_video_0.mp4 -vf 'fps=5.333333333333' ...`
- 结果:
  - `count=27`

### 来源2: 新 prepare 日志

- 新会话: `23869`
- 关键输出:
  - 抽帧阶段多次出现 `frame=   27`
  - `feature_extractor` 已完成 `Processed file [324/324]`
  - 随后进入:
    - `Running feature matching`
    - `Processing block [1/7, 1/7]`

### 来源3: 真实脚本阻塞与修复

- 现象:
  - `run_lyra_colmap_fastgs.sh --overwrite` 一开始报:
    - `拒绝删除非受控路径`
- 静态证据:
  - 脚本顶部用 `pwd`, 保留了 `/home/rais/FastGS` 这种符号链接路径.
  - 但 `normalize_path` 会把后续路径解析成真实目录 `/root/autodl-tmp/home/rais/FastGS`.
- 结论:
  - `safe_remove` 失败的根因是“脚本根路径和归一化路径不在同一个字符串口径”.
- 修复:
  - 已将脚本顶部的 `pwd` 改成 `pwd -P`.

## 综合发现

### 已验证结论

- `my5` 当前 1/3 图量口径已经稳定落地:
  - `12` 视角
  - 每视角 `27` 帧
  - 总计 `324` 张
- 新一轮 prepare 已经不再是旧的 `972` 图量任务.

## [2026-03-27 13:40:48] [Session ID: 80800] 笔记: `my5` 1/3 图量首轮训练的最新运行态

## 来源

### 来源1: prepare 完成日志

- `COLMAP sparse model '0': cameras=1, registered_images=324, points=30359`
- 随后成功执行:
  - `image_undistorter`
- 当前产物已落地:
  - `data/my5_colmap_fastgs/images`
  - `data/my5_colmap_fastgs/sparse/0`

### 来源2: 训练日志

- watcher 已自动启动:
  - `output/my5_nomask_v1/train_20260327_131214.log`
- 已观察到:
  - `[ITER 10000] Saving Gaussians`
  - `[ITER 10000] Saving Checkpoint`
  - `[ITER 20000] Saving Gaussians`
  - `[ITER 20000] Saving Checkpoint`
- 随后在约 `21000` 步附近报错:
  - `torch.AcceleratorError: CUDA error: an illegal memory access was encountered`

## 综合发现

### 已验证结论

- `my5` 这轮 1/3 图量的 COLMAP 已经完整跑通.
- FastGS 训练已经推进到 `20000+`, 不是没起起来.
- 当前阻塞点已经从 COLMAP 切换成训练后段的 CUDA 非法访问稳定性问题.

## [2026-03-27 13:43:30] [Session ID: 80800] 笔记: `my5` 续训策略判断

## 来源

### 来源1: 当前运行态事实

- `output/my5_nomask_v1/checkpoints/ckpt_20000.pth` 已存在.
- `output/my5_nomask_v1/point_cloud/iteration_20000/point_cloud.ply` 已存在.
- 首轮训练不是完全失败, 而是已经稳定跑到 `20000+`.

### 来源2: 项目经验

- `EXPERIENCE.md` 已记录:
  - 遇到随机 CUDA 非法访问时, `1000` 步分段 + checkpoint + 换 seed 重试在这台机器上已经被真实验证可用.

## 综合发现

### 当前结论

- 当前最合理的下一步不是重跑整轮, 也不是盲目改 CUDA 内核.
- 更稳的推进方案是:
  - 以 `ckpt_20000.pth` 为锚点
  - 逐段推进 `21000 -> 22000 -> ... -> 30000`
  - 每段优先保存新的 checkpoint
  - 若某段失败, 就在同一段换 seed 重试

## [2026-03-27 21:52:00] [Session ID: 245310] 笔记: `tmp_radii` 在 resume 路径中的生命周期判断

## 来源

### 来源1: `scene/gaussian_model.py` 静态阅读

- `tmp_radii` 在 `__init__` 里没有定义.
- 当前只在 `densify_and_prune_fastgs()` 里被赋值:
  - `self.tmp_radii = radii`
- 随后在同一函数尾部又被清空:
  - `self.tmp_radii = None`
- `prune_points()` 却直接假设该属性存在:
  - `if self.tmp_radii is not None:`
- `final_prune_fastgs()` 会调用 `prune_points()`.

### 来源2: `train.py` 静态阅读

- checkpoint 保存点:
  - `torch.save((gaussians.capture(...), iteration), checkpoint_path)`
- resume 恢复点:
  - `gaussians.restore(model_params, opt)`
- `capture()` 当前保存:
  - 参数张量
  - 优化器状态
  - `spatial_lr_scale`
- 没有 `tmp_radii`.

### 来源3: 动态证据

- `ckpt_21000.pth` 已成功落地.
- guarded resume 多次都在 `21000` 保存后, 进入 `final_prune_fastgs()` 时稳定报:
  - `AttributeError: 'GaussianModel' object has no attribute 'tmp_radii'`
- 这说明:
  - `20000 -> 21000` 训练主体已经成功
  - 真正失败的是保存后触发的 final prune 收尾逻辑

## 综合发现

### 当前主假设

- `tmp_radii` 属于瞬时运行态, 不应该作为 checkpoint 必需恢复字段.
- 更稳的修法是:
  - 让它在对象生命周期里始终存在
  - 默认值为 `None`
  - 在 `training_setup()` 这类“开始一轮训练”的入口重新清空

### 备选解释

- 如果后续验证发现 resume 后某些 densify 路径还依赖旧的 `tmp_radii` 内容, 才需要重新评估是否纳入 checkpoint.
- 但从当前静态代码看, 每次 densify 调用都会先用当轮 `radii` 覆盖它, 暂时没有这个证据.

## [2026-03-27 21:59:10] [Session ID: 245310] 笔记: `my5` resume 修复后的动态验证结果

## 来源

### 来源1: 最小动态复验

- 命令口径:
  - 从 `ckpt_20000.pth` 再跑一次 `20000 -> 21000`
- 关键结果:
  - `[ITER 21000] Saving Gaussians`
  - `[ITER 21000] Saving Checkpoint`
  - `Gaussian number: 48139`
  - `Training complete.`
- 结论:
  - 之前稳定复现的 `tmp_radii` 崩溃已经消失.

### 来源2: guarded 续训日志

- 新日志:
  - `output/my5_nomask_v1/guarded_resume_20260327_my5_after_fix.log`
- 连续成功分段:
  - `21000 -> 22000`
  - `22000 -> 23000`
  - `23000 -> 24000`
  - `24000 -> 25000`
  - `25000 -> 26000`
  - `26000 -> 27000`
  - `27000 -> 28000`
  - `28000 -> 29000`
  - `29000 -> 30000`
- 全部都是首个 seed 成功, 未触发重试.

## 综合发现

### 已验证结论

- 本次修复不只是“单测通过”.
- 它已经被真实 `my5` 续训链路验证过:
  - 两次 final prune 节点都已穿过
  - 最终训练稳定落到 `30000`

## [2026-03-27 22:39:00] [Session ID: 245310] 笔记: `my5_nomask_v1` 的正式评估结果

## 来源

### 来源1: `metrics.py` 真实运行

- 执行入口:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase metrics --model-path output/my5_nomask_v1 --overwrite`
- 动态证据:
  - `Metric evaluation progress: 41/41`
  - 说明当前 test 集共评估了 `41` 张图
- 汇总指标:
  - `SSIM = 0.8905442`
  - `PSNR = 27.1636581`
  - `LPIPS = 0.2032852`

### 来源2: 结果文件落盘

- 已生成:
  - `output/my5_nomask_v1/results.json`
  - `output/my5_nomask_v1/per_view.json`

## 综合发现

### 已验证结论

- `my5_nomask_v1` 当前已经具备可复查的正式 test 指标, 不再只是“训练完成但没有量化结果”.
- 后续如果要调优, 可以直接拿这组 `30000` 结果做基线对比.

## [2026-03-27 22:46:48] [Session ID: 019d2ea0-a35d-7a12-b8e9-9ebec510ea80] 笔记: `my5_nomask_v1` 续训到 `35000` 后的正式评估结果

## 来源

### 来源1: `35000` 轮正式评估命令

- 已执行:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase evaluate --model-path /root/autodl-tmp/home/rais/FastGS/output/my5_nomask_v1 --iteration 35000 --overwrite`
- 动态证据:
  - train render: `283` 张
  - test render: `41` 张
  - metrics method: `ours_35000`

### 来源2: `results.json`

- 文件:
  - `output/my5_nomask_v1/results.json`
- 当前平均指标:
  - `PSNR = 27.2039413`
  - `SSIM = 0.8910136`
  - `LPIPS = 0.2026276`

### 来源3: 与 `30000` 基线对比

- `30000` 基线:
  - `PSNR = 27.1636581`
  - `SSIM = 0.8905442`
  - `LPIPS = 0.2032852`
- `35000 - 30000` 增量:
  - `PSNR +0.0402832`
  - `SSIM +0.0004694`
  - `LPIPS -0.0006576`

### 来源4: `per_view.json` 的 test 视角观察

- 最弱视角仍较集中:
  - `00031.png`: `PSNR 23.2433`, `SSIM 0.8049`, `LPIPS 0.3074`
  - `00033.png`: `PSNR 23.4800`, `SSIM 0.8062`, `LPIPS 0.2846`
  - `00024.png`: `PSNR 24.5445`, `SSIM 0.8394`, `LPIPS 0.2435`
- 最强视角示例:
  - `00000.png`: `PSNR 32.5076`
  - `00014.png`: `PSNR 31.5081`
  - `00027.png`: `PSNR 30.5476`

## 综合发现

### 现象

- 把 `my5_nomask_v1` 从 `30000` 续到 `35000` 后, 三项 test 指标都朝更好的方向移动了.
- 但改变量不大, 属于“有提升, 但不是跃迁式改善”.

### 已验证结论

- 当前这组 `35000` 调参口径是稳定可跑通的.
- 相比 `30000`, 额外 `5000` 步确实带来了小幅收益.
- 当前结果里最差的 test 视角仍然集中在少数固定帧, 后续如果继续调优, 更像应该优先盯这些 worst views, 而不是只盯平均值.

## [2026-03-27 22:57:30] [Session ID: 019d2ea0-a35d-7a12-b8e9-9ebec510ea80] 笔记: `my5_nomask_v1` worst-view 定位报告已落盘

## 来源

### 来源1: 指标与机位聚类

- `ours_35000` 的 worst 5 为:
  - `00031 / 00033 / 00037 / 00024 / 00026`
- 机位聚合后最差的 test 视角组是:
  - `view 7`: `avg_psnr 24.1812`
  - `view 5`: `avg_psnr 24.9605`
  - `view 8`: `avg_psnr 26.7086`

### 来源2: 覆盖性核查

- worst 5 在同机位上都能找到前后 `1` 帧的 train 邻帧.
- 这说明当前问题不能简单归因成“test 离 train 太远”.

### 来源3: 图像三联图

- 已生成:
  - `specs/my5_worst_view_report_assets/worst5_contact_sheet.png`
  - `00031 / 00033 / 00037 / 00024 / 00026 / 00000` 的 panel 图
- 肉眼观察共性:
  - 误差主要集中在右侧高反射墙面 / 屏幕区域
  - 天花灯带与地面反射也比较重
  - 中央小车本体不是主要失真源

## 综合发现

### 当前主假设

- 这组 worst views 更像是“斜视角 + 高反射 + 细高亮边缘”叠加后的难点.

### 最强备选解释

- `view 7 / 5 / 8` 也可能叠加了轻微位姿偏差.
- 目前还缺少 COLMAP 轨迹层的直接证据, 不能把它写成已确认根因.

### 已验证结论

- worst-view 报告已经落盘到:
  - `specs/my5_worst_view_report_20260327.md`
- 当前最合理的后续顺序是:
  - 先查 `view 7 / 5 / 8` 的 COLMAP 轨迹
  - 再决定是否做下一轮训练调优

## [2026-03-28 01:48:27 UTC] [Session ID: 019d2fcd-edfd-7032-be9f-42f8bc79198c] 笔记: `my5_nomask_v1` 的 `35000` 视频导出验证

## 来源

### 来源1: 仓库现成导视频脚本

- 命令:
  - `timeout 20m bash scripts/run_lyra_colmap_fastgs.sh --phase render --model-path output/my5_nomask_v1 --video-iterations 35000 --video-sets both`
- 关键现象:
  - 脚本先重渲染 `ours_35000`
  - 然后分别调用 `ffmpeg` 生成 train/test 两个 mp4
  - 进程退出码为 `0`

### 来源2: 导出后动态验证

- 文件存在:
  - `output/my5_nomask_v1/videos/train_iter35000.mp4`
  - `output/my5_nomask_v1/videos/test_iter35000.mp4`
- `ffprobe` 结果:
  - train:
    - `codec_name=h264`
    - `width=1280`
    - `height=720`
    - `r_frame_rate=24/1`
    - `duration=11.792000`
    - `size=4706022`
  - test:
    - `codec_name=h264`
    - `width=1280`
    - `height=720`
    - `r_frame_rate=24/1`
    - `duration=1.709000`
    - `size=1149034`

## 综合发现

### 当前结论

- `35000` 轮视频已经成功导出.
- 当前导出口径与仓库 wrapper 默认视频口径一致:
  - `24 fps`
  - `h264`
  - `1280x720`
- 这次不只是“渲染帧存在”, 而是可直接播放的 mp4 已经落盘.

## [2026-03-28 00:10:40] [Session ID: 019d2ea0-a35d-7a12-b8e9-9ebec510ea80] 笔记: `my5` 的 COLMAP 位姿回查结果

## 来源

### 来源1: `images.bin` 轨迹与点支持统计

- 已直接读取:
  - `data/my5_colmap_fastgs/sparse/0/images.bin`
- 关键结论:
  - `view 7` 的 `obs_mean` 全部机位最低: `852.3`
  - `view 7` 的 `ratio_mean` 全部机位最低: `0.4582`
  - `view 7` 的 `step_mean` 全部机位最高: `1.2833`
  - `view 7` 的 `step_max` 全部机位最高: `2.2542`
- `view 5` 是次级可疑:
  - `step_mean` 第二高: `0.6159`
- `view 8` 轨迹平顺, 更不像 pose 主导问题:
  - `step_mean = 0.2273`

### 来源2: worst-view 对齐

- `00031` / `00033` 都落在 `view 7`
- 它们的 COLMAP 点支持分别只有:
  - `590`, `ratio 0.2943`
  - `775`, `ratio 0.4149`
- 对照 best-view `00000`:
  - `1488`, `ratio 0.8953`

### 来源3: 可视化图表

- 已生成:
  - `pose_topdown_focus_views.png`
  - `pose_quality_scatter.png`
  - `focus_view_frame_diagnostics.png`
  - `pose_projection_focus_views.png`
- 这些图都已经被正式收进:
  - `specs/my5_colmap_pose_report_20260328.md`

## 综合发现

### 当前主假设

- `view 7` 有最强的 pose 异常嫌疑.
- `view 5` 有中度嫌疑.
- `view 8` 更像高反射与细亮边缘的表达难点.

### 已验证结论

- 当前已经不只是“worst-view 集中在少数机位”.
- 现在还多了一层 COLMAP 证据:
  - `view 7` 同时具备最低点支持和最高轨迹抖动.
- 因此下一步最值得先做的是继续追 `view 7`, 而不是直接继续堆训练迭代.

## [2026-03-28 02:24:00 UTC] [Session ID: 79642ac4-ccdf-404a-967b-1342f85cc2bd] 笔记: `my5` 朝向连续性与相对位姿复核结果

## 来源

### 来源1: 新分析脚本

- 脚本:
  - `scripts/analyze_colmap_pose_continuity.py`
- 输入:
  - `data/my5_colmap_fastgs/sparse/0/images.bin`
  - `specs/my5_colmap_pose_report_assets/pose_report_data.json`
- 输出:
  - `specs/my5_pose_continuity_report_assets/*.png`
  - `specs/my5_pose_continuity_report_assets/pose_continuity_data.json`

### 来源2: 单机位朝向连续性统计

- `view 7`
  - `rotation_mean = 3.6893`
  - `rotation_max = 6.0948`
  - `forward_mean = 3.6831`
  - `forward_max = 6.0883`
- `view 5`
  - `rotation_mean = 1.9935`
  - `rotation_max = 2.8770`
- `view 8`
  - `rotation_mean = 0.6520`
  - `rotation_max = 0.9852`

### 来源3: `view 7` 的逐帧峰值

- 朝向峰值主要集中在:
  - `frame 3`
  - `frame 4`
  - `frame 5`
  - `frame 10`
  - `frame 11`
- 其中前段 `frame 3 ~ 5` 同时伴随:
  - 极低 `observed_ratio`
  - 极高 `translation_step`

### 来源4: 邻机位 pair 统计

- `7-8`
  - `delta_relative_rotation_mean = 2.1338`
  - 全局相邻机位最高
- `6-7`
  - `delta_relative_rotation_mean = 1.9313`
  - 全局相邻机位第二
- 对照:
  - `4-5 = 1.3843`
  - `8-9 = 1.3272`

### 来源5: worst-view 回对

- `00031 -> view 7 frame 6`
  - `rotation_step = 3.5802`
  - `forward_step = 3.5615`
  - `observed_ratio = 0.2943`
- `00033 -> view 7 frame 22`
  - `rotation_step = 2.1979`
  - `forward_step = 2.1958`
  - `observed_ratio = 0.4149`
- `00037 -> view 8 frame 27`
  - `rotation_step = 0.4322`
  - `forward_step = 0.4240`

## 综合发现

### 现象

- `view 7` 不只是平移轨迹跳.
- 它的朝向连续性也明显差于其他机位.
- 围绕 `view 7` 的相邻 pair, 相对位姿变化也更不稳.

### 当前主假设

- `view 7` 有真实 pose 连续性异常.
- 它已经不是“只凭相机中心轨迹猜的”.

### 最强备选解释

- `view 7` 的高反射 / 弱纹理区域, 也可能同时在拖低特征匹配质量.
- 所以更稳的口径是:
  - pose 异常和材质难点可能是叠加关系
  - 还不是单一根因已唯一确认

### 已验证结论

- 新报告已落盘:
  - `specs/my5_pose_continuity_report_20260328.md`
- 当前证据链已经从:
  - worst-view
  - 点支持
  - 相机中心轨迹
  扩展到:
  - 朝向连续性
  - 相邻机位相对位姿连续性
- 这让 `view 7` 成为更硬的 pose 可疑点.

## [2026-03-28 02:49:00 UTC] [Session ID: 7f1d2edd-4a39-4aee-b0fd-79f9701c57e7] 笔记: `my5` 局部 COLMAP 对照实验结果

## 来源

### 来源1: 局部实验数据准备

- 子集:
  - `view 6 / 7 / 8`
  - `frame 1 ~ 8`
  - 共 `24` 张图
- 数据目录:
  - `data/my5_local_pose_compare_v1`
  - `data/my5_local_pose_compare_v2_refinefocal`

### 来源2: 两版局部 COLMAP

- `local_fix`
  - 固定内参 `592.1701, 640, 360`
- `local_refine`
  - 同样用上面的 prior
  - 但允许 BA refine focal
- 两版都:
  - 成功注册 `24/24`
  - 但都要在“放宽初始化约束”后才真正起模型

### 来源3: `view 7` 的局部 vs 全局统计

- 全局:
  - `step_mean = 1.3726`
  - `rot_mean = 3.9438`
  - `obs_mean = 675.375`
- `local_fix`
  - `step_mean = 1.8088`
  - `rot_mean = 3.8531`
  - `obs_mean = 393.0000`
- `local_refine`
  - `step_mean = 1.7861`
  - `rot_mean = 3.7371`
  - `obs_mean = 390.1250`

### 来源4: 邻机位 pair 对照

- `6-7`
  - 全局 `delta_rot_mean = 2.1944`
  - `local_fix = 2.1904`
  - `local_refine = 2.1274`
- `7-8`
  - 全局 `delta_rot_mean = 2.7584`
  - `local_fix = 2.7345`
  - `local_refine = 2.6545`
- 但同时:
  - 局部两版的 `delta_dist_mean` 都明显更高

### 来源5: 焦距变化

- `local_refine` 最终内参:
  - `571.6432, 640, 360`
- 相比全局 prior:
  - `592.1701, 640, 360`

## 综合发现

### 现象

- 局部重建没有把 `view 7` 前段明显修顺.
- 允许 focal refine 也没有带来本质变化.

### 当前主假设

- “全局上下文把 `view 7` 解坏了”不再是当前最强解释.

### 最强备选解释

- `view 7` 这段局部素材本身就难.
- 或者这段局部几何约束天然偏弱.
- 所以不管切全局还是切局部, 高抖结构都会保留.

### 已验证结论

- 新报告已落盘:
  - `specs/my5_local_colmap_compare_20260328.md`
- 当前最合理的下一步优先级改成:
  - 先做 `view 7 frame 3 ~ 6` 的筛帧对照
  - 而不是继续缩局部 COLMAP 窗口

## [2026-03-27 18:55:48 UTC] [Session ID: ebb3c562-1702-4ea2-8e98-ed18d0a9bada] 笔记: `my5` 更大上下文 `widecontext` 对照结果

## 来源

### 来源1: `v3_widecontext` 稀疏模型复查

- 路径:
  - `data/my5_local_pose_compare_v3_widecontext/distorted/sparse/0`
- 复查结果:
  - `images.bin` 中有 `48` 张图
  - `cameras.bin` 中有 `1` 个 `SIMPLE_PINHOLE`
  - 相机参数:
    - `488.9067, 640, 360`
- 这里要明确纠正:
  - 先前把 `read_points3D_binary()` 的返回 tuple 长度误读成了“点数 = 3”
  - 复查后实际稀疏点数是 `4710`

### 来源2: 同口径朝向连续性脚本

- 输出目录:
  - `specs/my5_local_pose_compare_v3_widecontext_assets`
- `view 7`:
  - `obs_mean = 490.9167`
  - `ratio_mean = 0.2575`
  - `step_mean = 2.3200`
  - `step_max = 3.5823`
  - `rot_mean = 3.4714`
  - `rot_max = 4.8993`
- 对照全局同范围:
  - `obs_mean = 852.2963`
  - `ratio_mean = 0.4582`
  - `step_mean = 1.2833`
  - `step_max = 2.2542`
  - `rot_mean = 3.6893`
  - `rot_max = 6.0948`

### 来源3: 邻机位 pair 对照

- `5-6`
  - 全局 `delta_dist_mean = 0.1292`
  - `widecontext = 0.2090`
- `6-7`
  - 全局 `delta_rot_mean = 1.9313`
  - `widecontext = 1.8286`
  - 全局 `delta_dist_mean = 0.6830`
  - `widecontext = 1.2944`
- `7-8`
  - 全局 `delta_rot_mean = 2.1338`
  - `widecontext = 2.3023`
  - 全局 `delta_dist_mean = 0.7345`
  - `widecontext = 1.5666`

### 来源4: 报告与汇总资产

- 正式报告:
  - `specs/my5_local_colmap_compare_20260328.md`
- 汇总 JSON:
  - `specs/my5_local_colmap_compare_assets/comparison_summary.json`

## 综合发现

### 现象

- `widecontext` 不是空模型.
- 但它没有把 `view 7` 修顺.
- 更具体地说:
  - rotation 只有轻微下降
  - translation 明显更差
  - 点支持也没有变强

### 当前主假设

- “局部窗口太小导致约束不够”已经不是当前最强解释.

### 最强备选解释

- `view 7` 这段素材本身就难.
- 同时 COLMAP 在这段上还可能存在数值稳定性问题.
- 所以不管缩窗口还是放窗口, 都不会自然变稳.

### 已验证结论

- 更小窗口没有明显改善.
- 更大窗口也没有明显改善.
- 当前更稳的下一步是:
  - 做带 frame-gap 保护的筛帧对照
  - 或者改更保守的 mapper 参数

## [2026-03-27 18:58:52 UTC] [Session ID: ebb3c562-1702-4ea2-8e98-ed18d0a9bada] 笔记: 连续性分析脚本已补 `frame_gap` 感知

## 来源

### 来源1: 脚本改造

- 文件:
  - `scripts/analyze_colmap_pose_continuity.py`
- 新能力:
  - `--transition-summary-mode all|contiguous`
  - `frame_details[*].frame_gap`
  - `pair_details[*].frame_gap`

### 来源2: 最小单测

- 新增:
  - `tests/test_analyze_colmap_pose_continuity.py`
- 覆盖点:
  - view gap 会不会污染 `step_mean`
  - pair shared frame gap 会不会污染 `delta_relative_distance_mean`

### 来源3: 动态验证

- 通过:
  - `python3 -m py_compile scripts/analyze_colmap_pose_continuity.py tests/test_analyze_colmap_pose_continuity.py`
  - `pixi run python -m unittest tests.test_analyze_colmap_pose_continuity tests.test_convert`
- 真实冒烟:
  - 在 `v3_widecontext` 上跑了:
    - `--transition-summary-mode contiguous`
  - 已确认 JSON 顶层写出:
    - `transition_summary_mode = contiguous`
  - 明细里出现:
    - `frame_gap`
    - `is_contiguous_transition`

## 综合发现

### 现象

- 现有脚本原来默认把 surviving frame 的排序邻接直接当连续帧.
- 这在删帧实验里会把 `2 -> 7` 这样的跨 gap 跳跃混进连续性 summary.

### 当前主假设

- 先把量尺修好, 比立刻开删帧实验更值.

### 已验证结论

- 现在脚本已经能安全承接下一轮筛帧对照.
- 后面只要删掉 `view 7 frame 3 ~ 6`, 就可以直接用:
  - `--transition-summary-mode contiguous`
  去拿不被 gap 污染的连续性指标.

## [2026-03-28 12:12:00 UTC] [Session ID: 019d3478-98b2-7fa1-a395-f4ccc3012bf0] 笔记: FastGS 离线渲染链路与 Unity 画质差异候选

### 已观察到的事实
- `render.py` 直接调用 `render_fastgs(...)` 并把输出保存为 PNG, 没有看到额外的 tone mapping / gamma / 后处理链.
- `gaussian_renderer/__init__.py` 直接对接 `diff_gaussian_rasterization_fastgs` 的 CUDA rasterizer.
- 颜色不是简单 RGB 点色, 而是 `SH degree=3` 的球谐表示; 运行时由 CUDA 侧 `computeColorFromSH(...)` 或 Python 侧 `eval_sh(...)` 按视角求色.
- `utils/camera_utils.py` 默认会把宽度大于 `1600` 的输入自动缩到 `1.6K`, 除非显式传 `-r 1`.
- `arguments/__init__.py` 显示训练和渲染默认 `mult=0.5`, `sh_degree=3`, `white_background=False`.
- `scene/gaussian_model.py` 保存的 `point_cloud.ply` 包含: `x/y/z`, `f_dc_*`, `f_rest_*`, `opacity`, `scale_*`, `rot_*`. 这说明导出结果是完整 3DGS 参数集, 不是普通彩色点云.
- `README.md` 明确写了该表示与 vanilla 3DGS 一致, 推荐用官方 SIBR viewer 或 Supersplat 做交互查看.

### 候选假设
1. 如果 Unity 插件没有完整支持 `f_rest_*` 高阶 SH, 只用了 DC 色或低阶 SH, 会明显丢失视角相关高光和细节.
2. 如果 Unity 插件没有严格复现 `opacity + scale + rotation + EWA splat + Compact Box(mult)` 这套栅格化口径, 边缘、覆盖、厚度和透明叠加都会变差.
3. 如果训练时使用了 `-r 1` 或较高输入分辨率, 但 Unity 端只是以更低渲染分辨率、不同抗锯齿、不同颜色空间显示, 观感会下降.
4. 如果训练/离线渲染使用的 `mult` 与 Unity 插件内部覆盖框策略不同, 可能出现漏 splat、边缘发虚或体积感变薄.
5. 如果用户导给 Unity 的不是训练完成迭代的 `point_cloud/iteration_xxx/point_cloud.ply`, 而是 `input.ply` / `points3D.ply` / 被二次转换丢字段的资产, 效果会大幅变差.

### 当前结论状态
- 以上第 1/2/3/4/5 条里, 第 5 条可以直接靠文件名与头信息验证.
- 第 1/2/3/4 条目前属于有静态证据支撑的候选假设, 但还缺你所用 Unity 插件版本、导入器实现、实际截图或导入日志, 不能直接当成已确认根因.

## [2026-03-28 12:18:00 UTC] [Session ID: 019d3478-98b2-7fa1-a395-f4ccc3012bf0] 笔记: Unity 侧公开实现的补充参考

## 来源

### 来源1: `aras-p/UnityGaussianSplatting` README
- 链接: https://github.com/aras-p/UnityGaussianSplatting
- 关键信息:
  - 作者自述: `Toy Gaussian Splatting visualization in Unity`.
  - README 明确要求输入 original 3DGS 的 `point_cloud/iteration_*/point_cloud.ply`.
  - 导入时存在 compression options 和 asset quality level.
  - 文档明确说它只实现 realtime visualization 这一段, 不是完整训练栈.

## 综合发现

### 对当前问题的价值
- 这说明“Unity 插件显示略差”并不罕见, 因为很多 Unity 实现的目标本来就是实时查看和集成, 不是严格对齐官方离线参考图.
- 如果用户的插件带有压缩、质量档位、移动端兼容或跨图形 API 限制, 都可能进一步拉开与 FastGS 离线 render 的差距.
