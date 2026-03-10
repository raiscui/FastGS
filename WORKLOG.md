# WORKLOG

## 2026-02-25
- 初始化四文件上下文,用于记录本次任务过程与交付物.
- 生成 `AGENTS.md` 贡献指南: 覆盖项目结构、Conda 环境搭建、训练/渲染/指标命令、代码风格与提交/PR 约定.
- 使用 pixi 初始化依赖环境:
  - 新增 `pixi.toml`/`pixi.lock`,并通过 `pixi run setup` 统一编译安装本地 CUDA 扩展.
  - 新增 `.gitignore` 忽略 `.pixi/`、`output/`、`datasets/` 等运行产物.
  - README 增补 pixi 安装与运行示例.
- 预训练模型镜像检查:
  - 仓库内仅在 `README.md` 有 HuggingFace 预训练模型链接.
  - 已检查 ModelScope,当前未找到 `Goodsleepeverday/fastgs` 对应模型页面,因此未替换链接.

## 2026-02-26
- 在本机执行依赖安装:
  - `pixi install --frozen` 成功(按 `pixi.lock` 复现环境).
  - `pixi run setup` 成功编译并以 editable 方式安装 3 个本地 CUDA 扩展.
  - 已用 `pixi run python` 验证 `torch` 与本地扩展 import 正常.
- 梳理 `train_big.sh`/`train_base.sh` 的训练参数:
  - 对照 `train.py`/`utils/fast_utils.py`/`scene/gaussian_model.py`/CUDA rasterizer,确认 `densification_interval`、`loss_thresh`、`grad_abs_thresh`、`dense`、`highfeature_lr`、`lowfeature_lr`、`mult`、`optimizer_type`、`test_iterations` 的真实作用与相互关系.
- 将参数说明落盘到 `docs/`:
  - 新增 `docs/fastgs-train-scripts.md`,作为 `train_base.sh`/`train_big.sh` 的参数速查与调参指南.
- 已将当前工作区改动提交并推送到 `https://github.com/raiscui/FastGS.git`(remote: `raiscui`, branch: `main`).


## [2026-03-10 04:10:59 UTC] 任务名称: 改造 convert.py 支持直接处理整个视频文件夹

### 任务内容
- 改造 `convert.py`, 让它在保留旧 `input/` 图片模式的同时,支持直接把视频目录视为一套输入.
- 为视频模式增加抽帧与重跑控制参数,并保持训练侧目录结构不变.

### 完成过程
- 重构 `convert.py` 的命令执行方式,从 `os.system` 改为 `subprocess.run` 列表参数,避免路径中有空格时的命令拼接问题.
- 新增 `--video_path`、`--video_fps`、`--ffmpeg_executable`、`--overwrite`,并实现“直接 `-s <视频目录>` 自动识别视频模式”的逻辑.
- 让视频模式自动抽帧到 `<source_path>/input`,再复用现有 `feature_extractor -> exhaustive_matcher -> mapper -> image_undistorter` 流程.
- 用 fake `ffmpeg` 和 fake `colmap` 完成最小动态验证,确认视频模式和旧图片模式都能产出期望目录结构.

### 总结感悟
- 这类“输入源扩展”最稳的做法,不是改训练侧,而是把新输入先规范化为旧流程认识的目录结构.
- 对命令行脚本来说,把字符串拼接改成参数列表,能顺手消掉很多路径转义与空格类隐患.


## [2026-03-10 05:41:24 UTC] 任务名称: 让 convert.py 兼容 `<root>/<index>/rgb/*.mp4` 目录结构

### 任务内容
- 根据用户真实素材布局,补齐 `convert.py` 对多级子目录视频的发现逻辑.
- 确保脚本优先扫描 `rgb` 目录中的视频,避免误收集 `debug` / `manifests` 等其他目录内容.

### 完成过程
- 新增 `discover_video_files(...)`,按 `direct -> rgb_recursive -> recursive` 的优先级发现视频输入.
- 新增 `build_frame_prefix(...)`,让抽帧后的文件名带上来源目录信息,例如 `001_0_rgb_00172_000001.jpg`,方便排查多视频混合输入.
- 对真实目录做了只读验证,确认 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 会被识别为 `rgb_recursive`,共 6 个视频.
- 用仿真目录完成最小动态验证,确认 `<root>/<index>/rgb/*.mp4` 结构能完整走通 `convert.py` 的抽帧与 COLMAP 流程.

### 总结感悟
- 对多级媒体目录,最安全的策略不是直接全局递归,而是先锚定业务语义明确的目录名,例如这里的 `rgb`.
- 当不同子目录下的视频文件名完全一样时,抽帧输出最好带上相对路径前缀,否则后续排错非常痛苦.


## [2026-03-10 06:02:57 UTC] 任务名称: 在真实 flashvsr_reference 数据上完成 SfM 转换

