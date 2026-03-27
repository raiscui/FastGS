# EPIPHANY_LOG


## [2026-03-10 06:02:57 UTC] 主题: 本机 apt 安装的 COLMAP 是 CPU 版,转换脚本需要显式 `--no_gpu`

### 发现来源
- 在真实执行 `convert.py` 之前,先运行了 `colmap -h` 检查环境.

### 核心问题
- 这台机器通过 `apt` 安装到的 `colmap` 标识为 `COLMAP 3.7 ... without CUDA`.
- 如果沿用脚本默认 GPU 选项,未来在别的数据上很可能因为期望 CUDA SIFT 而踩坑.

### 为什么重要
- 这是环境级规律,不是单次任务偶发问题.
- 以后凡是在这台机器上跑 `convert.py`,都应该优先考虑 `--no_gpu`.

### 未来风险
- 如果用户误以为装了 `colmap` 就一定能走 GPU,可能在后续大数据集转换时遇到性能预期落差或启动报错.

### 当前结论
- 已验证 CPU 版 `colmap` 可以成功完成 6 段视频、60 张图的稀疏重建.
- 当前还没有在这台机器上验证过 CUDA 版 `colmap`.

### 后续讨论入口
- 若后续需要更快的 SfM 预处理,可以先讨论是否改装 CUDA 版 `colmap`.

## [2026-03-10 06:23:00 UTC] 主题: FastGS 默认会把宽度大于 1600 的输入图自动缩到 1.6K

### 发现来源
- 在真实数据 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 的 100 iter 烟雾训练日志中观察到提示信息.

### 核心问题
- 训练日志明确输出:
  - `Encountered quite large input images (>1.6K pixels width), rescaling to 1.6K.`
  - `If this is not desired, please explicitly specify '--resolution/-r' as 1`
- 这意味着即便 COLMAP 和抽帧都保留了更高分辨率, FastGS 默认训练也不会直接用原图宽度.

### 为什么重要
- 这会直接影响正式训练的清晰度、显存占用和训练耗时.
- 如果用户以为自己训练的是原始 2560 宽图, 实际结果会和预期不一致.

### 未来风险
- 不知道这个默认行为时, 很容易把“细节不够”误判成 SfM 或模型参数问题.
- 正式训练前如果没有明确分辨率策略, 可能在画质和速度之间做出非预期选择.

### 当前结论
- 当前 smoke test 已验证默认配置下会自动缩到 1.6K 宽并成功训练.
- 还没有对同一批数据验证 `--resolution 1` 的显存和耗时成本.

### 后续讨论入口
- 如果后续要追求更高保真, 可以专门讨论是否在正式训练中改用 `--resolution 1` 保留原始分辨率.

## [2026-03-10 06:41:00 UTC] 主题: 这台 A800 80GB 可以直接扛住 full_scale2x 的 `--resolution 1` 正式训练

### 发现来源
- 在真实数据 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 上完成了一轮完整 30000 iter 正式训练.

### 核心问题
- 前面只知道默认配置会自动缩到 1.6K, 但并不知道保留原始分辨率时是否会 OOM 或大幅拖慢.
- 这次实测给出了直接证据.

### 为什么重要
- 以后面对同量级的 60 视角自采数据时, 可以更有把握地优先尝试 `--resolution 1`.
- 这能减少因为过早保守缩图而损失画质的情况.

### 未来风险
- 这个结论依赖当前硬件是 A800 80GB, 不能无条件外推到小显存卡.
- 如果后续数据分辨率更高、视角更多, densify 后段的显存压力仍可能上升.

### 当前结论
- 当前这套数据在 `--resolution 1` 下完整跑完 30000 iter, 训练耗时约 332 秒.
- 最终 Gaussian 数量为 154271, 无 OOM, 无 CUDA error.

### 后续讨论入口
- 下次若要评估“保留原始分辨率是否值得”, 可以直接把这次结果和后续 render 结果一起对比.

## [2026-03-10 07:08:00 UTC] 主题: 不带 `--eval` 的 FastGS 训练无法直接产出 test PSNR

