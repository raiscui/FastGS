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

## [2026-03-10 08:24:49 UTC] 任务名称: 核查本机 SSH 是否允许密码登录

### 任务内容
- 在不接触任何密码内容的前提下,确认本机 `sshd` 是否允许密码登录.
- 同时确认监听端口与是否存在配置覆盖,避免只看单文件造成误判.

### 完成过程
- 先读取六文件上下文,然后追加本次任务计划到 `task_plan.md`.
- 用 `sshd -T` 读取有效配置,确认 `passwordauthentication yes`、`permitrootlogin yes`、`port 23`.
- 再检查 `/etc/ssh/sshd_config` 与 `/etc/ssh/sshd_config.d`,确认当前没有额外 `.conf` 覆盖主配置.
- 通过 `pgrep` 和 `lsof` 验证运行态,确认 `sshd` 正在监听 `*:23`.

### 总结感悟
- 判断 SSH 是否允许密码登录时,优先看 `sshd -T`,再回看配置来源,比只 grep 主配置更稳.
- 这台机器的 SSH 不是默认 `22` 端口,而是 `23`,后续远程连接时必须显式带端口.

## [2026-03-11 05:46:33 UTC] 任务名称: 判断本机是否可以支持 GPU 版 COLMAP

### 任务内容
- 核查 `convert.py` 是否需要改代码才能支持 GPU 版 `colmap`.
- 核查当前机器的 GPU、CUDA 与编译环境是否具备落地条件.
- 给出最稳妥的安装与接入建议.

### 完成过程
- 先读取项目上下文文件,避免重复判断历史上已经确认过的 `colmap` 环境信息.
- 通过 `colmap -h` 与 `convert.py` 源码确认: 脚本默认就会在未传 `--no_gpu` 时请求 COLMAP 使用 GPU, 当前缺口不在脚本层.
- 继续核查 `nvidia-smi`、`nvcc`、`cmake`、`g++`, 确认本机具备 A800 GPU、NVIDIA 驱动、CUDA 编译器与基础 C++ 构建链.
- 最后结合官方安装文档,确认 Linux 默认仓库中的 `colmap` 包通常不带 CUDA 支持, 若要 GPU 版应单独编译或单独安装 CUDA 构建.

### 总结感悟
- 这个仓库对 GPU 版 COLMAP 的关键设计其实已经有了: `--colmap_executable` 允许并行保留多份 `colmap` 二进制,不必粗暴替换系统包.
- 真正该改进的不是“再加一层 GPU 开关”,而是给用户更明确的启动期检测与提示,避免把 CPU 版 `colmap` 误当成脚本不支持 GPU.

## [2026-03-11 06:09:49 UTC] 任务名称: 在 /workspace 编译支持 CUDA 的 COLMAP

### 任务内容
- 在 `/workspace` 下编译并安装一份支持 CUDA 的 `colmap`.
- 保留系统已有 CPU 版 `/usr/bin/colmap`, 避免覆盖现有可工作路径.
- 形成可直接给 `convert.py` 使用的新二进制路径, 并完成动态验证.

### 完成过程
- 先读取项目上下文与官方安装口径, 确认 Linux 默认仓库的 `colmap` 通常不带 CUDA, 本次应走源码编译.
- 通过 `apt-get` 安装了 Boost / Eigen / FreeImage / Glog / Ceres / SuiteSparse / GLEW / Qt6 / CGAL / Ninja / GCC10 等构建依赖.
- 选择官方 `3.12.6` 版本, 拉取到 `/workspace/colmap-cuda-src-3.12.6`, 并使用以下独立目录组织产物:
  - 源码: `/workspace/colmap-cuda-src-3.12.6`
  - 构建: `/workspace/colmap-cuda-build-3.12.6`
  - 安装: `/workspace/colmap-cuda-install-3.12.6`
- 用 `gcc-10/g++-10` 与 `nvcc 12.6` 完成 CMake 配置和 Ninja 编译, 关键配置输出明确显示:
  - `Enabling CUDA support (version: 12.6.20, archs: 80)`
  - `Enabling GPU support (OpenGL: ON, CUDA: ON)`
