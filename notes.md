# 笔记: FastGS 仓库贡献指南素材

## 来源

### 来源1: `README.md`
- 要点:
  - 项目基于 PyTorch + CUDA 扩展,用 Conda 环境(`environment.yml`)搭建.
  - 常用入口: `train.py`(训练),`render.py`(渲染),`metrics.py`(指标).
  - 训练快捷脚本: `train_base.sh`、`train_big.sh`.

### 来源2: `environment.yml`
- 要点:
  - Conda env 名称: `fastgs`
  - Python 3.7.13, PyTorch 1.12.1, cudatoolkit 11.6.
  - pip 安装本地 CUDA 扩展: `submodules/diff-gaussian-rasterization_fastgs`、`submodules/simple-knn`、`submodules/fused-ssim`.

### 来源3: 仓库目录与脚本
- 要点:
  - 主要目录: `arguments/`(参数组),`gaussian_renderer/`(渲染与GUI/WS),`scene/`(数据/场景/模型封装),`utils/`(工具函数),`submodules/`(CUDA扩展源码),`assets/`(README图片).
  - 数据集目录 `datasets/` 不在仓库内,运行时按 README 约定放置.
  - 训练输出默认落在 `output/`(由脚本创建,不应提交到git).

### 来源4: `git log`
- 要点:
  - commit subject 多为简短祈使句/动词开头,例如 "Update README.md", "clean".
  - 部分提交使用方括号scope,例如 "[FastGS] Code release.".

## 综合发现

### 文档写作策略
- 只写本仓库确实存在且可执行的命令与路径.
- 测试部分说明: 当前未发现 pytest/unittest 测试目录,用 "小迭代训练 + render + metrics" 作为最小验证闭环.
- PR 要求尽量贴近研究代码贡献: 说明硬件、数据集、速度/指标变化,附复现实验命令.

---

# 笔记: pixi 环境初始化(从 environment.yml 迁移)

## 来源

### 来源1: pixi CLI 帮助
- 要点:
  - `pixi init --import environment.yml --format pixi` 支持从现有 conda `environment.yml` 导入生成 `pixi.toml`.

### 来源2: pixi 文档(Concepts: Conda + PyPI)
- 要点:
  - 可在 `pixi.toml` 中同时声明 `[dependencies]`(conda) 与 `[pypi-dependencies]`(PyPI).
  - 本地包可用 `path` + `editable = true` 的形式接入(适合本仓库 `submodules/*` 的 CUDA 扩展).

## 综合发现
- 迁移策略: 先自动导入 conda 依赖,再手动补齐 3 个本地 CUDA 扩展为可编辑 PyPI 依赖,最后生成 `pixi.lock` 保证可复现.

## 实际落地(最终方案)
- 由于 `pixi init --import environment.yml` 不能解析 pip 裸路径依赖,最终采用手写 `pixi.toml` 的方式,并以 `pixi lock` 生成 `pixi.lock`.
- conda channel 统一使用 `https://prefix.dev/conda-forge`(避免 `conda.anaconda.org` DNS 不可达).
- PyTorch 栈固定为:
  - `python=3.13.*`
  - `pytorch-gpu=2.9.1.*`
  - `torchvision=0.24.1.*`
  - `torchaudio=2.9.1.*`
  - `cuda-version=12.9.*`
- 本地 CUDA 扩展的安装方式改为 pixi task:
  - `pixi run setup` -> `pip install --no-build-isolation -e submodules/...`
  - 原因: 这些扩展在 `setup.py` 里 import torch,需要禁用 build isolation 才能在当前环境内构建.

---

# 笔记: 预训练模型是否在 ModelScope 上可用

## 结论
- 当前未在 ModelScope 找到 HuggingFace 上的 `Goodsleepeverday/fastgs` 镜像模型.
- 访问 `https://modelscope.cn/models/Goodsleepeverday/fastgs` 返回的是通用 SPA HTML,其中 `window.__detail_data__ = "null"`,与 ModelScope 已存在模型页面(会内嵌 JSON)的表现不一致,因此判断该模型未上架/不可用.

## 验证方式(可复现)
- 对比一个已存在的模型页面与目标页面:
  - 已存在模型页面示例: `https://modelscope.cn/models/damo/nlp_structbert_sentiment-classification_chinese-base` 会在 HTML 中出现很长的 `window.__detail_data__ = "{...}"`.
  - 目标页面: `https://modelscope.cn/models/Goodsleepeverday/fastgs` 的 `window.__detail_data__` 为 `null`.

