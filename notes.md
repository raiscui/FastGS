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