- 安装后验证新二进制 `-h` 输出为 `COLMAP 3.12.6 ... with CUDA`, 并进一步用 2 张真实图片执行 `feature_extractor --SiftExtraction.use_gpu 1`, 日志出现 `Creating SIFT GPU feature extractor`, 说明 GPU SIFT 路径实际跑通.

### 总结感悟
- 对这个仓库来说, 最稳的接入方式不是替换系统 `colmap`, 而是并行保留一份 CUDA 版, 再通过 `--colmap_executable` 指向它.
- 这次真正关键的验证不是 `ldd` 或 `-h` 单独通过, 而是实际跑一次 GPU 特征提取. 只有这样才能证明编译结果真的能服务 `convert.py`.

## [2026-03-11 06:14:10 UTC] 任务名称: 固化 GPU 版 COLMAP 构建文档

### 任务内容
- 将这次在 `/workspace` 真实编译并验证成功的 CUDA 版 `colmap` 路径沉淀为仓库文档.
- 让后续使用者可以直接复用目录、命令、验证方法与 `convert.py` 的接入方式.
- 保证文档可发现, 而不是只存在于一次性聊天记录里.

### 完成过程
- 先读取现有 `docs/fastgs-train-scripts.md` 与 README 的风格, 确定新文档应以“真实验证路径”而不是“泛官方安装说明”为主.
- 新增 `docs/colmap_cuda_build.md`, 写入了依赖安装、源码目录、CMake 参数、编译与安装命令、静态验证、动态验证、`convert.py --colmap_executable` 接入示例以及环境注意事项.
- 在 `README.md` 的环境设置段落补充了一个轻量入口链接, 避免文档写完后没人知道它存在.
- 最后重新核对 README 片段和新文档正文, 确认关键路径和命令都与本轮真实执行结果一致.

### 总结感悟
- 对环境型问题, 最有价值的文档不是“理论上怎么装”, 而是“这台机器上怎样已经装成了”.
- 单独新增 `docs/` 文档还不够, 最少还要给 README 一个入口, 否则文档很容易再次变成隐形知识.

## [2026-03-11 06:26:20 UTC] 任务名称: 整理 `data/s01` 的 3DGS 前处理与训练命令文档

### 任务内容
- 将 `data/s01` 这套 3ds Max 渲染的多机位 JPG 序列图,整理成一份可直接复制执行的 FastGS 文档.
- 文档覆盖 COLMAP 稀疏重建、FastGS 可训练目录整理、A800 80G 下的 smoke test 与正式训练命令.
- 把用户指定的 GPU 版 COLMAP 路径统一固化到文档里.

### 完成过程
- 先重新核对 `data/s01` 的最新状态,确认 `C01pick` ~ `C06pick` 六个目录当前都已存在且各有 51 张图.
- 对照 `scene/__init__.py`、`scene/dataset_readers.py` 与 `convert.py`,确认本仓库读取 COLMAP 数据的真实要求,并判断 `convert.py` 当前默认假设不适合多机位目录.
- 新增 `docs/s01_3dgs_workflow.md`, 使用手动 COLMAP CLI 作为主线,统一定义 `COLMAP_BIN=/workspace/colmap-cuda-install-3.12.6/bin/colmap`.
- 在 `README.md` 增加 `data/s01` 文档入口, 并对 smoke test、正式训练、`--eval` 评估口径做了自检.

### 总结感悟
- 对“渲染图 + 多机位目录”这类输入, 最容易踩坑的不是训练命令本身, 而是前处理口径是否把“每个文件夹就是一台相机”表达清楚.
- 用户给出的环境约束如果足够明确, 最好的文档不是泛讲原理, 而是把路径、命令和适用条件一次性写成可复制版本.

## [2026-03-11 06:51:20 UTC] 任务名称: 为 `data/s01` 落地一键脚本并完成真实 smoke test