---

# 笔记: train_big.sh 参数差异(与代码对照)

## 来源

### 来源1: `train_big.sh` / `train_base.sh`
- 关键差异:
  - `densification_interval`: Big 用 `100`,Base 用 `500`.
  - `grad_abs_thresh`: Big 普遍更小(更容易触发 split).
  - 部分场景设置 `mult=0.7`(例如 Tanks&Temples、Deep Blending).
  - 部分场景覆盖 `dense`/`highfeature_lr`/`lowfeature_lr`/`loss_thresh`.

### 来源2: `train.py`
- Densification 触发点:
  - `iteration > densify_from_iter` 且 `iteration % densification_interval == 0` 时,会执行 FastGS 的 densify+prune.
- 注意: 训练中间的 `training_report(...)` 调用目前被注释掉了,因此 `--test_iterations` 实际不会触发训练中评估.

### 来源3: `utils/fast_utils.py`
- 多视角一致性评分:
  - `metric_map = (l1_loss_norm > args.loss_thresh).int()` 用 `loss_thresh` 生成高误差像素图.
  - `importance_score` 是多视角 `accum_metric_counts` 的 floor-average,用于 densify 的 `metric_mask`.

### 来源4: `scene/gaussian_model.py`
- Feature 学习率如何落到参数组:
  - `features_dc` 使用 `lowfeature_lr`.
  - `features_rest` 使用 `highfeature_lr / 20.0`.
- clone/split 的核心判定(与 `dense`/梯度阈值强相关):
  - clone: `max_scaling <= dense * extent` 且 `grad >= grad_thresh`
  - split: `max_scaling > dense * extent` 且 `abs_grad >= grad_abs_thresh`
- densify 后会重置梯度统计:
  - `densification_postfix(...)` 会把 `xyz_gradient_accum`/`denom` 等重置为 0,因此 densify 越频繁,梯度统计窗口越短.

### 来源5: `diff-gaussian-rasterization_fastgs`(CUDA rasterizer)
- compact box 的 `mult` 直接参与 bbox/tiles 计算:
  - `t = mult * t; // beta in Compact Box`

## 综合发现
- `densification_interval` 与 `grad_abs_thresh`/`dense`/`loss_thresh` 是一组强耦合旋钮:
  - densify 更频繁会更快增点,也更可能在早期把噪声当细节,需要用阈值压住.
  - densify 更稀疏会更快更稳,但细节可能不够,点数也更少.
- `mult` 更像"渲染稳定性 vs 速度"拨杆:
  - 值更大 -> compact box 更保守 -> 覆盖更多 tiles -> 更慢但更不容易漏渲染/漏计数.

## 交付物
- 2026-02-26 02:17 UTC: 已将本次答疑整理为文档 `docs/fastgs-train-scripts.md`,后续如果要同步 README,可直接从该文档抽取段落.

---

# 笔记: convert.py 支持整目录视频输入

## 现象
- 当前  仅支持从  读取图片,不支持直接读取视频文件.
- 用户当前素材是同一镜头拍摄的多个短视频,希望把整个视频目录视为同一套输入直接处理.

## 当前假设
- 主假设: 最稳的改造方式是增加一个视频目录参数,先自动抽帧到 ,再沿用现有 COLMAP 流程.
- 备选解释: 也可以允许  直接就是视频目录,再内部临时生成工作目录. 但这种方式会让现有  语义变得模糊,也更容易破坏原行为.
- 推翻主假设的证据: 如果现有脚本在  上有强依赖,且自动生成抽帧目录会和已有数据互相覆盖导致难以安全区分,则需要改为独立视频工作区.

## 静态证据
-  的 COLMAP 命令全部硬编码使用  作为原始图像目录.
- 训练加载侧读取的是 undistort 后的  和 .
- 因此,视频模式只要最终产出同样的  结构,训练侧无需改动.


## 验证结果 (2026-03-10 04:10:59 UTC)
- 静态验证:
  - `python3 -m py_compile convert.py` 通过.
  - `python3 convert.py --help` 正常显示新增参数: `--video_path`、`--video_fps`、`--ffmpeg_executable`、`--overwrite`.