### 任务内容
- 在真实数据目录 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 上执行 `convert.py`.
- 验证递归 `rgb` 视频发现逻辑,并产出可用于 FastGS 训练的数据目录结构.

### 完成过程
- 检查环境后发现本机缺少 `colmap`,使用 `apt-get install -y colmap` 安装系统包恢复转换依赖.
- 验证 `colmap -h` 显示 `without CUDA`,因此最终采用 `--no_gpu` 执行真实转换.
- 成功从 6 个 `rgb/00172.mp4` 视频抽出 60 张图片,完成 COLMAP 的 feature extraction、matching、mapper 与 undistort.
- 最终在真实目录中生成了 `input/`、`images/`、`sparse/0/`、`distorted/sparse/0/` 等完整输出.

### 总结感悟
- 对这台机器而言, `convert.py` 的稳定运行前提不是 GPU,而是显式认清本机 `colmap` 是 CPU 版并加 `--no_gpu`.
- 即便视频原始分辨率较高(2560x1408),在 60 张级别上 CPU 版 COLMAP 仍可在可接受时间内完成稀疏重建.

## [2026-03-10 06:23:00 UTC] 任务名称: 对真实 full_scale2x 数据完成 100 iter 烟雾训练验证

### 任务内容
- 回收并核查上一轮 100 iter smoke test 会话状态, 确认真实训练是否已经完成.
- 验证真实数据 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 已能被 FastGS 正常读取并进入训练.
- 顺带核查 `--video_fps 2` 在这批视频上的真实抽帧数量.

### 完成过程
- 通过会话 `34025` 的训练日志确认短训练已经完整跑完, 输出目录实际落在默认路径 `output/032e12b6-bfff-411f-a6c6-088cda08ac69`.
- 核查输出目录, 确认存在 `cameras.json`、`cfg_args`、`input.ply` 和 `point_cloud/iteration_100/point_cloud.ply`, 且点云 header 对应 21007 个顶点.
- 用 `ffprobe` 检查 6 段源视频, 确认每段约 5.04 秒、24.01 fps, 在 `--video_fps 2` 下各抽 10 张, 合计 60 张.

### 总结感悟
- 对这种长链路任务, 先回收后台会话再决定是否重跑, 比盲目再开一轮训练更稳也更省时间.
- `--video_fps` 最终控制的是“目标采样频率”, 不是“每隔多少原始帧取一张”; 真正落盘数量要看视频总时长, 而不是只看原始 fps.

## [2026-03-10 06:41:00 UTC] 任务名称: 对 full_scale2x 启动并完成 `--resolution 1` 正式训练

### 任务内容
- 基于真实数据 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 启动一轮正式 FastGS 训练.
- 显式传入 `--resolution 1`, 避免训练阶段自动缩到 1.6K.
- 跑完整个 30000 iter, 并核查最终输出目录与点云产物.

### 完成过程
- 创建独立输出目录 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357`, 并用 `pixi run python train.py` 启动正式训练.
- 通过 `cfg_args` 与训练日志确认 `resolution=1` 已生效, 且训练不再打印自动缩图提示.
- 正式训练于 2026-03-10 06:40 UTC 完成: 总耗时约 332.24 秒, 最终 Gaussian 数量 154271, 成功生成 `point_cloud/iteration_30000/point_cloud.ply`.

### 总结感悟
- 对已经完成 SfM 的中小规模自采数据, 先用 100 iter smoke test 排链路, 再切到 `--resolution 1` 正式训练, 是一条很稳的落地路径.
- 这台 A800 80GB 对这套 60 视角、原始宽度训练是扛得住的, 后续更值得关注的是渲染结果和视觉质量, 而不是能否跑通.

## [2026-03-10 07:08:00 UTC] 任务名称: 评估 full_scale2x 正式训练结果的 PSNR

### 任务内容
- 对正式训练目录 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357` 进行渲染与指标评估.
- 核查是否存在 test 集可用于标准 PSNR 统计.
- 在没有 test 集的前提下, 给出当前可验证的 train 集 PSNR.

### 完成过程
- 先执行 `render.py --skip_train`, 动态确认 test 集为 0 帧.
- 对照 `cfg_args` 与 `scene/dataset_readers.py`, 确认原因是本轮训练使用了 `eval=False`, 因此 COLMAP 数据全部进了 train, test 集为空.
- 随后执行 `render.py --skip_test` 渲染 60 个 train 视角, 并用仓库 `psnr` / `ssim` 实现完成均值统计.

### 总结感悟
- FastGS 这套仓库里, “能训练成功”不等于“能直接得到 test PSNR”; 是否有 test 指标取决于训练时是否启用了 `--eval`.
- 如果只是想快速判断模型是否学到了东西, train 集 PSNR 可以先看; 但要做正式对比, 还是要重新走带 `--eval` 的评估路径.