### 任务内容
- 为当前 `data/s01` 提供一个真正可直接执行的脚本, 从多机位 JPG 序列一路跑到 FastGS 训练.
- 修复用户当前 `mapper` 报 “No images with matches found in the database” 的实际流程问题.
- 在真实机器上完成端到端 smoke test, 给出动态验证证据.

### 完成过程
- 先对用户失败现场做静态和动态核查,确认 `database.db` 中 `cameras/images/keypoints/matches/two_view_geometries` 全部为 0.
- 随后做了最小对照实验,验证“目录软链接”会让 COLMAP 读到 0 图,而“真实目录 + 文件级软链接”可以正常入库.
- 新增 `scripts/run_s01_fastgs.sh`, 默认接当前 GPU 版 COLMAP:
  - `/workspace/colmap-cuda-install-3.12.6/bin/colmap`
  - 关键参数固定为 `--ImageReader.single_camera_per_folder 1` 与 `PINHOLE`
  - 关键防呆点:
    - `feature_extractor` 后检查数据库中 `images > 0`
    - `exhaustive_matcher` 后检查 `two_view_geometries > 0`
    - 支持 `--phase`、`--overwrite`、`--frame-limit`、`--iterations`、`--eval`
- 用真实数据完成 smoke test:
  - `bash scripts/run_s01_fastgs.sh --overwrite --frame-limit 1 --iterations 10 --colmap-root data/s01_colmap_script_smoke --fastgs-root data/s01_fastgs_script_smoke --model-path output/s01_script_smoke`
  - 真实结果:
    - 6 张图成功入库
    - 15 组 `two_view_geometries`
    - sparse 重建得到 2389 个点
    - FastGS 成功训练到 `iteration_10`
- 同步修正文档:
  - `docs/s01_3dgs_workflow.md` 改为“文件级软链接”口径
  - `README.md` 增加一键脚本入口

### 总结感悟
- 对 COLMAP 这类前处理工具, “目录看起来像能遍历”不等于“它真的会跟进目录软链接”; 这类问题必须用最小数据库计数实验来确认.
- 真正能降低使用门槛的不是再解释一遍命令,而是把踩过的坑直接编码进脚本和自检步骤里.

## [2026-03-11 06:55:30 UTC] 任务名称: 补充 `--resolution` 与 COLMAP 关系的文档说明

### 任务内容
- 将“修改 `--resolution` 不需要重新跑 COLMAP”补入 `docs/s01_3dgs_workflow.md`.
- 把这条说明放到训练章节附近, 让后续做 `-r 1 / -r 2 / -r 4` 对比时能直接看到.

### 完成过程
- 在训练章节 `8.1` 后新增 `8.1.1`, 明确写清:
  - `--resolution` 只影响训练读图缩放
  - 不会改动 COLMAP 位姿、内参、稀疏点云
  - 只需重新训练, 不需重跑 `feature_extractor` / `mapper` / `image_undistorter`
- 同时补了两条直接复用的训练示例:
  - `output/s01_r2`
  - `output/s01_r1`
- 用固定字符串方式完成自检, 确认新段落和示例命令都已写入文档.

### 总结感悟
- 对实验型文档来说, “什么时候要重做前处理,什么时候只需重训” 是非常高价值的信息, 甚至比单条命令本身更能省时间.
- 这类说明最好紧贴参数出现的位置写, 用户在做实验切换时最容易看见, 也最不容易误操作.


## [2026-03-11 07:59:27 UTC] 任务名称: 解释 drjohnson 训练命令参数含义

### 任务内容
- 核对用户给出的 `drjohnson` 训练命令中环境变量、评估开关与 FastGS 训练参数的真实作用.
- 重点说明哪些参数会直接影响最终质量,哪些只影响输出路径或评估流程.