- 动态验证:
  - 使用 fake `ffmpeg` + fake `colmap` 执行 `python3 convert.py -s <video_scene>`.
  - 结果确认生成 `input/` 抽帧文件,并最终产出 `images/` 与 `sparse/0/cameras.bin|images.bin|points3D.bin`.
  - 同时验证了旧图片模式 `python3 convert.py -s <image_scene>` 仍可走通.
- 结论:
  - 当前主假设成立: “自动抽帧到 `input/`,再复用原 COLMAP 流程”可以同时满足新视频需求和旧图片兼容性.


## 真实目录验证 (2026-03-10 05:41:24 UTC)
- 验证命令:
  - `convert.discover_video_files(Path('/workspace/lyra/outputs/flashvsr_reference/full_scale2x'))`
- 关键输出:
  - `MODE rgb_recursive`
  - `COUNT 6`
  - 命中的路径均为 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x/<0..5>/rgb/00172.mp4`
- 结论:
  - 对这批素材, `convert.py` 不需要你手动搬运视频.
  - 直接对 `full_scale2x` 根目录执行 `python3 convert.py -s /workspace/lyra/outputs/flashvsr_reference/full_scale2x` 即可进入递归 `rgb` 视频模式.
  - 首次跑完后如果想重新抽帧,需要显式加 `--overwrite`,否则脚本会优先复用已生成的 `input/`.


## 真实 convert 执行结论 (2026-03-10 06:02:57 UTC)
- 执行命令:
  - `python3 convert.py -s /workspace/lyra/outputs/flashvsr_reference/full_scale2x --video_fps 2 --no_gpu`
- 关键输出:
  - `Discovered 6 video(s) ... using rgb_recursive mode`
  - `Extracted 60 frames into .../input`
  - `Loading matches... 1770`
  - `Loading images... 60 in ... (connected 60)`
  - `Reconstruction with 60 images and 21007 points`
- 产物核查:
  - `input/`: 60 张 jpg
  - `images/`: 60 张 undistorted 图
  - `sparse/0/`: `cameras.bin`、`images.bin`、`points3D.bin`
- 环境结论:
  - `apt` 安装的 `colmap` 在这台机器上显示 `without CUDA`,因此本机跑 `convert.py` 时应显式加 `--no_gpu`.
  - `ffmpeg` 路径为 `/usr/local/ffmpeg/bin/ffmpeg`.

---

# 笔记: full_scale2x 的 100 iter 烟雾训练与抽帧参数核查

## 现象
- 上一轮 smoke test 启动时, `-m` 参数没有正确传入, 终端里输出目录回退为 `./output/032e12b6-bfff-411f-a6c6-088cda08ac69`.
- 需要确认这是否导致训练失败, 以及真实数据链路是否已经跑通.
- 用户还追问了 `--video_fps 2` 的具体抽帧方式.

## 假设
- 主假设: 训练本身已经正常完成, 只是输出目录没有落到原计划的自定义路径.
- 备选解释: 训练可能只完成了数据读取阶段, 或在后台中途失败, 需要重新跑.
- 推翻主假设的证据: 如果会话没有出现 `Training complete.` 或输出目录缺少 `point_cloud/iteration_100/point_cloud.ply`, 则说明仍需重跑.

## 验证
- 会话回读:
  - `write_stdin(session_id=34025)` 返回完整训练日志.
  - 关键输出包括:
    - `Output folder: ./output/032e12b6-bfff-411f-a6c6-088cda08ac69`
    - `Number of points at initialisation : 21007`
    - `[ITER 100] Saving Gaussians`
    - `Training complete.`
- 产物核查:
  - 输出目录存在 `cameras.json`、`cfg_args`、`input.ply`、`point_cloud/iteration_100/point_cloud.ply`.
  - `point_cloud.ply` 大小约 `5211266` 字节, header 显示 `element vertex 21007`.
- `--video_fps 2` 核查:
  - 6 个源视频都位于 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x/<0..5>/rgb/00172.mp4`.
  - `ffprobe` 显示每段视频参数一致:
    - 时长 `5.039567` 秒
    - 原始帧率 `2401/100 ≈ 24.01 fps`
    - 原始总帧数 `121`
  - 抽帧结果统计:
    - 每段视频各生成 `10` 张 jpg
    - 总计 `60` 张