### 发现来源
- 在对 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357` 做 render + metrics 评估时发现 `test` 渲染为 0 帧.

### 核心问题
- `scene/dataset_readers.py` 对 COLMAP 数据的切分逻辑是:
  - `eval=True` 时按 `llffhold=8` 切 train/test
  - `eval=False` 时全部视角进入 train, `test_cameras = []`
- `metrics.py` 又是硬编码只读 `test/` 目录.
- 两者叠加的结果是: 不带 `--eval` 的训练, 后面即使跑 `metrics.py`, 也没有 test PSNR 可算.

### 为什么重要
- 这会直接影响后续实验对比的可复现性.
- 如果不知道这个约束, 很容易在训练结束后才发现“没有 test 指标”, 白白多走一轮渲染和评估.

### 未来风险
- 用户可能误把 train PSNR 当成 test PSNR.
- 后续不同实验如果有的开了 `--eval`, 有的没开, 指标口径会混乱.

### 当前结论
- 当前这轮正式训练只能给出 train 集指标: `PSNR 26.6863`, `SSIM 0.8609`.
- 若要拿标准 test PSNR, 需要重新用 `--eval` 训练或至少重新导出带 test 切分的评估路径.

### 后续讨论入口
- 如果接下来要做可比实验, 建议统一规定: 需要报 PSNR 的训练任务一律加 `--eval`.

## [2026-03-10 08:24:49 UTC] 主题: 本机 SSH 监听在 23 端口,且允许 root 密码登录

### 发现来源
- 在核查本机 SSH 是否允许密码登录时,结合 `sshd -T`、`/etc/ssh/sshd_config` 与监听端口结果得到.

### 核心问题
- 本机不是常见的 `22` 端口,而是 `Port 23`.
- 同时有效配置显示 `PasswordAuthentication yes` 与 `PermitRootLogin yes`.

### 为什么重要
- 以后如果有人直接用默认 `ssh user@host` 去连,很容易误判成“SSH 不通”.
- `root` 密码登录开启属于高风险配置,至少应该被明确记录,避免后续排障时忽略安全边界.

### 未来风险
- 若该机器暴露在更大网络范围内,口令爆破风险会高于“仅密钥登录”的配置.
- 如果团队成员不知道端口是 `23`,会反复在错误端口上排查网络和防火墙问题.

### 当前结论
- 已有动态证据表明 `sshd` 正在监听 `*:23`.
- 已有静态与有效配置证据表明密码登录和 `root` 直登都处于允许状态.

### 后续讨论入口
- 若后续要加固主机安全,可以先讨论是否改成“禁用 root 密码登录 + 仅密钥登录 + 明确保留端口策略”.

## [2026-03-27 05:48:00 UTC] [Session ID: 119e250a-72a8-40a1-bad2-1a106f4b536a] 主题: 已有 `images + sparse/0` 的目录不该被强制退回视频预处理模式

### 发现来源
- 在支持 `/home/rais/FreeFix/data/my4_fullcolmap` 直接进入 FastGS 时发现.
- 真实目录已经包含:
  - `images/`
  - `sparse/0/`
  - `distorted/sparse/*`

### 核心问题
- 旧脚本把 `--source-path` 默认理解成“原始视频根目录”.
- 这会导致已经准备好的 COLMAP 根目录无法直接复用, 用户被迫回退到重复的 `convert.py` 路线.

### 为什么重要
- 这不是 `my4_fullcolmap` 一份数据的偶发现象.
- 以后任何外部工具预处理好的 COLMAP 场景, 都可能遇到同样问题.
- 如果入口层不承认“数据已经准备好了”, 就会持续制造重复计算和错误心智模型.

### 未来风险
- 如果后续又新增别的 wrapper, 但没沿用这条识别规则, 入口行为会重新分裂.
- 用户可能以为“脚本不支持已准备数据”, 实际只是入口做了错误假设.

### 当前结论
- 最正确的入口策略是:
  - 先识别目录是不是已经有 `images + sparse/0`
  - 如果是, `prepare` 应退化为校验
  - 训练和评估直接复用该根目录
- 当前这条规律已经落地到 `scripts/run_lyra_colmap_fastgs.sh`.

### 后续讨论入口
- 如果后续继续收敛入口, 可以考虑把这种“prepared dataset root”识别逻辑再抽成各 wrapper 共享的公共约定.

## [2026-03-11 05:46:33 UTC] 主题: 这个仓库切换 GPU 版 COLMAP 的最佳挂载点不是改默认逻辑,而是利用 `--colmap_executable`

### 发现来源
- 在核查 `convert.py` 的 GPU 相关参数与本机 `colmap` 构建方式时发现.

### 核心问题
- 用户容易把“当前系统 `colmap` 是 CPU 版”误解成“仓库不支持 GPU 版 COLMAP”.
- 实际上脚本已经具备 GPU 请求能力,并且还能指定外部二进制路径.

### 为什么重要
- 这意味着后续如果要引入 CUDA 版 `colmap`, 最稳的方式不是直接覆盖 `/usr/bin/colmap`, 而是并行安装后通过 `--colmap_executable` 切换.
- 这样可以保留 CPU 版作为回退路径,降低环境改坏后的恢复成本.

### 未来风险
- 如果直接替换系统包,一旦 CUDA 版构建和运行失败, 现有可工作的 CPU 流程也会一起受影响.
- 如果脚本启动时不主动提示 `colmap` 是否带 CUDA, 用户仍可能继续困惑于“为什么没走 GPU”.

### 当前结论
- 当前仓库代码层面已支持 GPU 版 COLMAP.
- 当前限制来自系统安装的 `/usr/bin/colmap` 为 `without CUDA`.
- 本机具备 A800、驱动和 `nvcc`, 后续具备单独编译 CUDA 版 `colmap` 的基础条件.

### 后续讨论入口
- 若下次真的要落地 GPU 版 `colmap`, 可优先做两件事:
  - 单独安装一份 CUDA 版 `colmap` 到独立前缀.
  - 给 `convert.py` 增加启动期 CUDA 能力检测与提示.

## [2026-03-11 06:09:49 UTC] 主题: 这台机器编译 CUDA 版 COLMAP 的稳定组合是 GCC 10 + CUDA 12.6 + 独立安装前缀

### 发现来源
- 在 `/workspace` 真实编译并验证 GPU 版 `colmap` 的过程中得到.

### 核心问题
- 系统默认 `apt` 安装的 `colmap` 是 CPU 版, 但机器本身具备 A800 和完整 CUDA 工具链.
- 需要一条既能落地 GPU 版, 又不破坏现有 CPU 回退路径的稳定方案.

### 为什么重要
- 这直接决定后续 `convert.py` 的预处理速度和环境可维护性.
- 一旦后续升级 `colmap`, 只要沿用“独立前缀 + `--colmap_executable`”策略, 风险就会很低.

### 未来风险
- `apt` 安装依赖后仍会留下若干旧版 NVIDIA 空文件告警, 虽然当前链接器实际解析到新库, 但未来若系统驱动再次变更, 仍值得回头清理.
- 如果以后换到不同 GPU 架构, `CMAKE_CUDA_ARCHITECTURES=80` 需要同步调整, 不能盲复用.

### 当前结论
- 当前稳定可用的 GPU 版路径为 `/workspace/colmap-cuda-install-3.12.6/bin/colmap`.
- 已有静态证据:`COLMAP 3.12.6 ... with CUDA` 与 `ldd` 中的 `libcudart.so.12`.
- 已有动态证据: `feature_extractor --SiftExtraction.use_gpu 1` 日志出现 `Creating SIFT GPU feature extractor` 并成功处理 2 张真实图片.

### 后续讨论入口
- 若以后要减少编译时间或简化维护, 可以考虑给项目补一份 `docs/colmap_cuda_build.md`, 固化本机这条成功构建路径.

## [2026-03-27 14:12:23 CST] [Session ID: a354b352-2b30-435e-b917-cd8fed8e5060] 主题: 这份 FastGS 默认训练日程里, 30000 之后的额外步数不是“继续长结构”

### 发现来源
- 在回答 `my4_fullcolmap` 的“继续从 30000 跑到 50000 是否能明显提质”时, 回读了 `arguments/__init__.py`、`train.py` 与 `scene/gaussian_model.py`.

### 核心问题
- 用户很容易把“多跑 20000 步”理解成“会继续补点、补结构、补几何”.
- 但当前默认训练日程并不是这样设计的:
- `densify_until_iter = 15000`

## [2026-03-27 07:45:00 UTC] [Session ID: 019d2d07-3c10-70b0-a340-22753598e9ff] 主题: 当前唯一 GPU 正被另一条 CoherentGS 长任务占用约 39 GiB

### 发现来源
- 在多轮 FastGS 训练出现 CUDA 非法访存后, 主动检查了运行态:
  - `nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader`
  - `ps -fp 749108`

### 核心问题
- 当前机器只有 1 张可见 GPU:
  - `NVIDIA RTX PRO 6000 Blackwell Server Edition`
- 但同时还存在一条不是本轮 FastGS 任务拉起的进程:
  - `simple_deblur_difix.py ...`
  - 显存占用约 `39210 MiB`

### 为什么重要
- 这不一定单独构成根因.
- 但在已经发生过多轮 CUDA 非法访存的前提下, 共卡会明显抬高长训练的不确定性.
- 后续如果要做真正稳定的正式训练守护, 需要先明确:
  - 是否允许暂停那条任务
  - 或是否接受 FastGS 继续和它共享同一张卡

### 未来风险
- 长训练中途出现随机失败时, 很容易把“共卡干扰”误判成“代码回归”.
- 即便代码已经修正, 共享显存和调度压力仍可能让结果波动.

### 当前结论
- 目前已确认:
  - mask loss 语义 bug 已修复
  - 但长训练仍处在单卡共享环境中
- 因此下一步需要和用户对齐:
  - 是否暂停外部 CoherentGS 任务, 再做最终 30K 守护

### 后续讨论入口
- 若用户允许暂停外部任务, 优先先停:
  - PID `749108`
  - 命令 `simple_deblur_difix.py ...`
  - aggressive prune 只在 `15000 < iter < 30000` 每 `3000` iter 执行
  - `position_lr_max_steps = 30000`
  - `optimizer_step` 在 `iter > 20000` 后只每 `64` iter 执行一次

### 为什么重要
- 这会直接影响用户对“从 30000 续到 50000”的收益预期.
- 如果不先说清楚, 很容易把“默认 schedule 下收益有限”误判成“数据一定有问题”或“脚本没给够参数”.

### 未来风险
- 后续再做 50K / 60K 实验时, 如果仍沿用默认 `densify_until_iter` 和 `position_lr_max_steps`, 训练时间可能明显增加, 但结构质量提升有限.
- 用户可能误以为只要拉长总步数, 就能自动解决“棉絮”“模糊”等几何层问题.

### 当前结论
- 对这份代码来说, 30000 之后默认更像“低频微调现有 Gaussians”, 不是“继续积极生长”.
- 如果真想让 50K 更有价值, 不能只改 `--iterations`, 还要联动考虑:
  - `densify_until_iter`
  - `position_lr_max_steps`
  - 以及 densify / split / prune 相关阈值

### 后续讨论入口
- 如果后续还要继续做 `my4_fullcolmap` 的终版训练, 应优先讨论“50K 训练 schedule 该如何重排”, 而不只是把总步数改大.

## [2026-03-15 06:20:00 UTC] 主题: `mapper` 产出多子模型时, `sparse/0` 不是“最佳模型”的同义词

### 发现来源
- 在排查 `xhc_bai_flashvsr_colmap_fps12` 首轮 `cudaErrorInvalidConfiguration` 时, 对比了 `distorted/sparse/{0,1,2}` 的真实统计.

### 核心问题
- 旧 `convert.py` 把 `image_undistorter` 的输入写死为 `distorted/sparse/0`.
- 但真实数据里:
  - `sparse/0` 只有 4 张注册图和 2 个点
  - `sparse/2` 却有 360 张注册图和 92946 个点
- 这说明:
  - “目录编号最小”不等于“重建质量最好”

### 为什么重要
- 这不是单个 `xhc_bai` 场景的偶发问题, 而是 COLMAP 增量建图在多连通子图场景下的通用风险.
- 如果继续默认信任 `sparse/0`, 下游会把“上游选错模型”误读成“训练 CUDA 崩了”或“素材本身没法训”.

### 未来风险
- 任何多视频、多视角、低纹理或分段重叠的数据, 都可能再次让 `mapper` 产出多个 sparse 子模型.
- 一旦脚本继续偷懒取 `0`, 用户看到的就不是明确的 COLMAP 质量问题, 而是更晚、更难读的训练期崩溃.

### 当前结论
- 已有静态证据:
  - `convert.py` 旧逻辑固定选 `sparse/0`
- 已有动态证据:
  - 手动切到 `sparse/2` 后, 同一份 `xhc_bai` 数据恢复到 `Reading camera 360/360` 与 `Training complete.`
- 当前仓库已改为自动选择注册图像数最多的子模型.

### 后续讨论入口
- 如果以后需要更强控制, 可以再讨论是否暴露一个显式的 `--sparse-model-id` 或 `--sparse-model-path` 覆盖项.

## [2026-03-11 06:25:40 UTC] 主题: `convert.py` 的默认单相机假设不适合多机位渲染图目录

### 发现来源
- 在为 `data/s01` 整理 3DGS 命令文档时,对照了 `convert.py` 默认参数与多机位目录的真实需求.

### 核心问题
- `convert.py` 当前默认走 `--ImageReader.single_camera 1`.
- 这条默认假设更接近“单机位视频/单套图片”,不适合 `C01pick` ~ `C06pick` 这种每个子目录代表一台相机的输入.

### 为什么重要
- 如果未来有人看到仓库里有 `convert.py`, 很容易想当然把多机位目录直接喂进去.
- 一旦这样做, 相机内参建模口径就可能和真实数据结构不一致, 进而影响 SfM 结果质量.

### 未来风险
- 多机位渲染图会被错误地压成“单相机”口径, 造成位姿恢复不稳或内参估计偏差.
- 用户可能把重建质量问题误判成“FastGS 训练不行”, 实际问题发生在前处理阶段.

### 当前结论
- 当前对多机位目录的最稳做法, 是直接手动运行 COLMAP CLI, 并显式使用:
  - `--ImageReader.single_camera_per_folder 1`
  - `--ImageReader.camera_model PINHOLE`
- `convert.py` 目前仍适合作为单机位输入的快捷入口.

### 后续讨论入口
- 如果后续要降低多机位用户的使用门槛, 可以考虑给 `convert.py` 增加一套显式多机位模式.

## [2026-03-11 06:51:50 UTC] 主题: 对 COLMAP 来说,“目录软链接”和“文件软链接”不是等价输入

### 发现来源
- 在复盘 `data/s01` 的真实 `mapper` 失败现场,并做最小对照实验时得到.

### 核心问题
- 看起来同样都是“软链接”, 但 COLMAP 对两种输入的实际行为完全不同:
  - 相机目录本身是软链接 -> `feature_extractor` 后数据库仍为 0 图
  - 相机目录是真实目录,里面的图片是文件级软链接 -> 正常入库

### 为什么重要
- 这个差异不是肉眼看目录结构就能推断出来的, 必须靠数据库计数或真实日志验证.
- 它直接决定了后续多机位数据的前处理脚本能不能稳定工作.

### 未来风险
- 如果后续继续沿用“目录软链接”思路, 用户会在 `mapper` 阶段重复看到:
  - `No images with matches found in the database`
- 因为症状出现在 `mapper`, 人很容易误判成建图参数问题, 实际根因却在更早的输入组织阶段.

### 当前结论
- 未来凡是给 COLMAP 组织多机位输入目录, 默认应使用:
  - 真实目录
  - 文件级软链接或真实复制文件
- 不应再推荐“目录级软链接”作为标准做法.

### 后续讨论入口
- 如果后续要把这条规律进一步固化, 可以考虑把它抽成更通用的多机位数据准备脚本,而不只服务 `s01`.

## [2026-03-11 08:09:36 UTC] 主题: 对无畸变渲染图, 过于自由的 COLMAP 相机模型会把几何误差“吸收到内参里”

### 发现来源
- 在排查 `data/s01` 一键脚本训练后“空间被压扁”的问题时, 对同一批 full data 做了 `PINHOLE` 与 `SIMPLE_PINHOLE` 的真实对照重建.

### 核心问题
- 直觉上容易觉得“模型更自由应该更准”, 但对无畸变、近似方形像素的渲染图, `PINHOLE` 的独立 `fx/fy` 反而可能吸收几何误差.
- 在 `data/s01` 上, 这种吸收直接表现为:
  - `PINHOLE`: `fx≈3231`, `fy≈8162`, sparse `y` 方向跨度仅 `5.82`
  - `SIMPLE_PINHOLE`: `f≈3231`, sparse `y` 方向跨度提升到 `16.56`

### 为什么重要
- 这是一条比“某个脚本参数怎么写”更高层的规律.
- 以后遇到“训练后空间被压扁”“视角看着怪”“相机高度不对”时, 应先去查 COLMAP 的 `cameras.bin`, 而不是直接在 3DGS 训练参数上乱试.

### 未来风险
- 如果后续把这类渲染图继续默认喂给 `PINHOLE`, 很容易再次出现“重建能跑通, 但几何比例离谱”的隐性问题.
- 只看 `Registered images` 或 `Mean reprojection error` 也不够, 因为它们可能还不错, 但几何比例已经明显失真.

### 当前结论
- 对 `data/s01`, 已有动态证据支持把默认值改为 `SIMPLE_PINHOLE`.
- 是否所有渲染图都该一律使用 `SIMPLE_PINHOLE`, 还不能一概而论; 若数据确实存在非方形像素或已知 `fx/fy` 不同, 仍可能需要 `PINHOLE` 或固定相机参数.

### 后续讨论入口
- 下次如果再遇到合成数据的 SfM 异常, 优先做三步:
  - 对比 `cameras.bin` 的焦距参数是否离谱
  - 对比 `points3D.bin` 的三轴跨度
  - 再决定是改 `SIMPLE_PINHOLE`, 还是进一步固定 `camera_params`

## [2026-03-14 08:34:09 UTC] 主题: 自带 `pose/intrinsics` 的生成数据不该默认退回到 COLMAP 猜位姿

### 发现来源
- 在核查 `/workspace/lyra/assets/demo/static/diffusion_output_generated_my` 是否能直接进入 3DGS 流程时发现.

### 核心问题
- 这类目录已经自带:
  - `pose/*.npz`
  - `intrinsics/*.npz`
- 但当前仓库训练入口只认:
  - `sparse/`(COLMAP)
  - `transforms_train.json`(Blender)
- 现有 `convert.py` 虽然能识别 `rgb/*.mp4`, 但会忽略现成位姿和内参, 重新用 COLMAP 做 SfM.

### 为什么重要
- 这不是“少一个命令行参数”的小问题.
- 它决定了仓库面对 synthetic / generated / 已知轨迹数据时, 是复用真值几何, 还是回退到猜测几何.

### 未来风险
- 如果继续默认用 COLMAP, 可能会:
  - 额外引入位姿误差
  - 让结果依赖纹理质量和匹配稳定性
  - 把“本来就有的真值信息”白白浪费掉

### 当前结论
- 当前仓库对这类路径的“最小可用”支持已经有了:
  - `convert.py` 能识别并抽取 `rgb` 视频
- 但“最正确”的长期支持还没有:
  - 缺少 `npz pose/intrinsics -> FastGS 可读格式` 的 direct importer

### 后续讨论入口
- 如果后续要把“只给路径就能一键生成 3DGS”做成稳定能力, 应优先讨论:
  - 是先补通用 wrapper
  - 还是直接补 `npz -> transforms/colmap` 的数据导入器

## [2026-03-14 09:05:22 UTC] 主题: direct loader 的派生缓存必须带版本元数据, 否则修复会被旧缓存悄悄抵消

### 发现来源
- 在修复 Lyra direct loader 的初始化几何问题时发现.

### 核心问题
- loader 一旦会把派生结果落盘缓存, 例如:
  - 抽帧 PNG
  - 初始化 `points3d.ply`
- 那么“代码逻辑已修复”并不等于“用户下一次运行就会得到新结果”.
- 如果缓存没有版本元数据, 旧缓存会继续被复用, 把已经修好的 bug 再次带回来.

### 为什么重要
- 这类问题非常隐蔽.
- 用户表面上看到的是:
  - “我明明拉了最新代码, 为什么结果还是老样子?”
- 但真正的问题在磁盘缓存, 不在源码.

### 未来风险
- 今后如果 direct loader 再调整:
  - 坐标系口径
  - 初始化几何
  - 抽帧策略
- 只要没有版本校验, 都可能出现“代码和缓存语义不一致”的幽灵问题.

### 当前结论
- 对派生缓存至少要记录:
  - 生成器版本
  - 关键参数
  - 上游输入特征
- 本次 Lyra 点云缓存已经落地:
  - `points3d_metadata.json`
  - 用于自动淘汰旧版“围绕原点”的错误初始化

### 后续讨论入口
- 如果后续继续扩展 direct loader, 可以把“缓存元数据 + 自动失效”抽成一个统一 helper, 避免每种缓存各写一套.

## [2026-03-14 09:54:08 UTC] 主题: render 阶段不能盲信 CLI 默认值, 必须优先尊重训练时保存的配置

### 发现来源
- 在为 Lyra 一键脚本补 `render.py -> metrics.py` 评估阶段时发现.

### 核心问题
- `render.py` 会通过 `get_combined_args(...)` 读取训练输出目录里的 `cfg_args`.
- 但它的命令行参数仍有默认值, 例如:
  - `--mult = 0.5`
- 当前合并逻辑会让“命令行默认值”覆盖“配置文件中的训练值”.

### 为什么重要
- 这意味着:
  - 即使训练时用了别的 `mult`
  - 只要 render 阶段没显式传正确值
  - 评估就可能在另一套 compact box 口径上进行
- 这种偏差很隐蔽, 因为流程表面上仍然会“正常跑完”.

### 未来风险
- 以后不只是 `mult`.
- 任何“训练后需要复跑的脚本”, 只要采用类似的“配置文件 + CLI 默认值合并”逻辑, 都可能出现同类口径漂移.

### 当前结论
- 对评估脚本, 不能简单依赖底层脚本默认值.
- 当前 Lyra wrapper 已经做了补救:
  - render 阶段在用户未显式传 `--mult` 时, 会从 `cfg_args` 回读训练保存值

### 后续讨论入口
- 如果后续要从根上修, 可以考虑调整 `get_combined_args(...)` 的合并策略, 让“未显式传入的 CLI 默认值”不要覆盖配置文件.

## [2026-03-14 11:58:30 UTC] 主题: 视频型 COLMAP 基线必须区分“快速评估”与“严格公平对比”

### 发现来源
- 在为 Lyra generated root 同时跑 direct 与 COLMAP 基线时, 先尝试了全量 `24 fps -> 726 图` 的传统流程, 后又改成 `--video-fps 4 -> 120 图` 的快速流程.

### 核心问题
- 这两类目标表面上都叫“跑 COLMAP 基线”, 但本质完全不同:
  - 快速评估:
    - 目标是尽快拿一版传统流程结果
  - 严格公平对比:
    - 目标是和 direct 路线在同一抽帧集合、同一切分下比较指标
- 如果不提前说清楚, 很容易把“快速模式跑出来的更高指标”误读成“COLMAP 一定更好”.

### 为什么重要
- 指标高低不仅取决于相机参数质量, 还会被 test 集规模和视角集合强烈影响.
- 这次就已经出现:
  - direct: `train=635`, `test=91`
  - quick COLMAP: `train=105`, `test=15`
- 在这种情况下, 两组 `PSNR / SSIM / LPIPS` 不能直接当成严格公平结论.

### 未来风险
- 如果后续团队只记住“COLMAP quick baseline 指标更高”, 会把一个“不同 test 集上的结果”错误升级成架构判断.
- 这会误导后续:
  - 参数选择
  - 文档口径
  - 甚至产品默认流程

### 当前结论
- 对视频型 COLMAP:
  - 全量 `24 fps + exhaustive matcher` 在这类数据上很重, 慢点主要在 `mapper + BA`
  - `--video-fps 4` 能快速得到一版可交付基线
- 但 quick baseline 的结果应明确标注为:
  - “快速参考”
  - 不是“严格同口径胜负结论”

### 后续讨论入口
- 如果后续还要正式回答“Lyra 参数好, 还是 COLMAP 参数好”, 应优先统一:
  - 抽帧集合
  - train/test 切分
  - 再复跑两边指标

## [2026-03-14 16:26:00 UTC] 主题: `set -u` 下的 bash wrapper 必须显式初始化所有布尔开关

### 发现来源
- 在真实验证 `scripts/run_lyra_flashvsr_fastgs.sh --phase prepare` 时发现.

### 核心问题
- 这类脚本通常会启用:
  - `set -euo pipefail`
- 一旦新增了布尔参数, 例如:
  - `--dry-run`
  - `--overwrite`
  - `--no-gpu`
- 如果顶部漏掉默认值初始化, 脚本不会等到真正业务逻辑才出错, 而会在参数校验阶段直接被 `set -u` 打断.

### 为什么重要
- 这种失败很迷惑.
- 用户表面上会以为:
  - 是路径问题
  - 是长文件名问题
  - 或者是下游工具失败
- 但真实根因其实是 shell 自己的未绑定变量.

### 未来风险
- 当前仓库已经有多份 bash wrapper:
  - `run_lyra_fastgs.sh`
  - `run_lyra_colmap_fastgs.sh`
  - `run_lyra_flashvsr_reference.sh`
  - `run_lyra_flashvsr_fastgs.sh`
- 后续继续扩参数时, 如果没有“新增布尔选项就先补默认值”的纪律, 很容易反复出现同类问题.

### 当前结论
- 对这类 wrapper, 一个简单但必须遵守的规则是:
  - 每个布尔开关在参数解析前都要有显式默认值
- 另外, 串联脚本还要检查“选项是否真的透传到了下游”, 否则帮助文本会比实际能力更大.

### 后续讨论入口
- 如果后续 bash wrapper 继续增多, 可以考虑抽一份更统一的 shell 参数模板或检查清单, 避免每个脚本各自漏一遍.

## [2026-03-14 17:45:00 UTC] 主题: 读 `COLMAP` 模型时, 图像名字段必须按“完整 UTF-8 字节串”处理, 不能假设 ASCII

### 发现来源
- 在 `xhc_flashvsr_colmap_fps12` 真实训练中, `read_extrinsics_binary(...)` 读取 `images.bin` 时触发 `UnicodeDecodeError`.

### 核心问题
- `COLMAP images.bin` 里的 `image_name` 是 NUL 结尾字符串.
- 只要文件名允许:
  - 中文
  - 空格
  - 其他非 ASCII 字符
- 那它在二进制层面就是 UTF-8 多字节序列.
- 如果解析器仍按“1 字节 = 1 字符”的思路逐个 decode, 一定会在某些文件名上炸掉.

### 为什么重要
- 这类错误极易误导定位.
- 用户看到的是:
  - `train.py` 读 COLMAP 失败
- 很容易以为:
  - COLMAP 重建坏了
  - 模型文件损坏了
  - 或者数据目录不完整
- 但真正坏掉的其实只是读取器对字符编码的假设.

### 未来风险
- 不只是二进制分支.
- 文本分支如果仍用无上限 `split()`, 一样会被带空格文件名拆坏.
- 只要仓库继续支持“用户真实原始文件名”而不是强制重命名, 这个兼容性就必须守住.

### 当前结论
- 读取 `COLMAP` 图像名时, 必须同时满足两条:
  - binary:
    - 先收集完整字节串, 再统一 `decode("utf-8")`
  - text:
    - 只分割前 9 个固定字段, 把剩余整段保留为 `NAME`

### 后续讨论入口
- 如果后续还会接更多外部数据源, 最稳的做法是把“支持 UTF-8/空格文件名”视为基础兼容要求, 而不是个例补丁.

## [2026-03-23 00:00:00 UTC] 主题: VerseCrafter 相机轨迹可被 direct loader 读入, 但训练稳定性仍未被证明

### 发现来源
- 在为 `/workspace/VerseCrafter/demo_data/my4` 设计“先超分再 FastGS”的命令时发现.
- 先把 VerseCrafter 目录轻量转换成 `view_id/{rgb,pose,intrinsics}` 后, 做了 direct 路线最小 smoke train.

### 核心问题
- 当前问题不是“VerseCrafter 数据完全无法接入 FastGS”.
- 新证据显示:
  - direct loader 能识别这类目录
  - `custom_camera_trajectory.npz` 也足以进入相机构建与初始化点云阶段
- 但训练仍可能在首轮 backward 报:
  - `cudaErrorInvalidConfiguration`

### 为什么重要
- 这意味着“能读入”不等于“能稳定训练”.
- 如果以后团队只记住“VerseCrafter 目录能转成 Lyra 风格”, 很容易误以为 direct 路线已经可直接对外推荐.
- 真正稳妥的口径应该更细:
  - 目录适配已基本打通
  - 训练稳定性还需要单独验证

### 未来风险
- 如果没有这条记录, 后续很可能重复走一遍:
  - 看到 loader 成功读入
  - 便过早把 direct 方案当成最终建议
  - 最后在用户长跑训练时才暴露首轮 CUDA 崩溃

### 当前结论
- VerseCrafter -> Lyra 风格目录转换本身是可行的.
- 对当前 `my4` 这类数据, 面向用户的稳定建议应优先:
  - `FlashVSR -> COLMAP -> FastGS`
- direct 路线应视为:
  - 已到“接近可用, 但还需继续验证”的状态

### 后续讨论入口
- 如果后续要正式支持 VerseCrafter direct 训练, 建议先复用本次 `my4` 转换根目录做最小可证伪实验, 再定位首轮 backward 的真实触发条件.

## [2026-03-23 15:03:08 UTC] 主题: 当前机器对 torch 和 CUDA COLMAP 实际只稳定暴露 1 张可用 GPU

### 发现来源
- 在给 VerseCrafter wrapper 做“双卡超分 + CUDA COLMAP”最小真实验证时发现.
- 先跑了:
  - `scripts/run_versecrafter_flashvsr_fastgs.sh --phase prepare --view-ids 0,1 --superres-gpu-ids 0,1`
- 随后又分别做了 torch 与 COLMAP 的最小 GPU 探测.

### 核心问题
- 从 `nvidia-smi` 看, 机器表面上有 2 张 A800.
- 但动态证据表明:
  - `CUDA_VISIBLE_DEVICES=0` 下, torch 正常
  - `CUDA_VISIBLE_DEVICES=1` 下, torch 返回:
    - `torch.cuda.is_available() = False`
  - `COLMAP --SiftExtraction.gpu_index 1` 也会报:
    - `Cannot set device to 1`
- 这说明“系统有两张卡”不等于“当前运行环境真的能把两张卡都交给训练与 SfM 使用”.

### 为什么重要
- 以后凡是用户提“双卡”“多卡”时, 如果只看 `nvidia-smi` 和硬件数量, 很容易误判脚本能力.
- 实际上这类问题可能根本不是脚本 bug, 而是:
  - 驱动 / 容器 / 权限 / 可见性映射
  - 让应用层只看到 1 张真正可用的 CUDA 设备

### 未来风险
- 如果不把这条规律记下来, 后面很可能反复发生:
  - 用户要求双卡
  - wrapper 按两张卡分片
  - 运行到中途才在某个 shard 里报 `No CUDA GPUs are available`
- 这种失败会被误解成:
  - FlashVSR 崩了
  - torch 崩了
  - 或新 wrapper 接线错了

### 当前结论
- 当前机器层面, 面向 torch / CUDA COLMAP 的可用 GPU 实际只有 1 张.
- VerseCrafter wrapper 的脚本接线已经没问题.
- 因此“现在不能真正双卡跑完”应归因于环境可见性, 不是脚本逻辑.

### 后续讨论入口
- 如果后续真的要把这台机子恢复到可用双卡, 建议优先单独排查:
  - `CUDA_VISIBLE_DEVICES=1` 为什么对 torch 不可用
  - `COLMAP` 为什么只能看到 1 个可设设备

## [2026-03-23 15:36:50 UTC] 主题: “系统看得到两张卡”与“CUDA 应用真能初始化两张卡”是两回事

### 发现来源
- 在回答“为什么只能用 0”时, 对 GPU1 做了更底层的最小验证.

### 核心问题
- 很多人看到:
  - `nvidia-smi -L` 有两张卡
  - `/dev/nvidia1` 设备节点也在
- 就会默认得出:
  - “应用当然也能用第 2 张卡”
- 这次动态证据明确说明这个推断不成立.

### 为什么重要
- 以后排“多卡为什么没生效”时, 不能只看硬件清单.
- 必须至少再做一条应用层最小验证:
  - `CUDA_VISIBLE_DEVICES=<id> python -c 'import torch; torch.cuda.init()'`

### 未来风险
- 如果没有这条规律, 很容易把环境问题继续误甩给:
  - wrapper
  - 训练参数
  - 某个具体模型代码

### 当前结论
- 这台机器当前已经被动态验证为:
  - 物理双卡
  - 但 CUDA 应用只稳定可用单卡
- 当前最可疑的异常信号是 MIG 配置不一致, 但还不是已证实根因.

### 后续讨论入口
- 如果要继续深挖, 优先围绕:
  - MIG 配置统一
  - CUDA runtime 的设备初始化链路

## [2026-03-23 16:31:22 UTC] 主题: 跨仓库拼接 `PYTHONPATH` 时, 不要把本地新模块放进通用顶层包名

### 发现来源
- 在收编 `run_flashvsr_reference.py` 的过程中, 做真实 dry-run 验证时发现.

### 核心问题
- 当运行环境同时挂着:
  - `/workspace/FlashVSR-Pro`
  - `/workspace/FastGS`
- 并且两边都存在通用顶层包名, 例如 `utils`, 就会出现 import 抢占.
- 结果往往不是“明确找不到本地模块”, 而是“误 import 到另一个仓库里的同名包”.

### 为什么重要
- 这种错误很隐蔽.
- 现象经常表现成“看起来缺了一个不相干依赖”, 实际根因却是模块命名空间冲突.

### 未来风险
- 后续如果还要继续把外仓脚本收编进来, 只要继续使用 `utils.*`、`common.*` 这种高撞名目录, 就还会重复踩坑.

### 当前结论
- 对这种跨仓库脚本, 更稳的做法是:
  - 使用独立包名前缀
  - 或放进明确属于本仓库的包, 例如 `scripts.*`
- 这次真实修复就是把 `utils.flashvsr_reference` 改成了 `scripts.flashvsr_reference_lib`.

### 后续讨论入口
- 下次再做“从别的仓库迁入 Python 工具”时, 先检查:
  - 最终运行时的 `PYTHONPATH`
  - 是否存在同名顶层包

## [2026-03-27 08:21:30 UTC] [Session ID: 019d2d07-3c10-70b0-a340-22753598e9ff] 主题: 指标继续上涨, 也不能证明 COLMAP 位姿已经足够正确

### 发现来源
- 这轮 `my4_mask_guarded_v4` 已经从分段守护一路推到 `30000`.
- 同时产出了 `10000 / 20000 / 30000` 三档视频和 `results.json`.
- 但用户在看结果时仍明确反馈“现在没了”, 并怀疑素材或 COLMAP 镜头解算质量导致重影.

### 核心问题
- `PSNR / SSIM / LPIPS` 继续改善, 说明模型在拟合训练与测试视角上还在进步.
- 但这不等于相机几何一定已经对了.
- 一旦前处理位姿本身有系统误差, 训练继续收敛, 也可能只是把错误几何拟合得更稳定, 而不是把重影真正消掉.

### 为什么重要
- 这会直接影响后续决策顺序.
- 如果把“指标在涨”误读成“继续多跑就能解决重影”, 很容易把算力继续砸在错误阶段.
- 对这类问题, 更值钱的下一步往往不是多 `5000` 或 `20000` 步, 而是先回到 COLMAP 结果本身做证据检查.

### 未来风险
- 继续从 `30000` 盲目冲到 `35000 / 50000`, 可能只会得到:
  - 更干净的错误几何
  - 更稳定的重影
  - 更难分辨“是训练问题还是位姿问题”

### 当前结论
- 已验证结论:
  - `my4_mask_guarded_v4` 到 `30000` 的训练、视频导出和指标统计都已完成.
  - 指标从 `10000 -> 30000` 持续上升.
- 当前假设:
  - 用户看到的重影, 更可能与素材质量 / COLMAP 位姿误差有关.
  - 这一点目前还缺少新的动态证据, 还不能直接下“根因已确认”的结论.

### 后续讨论入口
- 下次继续前, 优先检查:
  - `sparse/0` 的相机轨迹与稀疏点云形态
  - `cameras.bin / images.bin / points3D.bin` 的一致性
  - worst-view 对应的输入图像是否存在模糊、动态物体、重复纹理或曝光问题