### 完成过程
- 回读六文件上下文,确认仓库里已存在一版训练脚本参数笔记,但仍按当前代码重新核对.
- 对照 `arguments/__init__.py`、`train.py`、`scene/gaussian_model.py`、`utils/fast_utils.py`、`scene/dataset_readers.py` 和 CUDA rasterizer,逐项定位默认值与生效点.
- 确认 `OAR_JOB_ID` 只影响默认输出目录,`--test_iterations` 当前在训练中不真正生效,而 `densification_interval`、`grad_abs_thresh`、`dense`、`highfeature_lr`、`mult` 才是影响最终结果的核心旋钮.
- 额外对比 `train_base.sh` 与 `train_big.sh` 的 `drjohnson` 配置,判断用户当前命令整体更偏保守、更稳而非极限细节导向.

### 总结感悟
- 这类训练命令最容易误解的不是参数名字,而是“参数是否真的在当前代码路径里生效”.
- 对 FastGS 来说,最关键的不是单个阈值,而是 densify 频率、split 门槛、点尺寸分界和 compact box 覆盖范围这几组联动关系.

## [2026-03-11 08:09:36 UTC] 任务名称: 修复 `data/s01` 一键脚本训练后空间被压扁的问题

### 任务内容
- 排查 `bash scripts/run_s01_fastgs.sh --overwrite` 训练结果中“高度被压扁”的来源.
- 通过相机模型对照实验确认问题发生在 COLMAP 前处理还是 FastGS 训练阶段.
- 修正一键脚本默认参数, 并同步更新 `docs/s01_3dgs_workflow.md`.

### 完成过程
- 先读取 `output/s01/cameras.json`、`data/s01_colmap/sparse/0/cameras.bin`、`points3D.bin`, 确认旧结果在 COLMAP 阶段就存在异常 `fx/fy` 比例与过薄的 `y` 方向跨度.
- 随后对同一批 full data 跑了一轮 `SIMPLE_PINHOLE` 对照重建, 动态结果显示:
  - 注册图像仍为 `301`
  - 点数从 `80107` 提升到 `86581`
  - 平均重投影误差从 `0.595px` 降到 `0.573px`
  - sparse 点云 `y` 方向跨度从 `5.82` 提升到 `16.56`
- 基于这条证据链, 将 `scripts/run_s01_fastgs.sh` 默认相机模型改为 `SIMPLE_PINHOLE`, 同时保留 `--camera-model` 覆盖开关.
- 最后完成静态校验与端到端 smoke test, 确认新版脚本仍可跑通 `feature_extractor -> matcher -> mapper -> image_undistorter -> train.py` 全链路.

### 总结感悟
- 对“无畸变渲染图”, 不是相机模型越自由越好. 如果 `fx/fy` 已经拟合得明显离谱, 优先怀疑模型过复杂, 而不是先怪训练参数.
- 这次最关键的不是单看训练输出, 而是先回到 COLMAP 的 `cameras.bin` 和 `points3D.bin` 做最小对照, 这样才能把“看起来像根因”和“已经验证的结论”分开.

## [2026-03-11 08:11:05 UTC] 任务名称: 为 `scripts/run_s01_fastgs.sh` 增加 `-r` 短参数

### 任务内容
- 让 `scripts/run_s01_fastgs.sh` 支持用 `-r` 代替 `--resolution`.
- 同步更新脚本帮助文本, 保证命令说明和真实行为一致.

### 完成过程
- 读取脚本参数解析逻辑, 确认原先只支持 `--resolution`.
- 修改参数分支为 `-r|--resolution`, 并同步更新帮助文本中的选项说明.
- 通过 `bash -n`、`--help` 和 `-r 4 --help` 做了最小验证, 确认新短参数可以正常被脚本接受.

### 总结感悟
- 这类命令行入口的小改动, 最容易漏的不是解析逻辑, 而是帮助文本同步.
- 对用户常用的高频参数, 短参数别名能明显减少输入负担, 尤其是在反复试 `-r 1/2/4` 这类训练实验时.


## [2026-03-11 08:21:47 UTC] 任务名称: 补充 `docs/fastgs-train-scripts.md` 默认值说明

### 任务内容
- 在参数文档中明确写出当前代码默认值.
- 区分“代码默认值”和 `train_base.sh` / `train_big.sh` 的场景覆写值.

