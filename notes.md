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