## 结论
- 主假设成立: 100 iter 烟雾训练已经真实完成, 不需要为“训练是否能跑通”这件事再次重跑.
- 这次 smoke test 已证明 FastGS 可以直接读取刚生成的 `images/` 与 `sparse/0/` 进入训练.
- `--video_fps 2` 的含义就是“每秒抽 2 帧”. 对这批 5.04 秒视频来说, 理论值约 `5.04 x 2 = 10.08`, 实际每段落盘 10 张, 所以 6 段一共 60 张.
- 训练日志还暴露出一个重要默认行为: 输入图像宽度超过 1600 像素时, FastGS 会自动缩到 1.6K 宽. 如果后续想保留原始宽度, 需要显式传 `--resolution 1`.

---

# 笔记: full_scale2x 在 `--resolution 1` 下的正式训练结果

## 现象
- 用户选择了保留原始分辨率的正式训练方案.
- 需要确认 `--resolution 1` 不只是参数写上了, 而是真的没有再触发训练侧的 1.6K 自动缩图.
- 还需要确认完整 30000 iter 训练是否能在当前硬件上无错误跑完.

## 假设
- 主假设: 在当前 A800 80GB 环境下, 这套 60 视角数据可以直接用 `--resolution 1` 完整跑完 30000 iter.
- 备选解释: 训练虽然能启动, 但可能在 densify 后段因为显存或点数增长而失败.
- 推翻主假设的证据: 若日志在中后段出现 OOM、CUDA error, 或最终没有 `Training complete.` 和 `iteration_30000/point_cloud.ply`, 则主假设不成立.

## 验证
- 启动命令:
  - `pixi run python train.py -s /workspace/lyra/outputs/flashvsr_reference/full_scale2x -m /workspace/FastGS/output/full_scale2x_res1_20260310_063357 --resolution 1`
- 静态证据:
  - `cfg_args` 明确记录: `resolution=1`
  - 输出目录存在 `cfg_args`、`cameras.json`、`input.ply`、`train.log`
- 动态证据:
  - 日志包含:
    - `Number of points at initialisation :  21007`
    - `[ITER 30000] Saving Gaussians`
    - `Gaussian number: 154271`
    - `Training time: 332.24425458101723`
    - `Training complete.`
  - 训练日志中没有再出现 smoke test 时那条 `rescaling to 1.6K` 提示.
- 产物核查:
  - `/workspace/FastGS/output/full_scale2x_res1_20260310_063357/point_cloud/iteration_30000/point_cloud.ply`
  - 文件大小约 `38260739` 字节.