### 完成过程
- 对照 `arguments/__init__.py`、`train.py`、`render.py` 核对默认值来源.
- 在 `docs/fastgs-train-scripts.md` 新增“当前代码默认值速查”总表,把 `eval`、`densification_interval`、`loss_thresh`、`grad_thresh`、`grad_abs_thresh`、`lowfeature_lr`、`highfeature_lr`、`dense`、`mult`、`optimizer_type`、`test_iterations` 的默认值集中列清楚.
- 在各参数小节里补入“默认值”段落,避免读者只看到脚本值,误以为那就是程序默认.
- 自检时顺手修正了前文“见本文第 7 节”的编号引用,改为和当前章节结构一致的“第 8 节”.

### 总结感悟
- 这类调参文档最容易误导人的地方,通常不是解释不够多,而是没有先把“默认值”和“推荐覆写值”拆开.
- 对频繁被复制命令的训练脚本文档来说,先给默认值总表,再在正文里重复强调一次,能明显降低误读成本.

## [2026-03-11 08:37:20 UTC] 任务名称: 为 `run_s01_fastgs.sh` 增加 FastGS 高频训练参数配置

### 任务内容
- 将 `docs/fastgs-train-scripts.md` 中当前最常用的一组 FastGS 训练参数接入 `scripts/run_s01_fastgs.sh`.
- 让 `data/s01` 的一键脚本可以直接承接 `train_base.sh` / `train_big.sh` 的调参方式.
- 同步更新 `docs/s01_3dgs_workflow.md` 与 `docs/fastgs-train-scripts.md`.

### 完成过程
- 对照 `docs/fastgs-train-scripts.md`、`train_base.sh`、`train_big.sh` 和 `arguments/__init__.py`, 选出高频且有调参价值的参数集合.
- 在脚本中新增默认值、帮助文本、参数解析、基础校验、启动日志打印, 并把这些参数直接透传到 `train.py`.
- 透传参数包括:
  - `--densification_interval`
  - `--loss_thresh`
  - `--grad_thresh`
  - `--grad_abs_thresh`
  - `--highfeature_lr`
  - `--lowfeature_lr`
  - `--dense`
  - `--mult`
  - `--optimizer_type`
  - `--test_iterations`
- 随后同步改写两份文档, 让脚本手册能看到这些高级入口, 训练参数总文档也能反向说明“现在可以直接在脚本里配”.
- 最后用 `--phase train` 基于现成 `data/s01_fastgs` 跑了一轮 10 iter 动态验证, 确认新增参数已进入真实训练命令并且训练完成.

### 总结感悟
- 对已经稳定的业务脚本, 最有价值的扩展不是做一层“自创 DSL”, 而是直接复用底层训练参数名.
- 这样文档、脚本和 `train.py` 三者就能共用同一套词汇, 后续维护和沟通成本都会低很多.

## [2026-03-11 08:39:20 UTC] 任务名称: 从 `run_s01_fastgs.sh` 移除 `--test_iterations`

### 任务内容
- 根据用户反馈, 将 `--test_iterations` 从 `scripts/run_s01_fastgs.sh` 的可配置参数里移除.
- 保持脚本手册与实际脚本接口一致.

### 完成过程
- 从脚本中删除了 `TEST_ITERATIONS` 的默认值、帮助文本、`train.py` 透传、参数解析、整数校验和启动日志输出.
- 同步清理了 `docs/s01_3dgs_workflow.md` 中“脚本支持 `--test_iterations`”的描述.
- 保留 `docs/fastgs-train-scripts.md` 对该参数当前行为的解释, 但改成明确说明: 这是 `train.py` 层仍然存在的参数, `run_s01_fastgs.sh` 当前刻意不暴露它.
- 最后用 `bash -n` 和固定字符串检索完成一致性验证.

### 总结感悟
- 不是所有底层参数都值得暴露到业务脚本层.
- 对当前代码路径里基本不产生直觉收益、还容易误导用户的参数, 主动不暴露反而是更干净的接口设计.