## 结论
- 主假设成立: 这套 `full_scale2x` 数据在当前机器上可以用 `--resolution 1` 完整跑完正式训练.
- 最终训练耗时约 `5 分 32 秒`, 输出目录为 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357`.
- 与前面的 100 iter smoke test 相比, Gaussian 数量从初始化 `21007` 增长到了最终 `154271`.
- 对这批数据来说, `--resolution 1` 不仅可用, 而且训练时长也在可接受范围内.

---

# 笔记: full_scale2x 正式训练结果的 PSNR 评估

## 现象
- 用户追问正式训练结果的 PSNR.
- 先按仓库标准路径执行 `render.py --skip_train`, 结果日志显示 `[test] Rendered 0 frames`.
- 这说明当前模型目录里没有可评估的 test 视角.

## 假设
- 主假设: test 集为空, 是因为这轮训练和渲染都继承了 `cfg_args` 中的 `eval=False`.
- 备选解释: 也可能是 test 渲染输出写入失败, 导致看起来像 0 帧.
- 推翻主假设的证据: 如果代码里 `eval=False` 仍会构造 test 集, 或 test 目录里其实已经有有效的 gt/renders 文件, 那就不是切分问题.

## 验证
- 静态证据:
  - `cfg_args` 显示 `eval=False`.
  - `scene/dataset_readers.py` 中 `readColmapSceneInfo(...)` 的逻辑是:
    - `if eval: ... test_cam_infos = [idx % llffhold == 0]`
    - `else: train_cam_infos = cam_infos; test_cam_infos = []`
  - `metrics.py` 只读取 `<model>/test/<method>/...`, 不会自动评估 train.
- 动态证据:
  - `render.py -m /workspace/FastGS/output/full_scale2x_res1_20260310_063357 --iteration 30000 --skip_train`
    的结果是 `[test] Rendered 0 frames`.
  - 随后执行
    `render.py -m /workspace/FastGS/output/full_scale2x_res1_20260310_063357 --iteration 30000 --skip_test`
    成功渲染 train 视角 60 帧.
- 指标计算:
  - 用仓库 `utils.image_utils.psnr` 与 `utils.loss_utils.ssim` 对
    `train/ours_30000/renders` 和 `train/ours_30000/gt` 做逐帧均值统计.
  - 结果:
    - `count = 60`
    - `PSNR = 26.686299165089924`
    - `SSIM = 0.8608855307102203`

## 结论
- 主假设成立: 当前这轮正式训练没有 test 集, 所以严格意义上的 test PSNR 现在拿不到.
- 当前能给出的真实数值是 train 集重建指标:
  - `PSNR = 26.6863`
  - `SSIM = 0.8609`
- 如果后续要拿标准 test PSNR, 需要在训练和渲染时使用 `--eval`, 让 COLMAP 视角按 `llffhold=8` 切出 test 集.

---

# 笔记: 本机 SSH 密码登录状态核查

## 来源

### 来源1: `sshd -T`
- 命令:
  - `sshd -T | rg -i "^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|usepam) "`
- 结果:
  - `port 23`
  - `permitrootlogin yes`
  - `passwordauthentication yes`
  - `pubkeyauthentication yes`
  - `kbdinteractiveauthentication no`
  - `usepam yes`

### 来源2: `/etc/ssh/sshd_config`
- 关键配置:
  - `Include /etc/ssh/sshd_config.d/*.conf`
  - `Port 23`
  - `PermitRootLogin yes`
  - `PasswordAuthentication yes`
  - `KbdInteractiveAuthentication no`
  - `UsePAM yes`
- `sshd_config.d` 目录当前没有额外 `.conf` 文件覆盖主配置.

### 来源3: 运行态证据
- 命令:
  - `pgrep -af "^sshd:"`
  - `lsof -nP -iTCP -sTCP:LISTEN | rg ":(22|23)\\b"`
- 结果:
  - 存在 `sshd` 监听进程.
  - 当前监听端口是 `*:23`,不是默认的 `22`.

## 综合发现
- 现象:
  - 本机 `sshd` 有效配置明确允许密码登录.
  - 本机还明确允许 `root` 直接 SSH 登录.
  - SSH 服务监听在 `23` 端口.
- 结论:
  - 若你用的是这台机器上的账户密码,当前配置允许通过 SSH 密码方式登录.
  - 连接时端口应优先使用 `23`,不能想当然用默认 `22`.

# 笔记: GPU 版 COLMAP 可行性核查

## 来源

### 来源1: 本机 `colmap -h`
- 证据:
  - `/usr/bin/colmap`
  - 输出含 `COLMAP 3.7 ... without CUDA`
- 要点:
  - 当前系统安装的是 CPU 版 `colmap`.
  - 这会导致 `convert.py` 即使默认请求 GPU, 实际也无法走 CUDA SIFT.

### 来源2: `convert.py`
- 位置:
  - `convert.py:323`
  - `convert.py:355`
  - `convert.py:367`
- 要点:
  - `use_gpu = 0 if args.no_gpu else 1`
  - 未传 `--no_gpu` 时,脚本本来就会把 `SiftExtraction.use_gpu=1` 与 `SiftMatching.use_gpu=1` 传给 COLMAP.
  - 因此脚本层面并不存在“完全不支持 GPU”的问题.

## 当前综合发现
- 当前现象:
  - 脚本里已经有 GPU 开关.
  - 本机 `colmap` 是 `without CUDA`.
- 当前主假设:
  - 若替换为 CUDA 版 `colmap`, 现有 `convert.py` 大概率无需改动就能使用 GPU.
- 最强备选解释:
  - 即便替换为 CUDA 版 `colmap`, 仍可能因为本机 CUDA toolkit / 驱动 / CMake / 依赖版本不匹配而无法成功运行.
- 下一步证据:
  - 核查 `nvidia-smi`、`nvcc --version`、`cmake --version`、`g++ --version`.

## 补充笔记: 准备在 /workspace 编译 CUDA 版 COLMAP

### 官方构建线索
- Context7 / 官方文档指出:
  - Linux 默认仓库里的 `colmap` 通常不带 CUDA.
  - `CUDA_ENABLED` 在 CMake 中默认是 `ON`, 但前提是构建时能找到 CUDA.
  - Debian / Ubuntu 需要先准备一批系统依赖, 再执行标准的 `cmake -> build -> install` 流程.

### 当前判断
- 代码层已经允许通过 `--colmap_executable` 使用另一份 `colmap`.
- 因此本次重点是把一份 CUDA 版编译到 `/workspace`, 而不是改仓库代码.

## 补充笔记: CUDA 版 COLMAP 源码与安装目录约定
- 为避免覆盖或删除旧目录, 本次使用带版本号的独立路径:
  - 源码: `/workspace/colmap-cuda-src-3.12.6`
  - 构建: `/workspace/colmap-cuda-build-3.12.6`
  - 安装: `/workspace/colmap-cuda-install-3.12.6`
- 这样后续如果要升级版本, 可以并行保留多份构建结果.

## 补充笔记: CUDA 版 COLMAP 的验证策略
- 静态验证:
  - 新二进制 `-h` 输出应包含 `with CUDA`.
  - `ldd` 应能看到 `libcudart.so` 等 CUDA 相关链接.
- 动态验证:
  - 用 2 张真实图片跑一次 `feature_extractor --SiftExtraction.use_gpu 1`.
  - 只要数据库成功写出, 且命令不报 `without CUDA` / GPU 初始化失败, 就说明最关键的 GPU SIFT 路径已通.

## 补充笔记: GPU 版 COLMAP 文档的落盘范围
- 当前仓库 `docs/` 下只有 `docs/fastgs-train-scripts.md`.
- README 里暂时没有 GPU 版 COLMAP 的专门入口.
- 本次最小且清晰的落地方式:
  - 新增 `docs/colmap_cuda_build.md`
  - 视 README 中现有结构, 再决定是否补一个轻量链接入口.

# 笔记: `data/s01` 的 3DGS 文档口径整理

## 来源

### 来源1: 仓库数据入口代码
- 位置:
  - `scene/__init__.py`
  - `scene/dataset_readers.py`
- 要点:
  - 训练入口只识别带 `sparse/` 的 COLMAP 数据,或带 `transforms_train.json` 的 Blender 数据.
  - COLMAP 路径下要求使用去畸变后的 `PINHOLE` / `SIMPLE_PINHOLE` 相机模型.

### 来源2: `data/s01` 目录动态核对
- 命令:
  - `python3 - <<'PY' ...`
- 结果:
  - `C01pick` ~ `C06pick` 六个目录均存在.
  - 每个目录当前各有 51 张 JPG.
  - 样本图分辨率为 `3840x2160`.

### 来源3: 当前用户约束
- 用户确认:
  - `s01` 是 3ds Max 渲染器渲染的图.
  - 数据没有镜头畸变.
  - 指定 GPU 版 COLMAP 路径:
    - `/workspace/colmap-cuda-install-3.12.6/bin/colmap`
  - 训练机器 GPU 为 A800 80G.

## 综合发现
- 当前结论:
  - 文档主线应该是“手动 COLMAP CLI -> 生成 FastGS 可读目录 -> 训练”.
  - 不应该把 `convert.py` 当成主推荐路径,因为它当前默认 `single_camera=1`,不适合多机位目录.
- 命令层决策:
  - 文档中统一定义:
    - `COLMAP_BIN=/workspace/colmap-cuda-install-3.12.6/bin/colmap`
  - 相机模型使用:
    - `--ImageReader.camera_model PINHOLE`
  - 多机位目录使用:
    - `--ImageReader.single_camera_per_folder 1`
  - 训练推荐:
    - A800 80G 优先推荐 `-r 2`
    - 先给 `--iterations 1000` 的 smoke test
    - 再给正式训练命令

# 笔记: `mapper` 报 “No images with matches found” 的最小验证

## 来源

### 来源1: 用户真实失败现场
- 现象:
  - `mapper` 日志显示:
    - `Loading cameras... 0`
    - `Loading matches... 0`
    - `Loading images... 0`
    - `No images with matches found in the database`
- 数据库动态核对:
  - `cameras = 0`
  - `images = 0`
  - `keypoints = 0`
  - `matches = 0`
  - `two_view_geometries = 0`

### 来源2: 最小对照实验
- 测试数据:
  - 取 `C01pick` 中 2 张真实图片
- 三组输入形态:
  - A. `images/C01pick -> 原目录软链接`
  - B. `images/C01pick/xxx.jpg -> 真实复制文件`
  - C. `images/C01pick/xxx.jpg -> 文件软链接`

### 动态结果
- A 目录软链接:
  - `feature_extractor` 日志只出现 `Creating SIFT GPU feature extractor`
  - 数据库计数:
    - `cameras = 0`
    - `images = 0`
- B 真实目录 + 真实文件:
  - 正常处理 2 张图
  - 数据库计数:
    - `cameras = 1`
    - `images = 2`
- C 真实目录 + 文件软链接:
  - 正常处理 2 张图
  - 数据库计数:
    - `cameras = 1`
    - `images = 2`

## 结论
- 已验证结论:
  - 当前失败根因不是 `mapper` 本身.
  - 真正的问题发生在更前面的 `feature_extractor`.
  - COLMAP 当前不会按预期跟进“目录软链接”中的图片,导致数据库完全为空.
- 可用修正:
  - 使用真实目录
  - 目录内放真实文件或文件级软链接


---

# 笔记: drjohnson 训练命令参数释义核对

## 来源

### 来源1: `arguments/__init__.py`
- 默认值确认:
  - `densification_interval=100`
  - `loss_thresh=0.1`
  - `grad_abs_thresh=0.0012`
  - `highfeature_lr=0.005`
  - `lowfeature_lr=0.0025`
  - `dense=0.001`
  - `mult=0.5`
  - `optimizer_type="default"`

### 来源2: `train.py`
- `OAR_JOB_ID` 只用于在未显式传 `--model_path` 时决定输出目录名.
- `--test_iterations` 虽然被解析,但训练循环里的 `training_report(...)` 调用当前被注释,因此训练中不会真正触发评估.
- `densification_interval` 在 `iteration > densify_from_iter` 且整除时触发多视角 densify + prune.
- `optimizer_type=default` 会走 `gaussians.optimizer_step(iteration)` 这条主路径.

### 来源3: `scene/gaussian_model.py`
- `lowfeature_lr` 作用在 `features_dc`.
- `highfeature_lr` 作用在 `features_rest`,但真实 lr 是 `highfeature_lr / 20`.
- `grad_abs_thresh` 控制 split 候选阈值.
- `dense * extent` 是 clone / split 的尺寸分界.
- `default` 优化器不是每轮都更新全部参数: 15k 前较频繁,后期逐步降频.

### 来源4: `utils/fast_utils.py` + CUDA rasterizer
- `loss_thresh` 用于构造高误差像素二值图 `metric_map = (l1_loss_norm > args.loss_thresh).int()`.
- `mult` 同时参与训练渲染、重要性评分渲染和最终 `render.py` 渲染.
- CUDA 中 `t = mult * t` 会直接改变 compact box 大小,因此 `mult` 会影响 tiles 覆盖范围与速度/稳健性平衡.

### 来源5: `scene/dataset_readers.py`
- `--eval` 对 COLMAP 数据会按 `llffhold=8` 切 train/test.
- 不开 `--eval` 时,测试集为空.

## 综合发现
- 用户给出的 `drjohnson` 这一行来自 `train_base.sh`,属于比 `train_big.sh` 更保守的一套配置:
  - `densification_interval=500`
  - `grad_abs_thresh=0.0012`
  - `dense=0.013`
  - `mult=0.7`
- 这套参数整体倾向:
  - 比 big 配置更稳,更省点数/时间.
  - 但 densify/split 没那么激进,极限细节通常不如 big 配置.
- `mult` 对“最终结果”的影响不只在训练期,因为 render 阶段通常也要保持一致.
- `test_iterations=30000` 在当前仓库状态下主要是配置记录作用,不是训练中评估开关.

## 可直接给用户的结论
- 这条命令里真正决定最终质量/点数/速度平衡的核心旋钮是:
  - `densification_interval`
  - `grad_abs_thresh`
  - `dense`
  - `highfeature_lr`
  - `mult`
- 其中:
  - `densification_interval` 决定多久增点一次.
  - `grad_abs_thresh` 决定 split 有多激进.
  - `dense` 决定点大小到什么程度算“该 split 的大点”.
  - `highfeature_lr` 决定高阶 SH 颜色细节学得多快.
  - `mult` 决定 compact box 有多保守,会影响训练和渲染的覆盖范围.

# 笔记: `data/s01` 空间被压扁问题的相机模型对照

## 现象
- 用户反馈: 执行 `bash scripts/run_s01_fastgs.sh --overwrite` 后, 训练结果看起来“高度像正常的一半”, 空间被压扁.
- 现有 `PINHOLE` 结果中:
  - `output/s01/cameras.json` 出现 `fx≈3231`, `fy≈8162`
  - `data/s01_colmap/sparse/0/points3D.bin` 包围盒约为 `[76.37, 5.82, 46.02]`
- 这说明异常在 COLMAP 阶段就已经存在, 不能直接归因到 FastGS 训练参数.

## 主假设与备选解释
- 主假设:
  - 对这批无畸变渲染图, `PINHOLE` 自由度偏高, 导致 COLMAP 把 `fx/fy` 拟合到异常比例, 进而把 sparse 几何压扁.
- 备选解释:
  - 数据本身竖直视差偏弱, 即便换成 `SIMPLE_PINHOLE` 也不会明显改善.

## 动态验证
- full data 对照目录:
  - `PINHOLE`: `/workspace/FastGS/data/s01_colmap/sparse/0`
  - `SIMPLE_PINHOLE`: `/workspace/FastGS/data/s01_colmap_simple_test/sparse/0`
- `PINHOLE` 结果:
  - `cameras=6`
  - `registered_images=301`
  - `points=80107`
  - `Mean reprojection error=0.595019px`
  - 相机参数近似:
    - `[3231.x, 8161.x, 1920, 1080]`
  - 点云包围盒:
    - `[76.367331, 5.817529, 46.023958]`
  - 比例:
    - `x/y = 13.127108`
    - `z/y = 7.911255`
- `SIMPLE_PINHOLE` 结果:
  - `cameras=6`
  - `registered_images=301`
  - `points=86581`
  - `Mean reprojection error=0.573127px`
  - 相机参数近似:
    - `[3231.x, 1920, 1080]`
  - 点云包围盒:
    - `[76.727743, 16.558864, 59.953666]`
  - 比例:
    - `x/y = 4.633636`
    - `z/y = 3.620639`

## 结论
- 主假设成立.
- `SIMPLE_PINHOLE` 相比 `PINHOLE`:
  - 保持了同样的注册图像数量 `301`
  - 点数更多: `86581 > 80107`
  - 重投影误差更低: `0.573px < 0.595px`
  - `y` 方向跨度扩大约 `2.85x`
- 因此 `data/s01` 当前“空间被压扁”的主要问题, 已验证更接近 COLMAP 的相机模型选择, 不是 FastGS 训练阶段单独引入.

## 落地修正
- `scripts/run_s01_fastgs.sh`
  - 默认 `CAMERA_MODEL` 改为 `SIMPLE_PINHOLE`
  - 新增 `--camera-model <SIMPLE_PINHOLE|PINHOLE>`
- `docs/s01_3dgs_workflow.md`
  - 更新手动 COLMAP 命令为 `SIMPLE_PINHOLE`
  - 补入对照实验结果和排障说明


---

# 笔记: `docs/fastgs-train-scripts.md` 默认值补齐

## 来源

### 来源1: `arguments/__init__.py`
- 训练参数默认值确认:
  - `densification_interval=100`
  - `loss_thresh=0.1`
  - `grad_thresh=0.0002`
  - `grad_abs_thresh=0.0012`
  - `highfeature_lr=0.005`
  - `lowfeature_lr=0.0025`
  - `dense=0.001`
  - `mult=0.5`
  - `optimizer_type="default"`
  - `eval=False`

### 来源2: `train.py` / `render.py`
- `test_iterations` 默认值来自 `train.py`,为 `[30000]`.
- `render.py` 的 `--mult` 默认值也是 `0.5`,需要和训练侧一起写清楚,避免误以为脚本里的 `0.7` 是全局默认.

## 综合发现
- 原文档已经解释了参数作用,但没有系统地区分“代码默认值”和“脚本覆写值”.
- 最容易被误读的几个参数是:
  - `densification_interval`
  - `mult`
  - `eval`
  - `test_iterations`
- 最稳的写法不是只在正文零散补默认值,而是先给一个“默认值速查”总表,再在每个参数小节里重复写一次默认值.
