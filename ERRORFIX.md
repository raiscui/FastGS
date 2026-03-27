# ERRORFIX


## [2026-03-10 04:10:59 UTC] 错误名称: 追加 Markdown 时反引号触发 shell 命令替换

### 问题现象
- 在向 `task_plan.md` / `notes.md` 追加 Markdown 时,外层用了双引号包裹 shell 命令.
- 正文中的反引号片段如 `convert.py`、`input/` 被 shell 提前执行,导致终端出现 `command not found` 与路径不存在错误.
- 文件虽然被追加了内容,但反引号包裹的关键字被吃掉了.

### 原因
- 虽然内部 heredoc 用了单引号 `<<'EOF'`,但外层 `bash -lc "..."` 仍会先处理反引号命令替换.
- 这属于 shell 层命令构造错误,不是仓库代码逻辑错误.

### 修复
- 后续文件追加统一改为 `python3` 脚本写入,避免 shell 对正文做命令替换.
- 对已受影响的上下文信息,采用“追加纠正记录”的方式修复,不在原位置中途改写.

### 验证
- 使用 `python3` 追加上下文后,未再出现反引号触发的误执行.
- 后续 `task_plan.md` / `notes.md` / `WORKLOG.md` / `ERRORFIX.md` 均已成功追加.


## [2026-03-10 06:02:57 UTC] 错误名称: shell 变量在核查命令中被提前展开成空路径

### 问题现象
- 我在核查产物目录时写了 `bash -lc "root=...; ls -ld $root/input ..."`.
- 由于外层 shell 先展开了 `$root`,命令实际查成了 `/input`、`/images` 这类错误路径,终端出现 `No such file or directory`.

### 原因
- 变量定义和变量使用都放在双引号命令字符串里,被外层 shell 提前展开了.
- 这属于命令构造错误,不是数据转换失败.

### 修复
- 改用 `python3` 直接读取和统计真实目录,绕开 shell 变量展开风险.

### 验证
- 重查后确认真实目录 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x/input`、`images`、`sparse/0` 均存在且内容完整.

## [2026-03-10 06:20:00 UTC] 错误名称: 在双引号 `python3 -c` 命令里再次写入反引号文本, 仍会触发 shell 替换

### 问题现象
- 我尝试用 `python3 -c "...` 的方式向 `task_plan.md` 追加内容.
- 追加正文里包含 `` `output/` `` 这类反引号片段时, 外层 shell 仍然会先执行命令替换.
- 终端报错: `/bin/bash: line 1: output/: Is a directory`.

### 原因
- 即使主体逻辑已经切到 Python, 只要最外层命令还是双引号, 反引号就会在进入 Python 前先被 shell 处理.
- 根因仍然是 shell 引号层级不安全, 不是 Python 文件写入逻辑有问题.

### 修复
- 改成 `bash -lc 'python3 <<'"'"'PY'"'"' ... PY'` 这种单引号 heredoc 方案.
- 后续凡是要把 Markdown 原样追加到六文件, 都避免再用双引号包 `python3 -c`.

### 验证
- 改用单引号 heredoc 后, `task_plan.md` 成功追加包含反引号的正文, 未再触发 shell 误执行.

## [2026-03-10 06:41:00 UTC] 错误名称: 用 `pgrep -af <完整命令串>` 监控训练进程时, 误匹配到了监控命令自身

### 问题现象
- 我写了一个 `while pgrep -af "train.py -s ... -m ..." >/dev/null; do sleep 30; done` 的等待命令.
- 结果它一直不退出, 即使训练其实已经结束了.

### 原因
- `pgrep -af` 会匹配完整命令行.
- 监控命令自己的 shell 进程里就包含了同一段模式字符串, 所以等价于把自己也匹配进去了.

### 修复
- 放弃用这条 `pgrep` 循环做结束判定.
- 改为直接读取 `train.log` 和训练输出目录来确认最终状态, 这是更直接也更可靠的证据.

### 验证
- 重新通过 `train.log` 中的 `Training complete.`、`[ITER 30000] Saving Gaussians` 以及最终点云文件存在性完成核查后, 已确认训练真实结束.

## [2026-03-10 07:08:00 UTC] 错误名称: 为了回答 PSNR 误触发了 `LPIPS(vgg)` 大模型下载

### 问题现象
- 我最开始复用了 `metrics.py` 的完整指标口径, 连同 `LPIPS(vgg)` 一起跑.
- 终端随即开始下载 `vgg16-397923af.pth` 大约 528MB 权重, 明显超出了“只回答 PSNR”所需范围.

### 原因
- `metrics.py` 默认同时计算 `SSIM`、`PSNR`、`LPIPS`.
- `LPIPS(vgg)` 首次运行需要额外下载 VGG 权重, 这是隐藏的运行时成本.

### 修复
- 中止了这条无关的大下载流程.
- 改为仅调用仓库现有 `psnr` / `ssim` 实现计算用户当前真正需要的指标.

### 验证
- 改用精简脚本后, 已成功输出 `count=60`, `PSNR=26.6863`, `SSIM=0.8609`.

## [2026-03-11 06:50:50 UTC] 错误名称: 用“相机目录软链接”喂给 COLMAP,导致数据库始终是 0 图 0 match

### 问题现象
- 用户按旧文档先把:
  - `data/s01_colmap/images/C01pick -> data/s01/C01pick`
  - `data/s01_colmap/images/C02pick -> data/s01/C02pick`
  - ...
  这种“目录级软链接”喂给 COLMAP.
- 随后 `mapper` 报错:
  - `No images with matches found in the database`
- 继续核查数据库发现:
  - `cameras = 0`
  - `images = 0`
  - `keypoints = 0`
  - `matches = 0`
  - `two_view_geometries = 0`

### 原因
- 问题不在 `mapper`,而在更早的 `feature_extractor`.
- 已通过最小对照实验验证:
  - 目录软链接 -> 数据库仍为 0
  - 真实目录 + 文件复制 -> 正常入库
  - 真实目录 + 文件软链接 -> 正常入库
- 也就是说,当前这条 COLMAP 流程不会按预期读取“目录软链接”里的图片.

### 修复
- 新增 `scripts/run_s01_fastgs.sh`.
- 脚本改为:
  - 创建真实相机目录
  - 在目录里逐张建立“文件级软链接”
  - `feature_extractor` 后立即检查数据库中的 `images` / `cameras`
  - `exhaustive_matcher` 后立即检查 `two_view_geometries`
- 同步修正文档 `docs/s01_3dgs_workflow.md`, 移除旧的“目录软链接”写法.

### 验证
- 真实 smoke test 命令:
  - `bash scripts/run_s01_fastgs.sh --overwrite --frame-limit 1 --iterations 10 --colmap-root data/s01_colmap_script_smoke --fastgs-root data/s01_fastgs_script_smoke --model-path output/s01_script_smoke`
- 关键输出:
  - `feature_extractor 完成: cameras=6, images=6`
  - `exhaustive_matcher 完成: two_view_geometries=15`
  - `Reconstruction with 6 images and 2389 points`
  - `Training complete.`
- 关键产物:
  - `data/s01_fastgs_script_smoke/sparse/0/points3D.ply`
  - `output/s01_script_smoke/point_cloud/iteration_10/point_cloud.ply`

## [2026-03-11 08:09:36 UTC] 错误名称: `data/s01` 使用 `PINHOLE` 重建时空间被明显压扁

### 问题现象
- 用户执行 `bash scripts/run_s01_fastgs.sh --overwrite` 后, 观察到训练结果“高度像正常的一半”, 空间有明显被压扁的感觉.
- 旧结果里 `output/s01/cameras.json` / `data/s01_colmap/sparse/0/cameras.bin` 出现异常内参:
  - `fx≈3231`
  - `fy≈8162`
- `data/s01_colmap/sparse/0/points3D.bin` 的包围盒约为 `[76.37, 5.82, 46.02]`, 说明异常在 COLMAP 阶段就已经形成.

### 原因
- 不是 FastGS 训练参数单独导致的.
- 已通过 full data 对照实验验证:
  - `PINHOLE` 会把这批无畸变渲染图拟合成异常的双焦距比例
  - `SIMPLE_PINHOLE` 则能保持更稳定的内参, 同时得到更厚实的 `y` 方向几何
- 因此根因是 `data/s01` 当前默认使用 `PINHOLE` 作为 COLMAP 相机模型, 对这批数据过于自由.

### 修复
- 将 `scripts/run_s01_fastgs.sh` 的默认相机模型改为 `SIMPLE_PINHOLE`.
- 新增 `--camera-model <SIMPLE_PINHOLE|PINHOLE>` 开关, 允许按数据情况覆盖.
- 同步更新 `docs/s01_3dgs_workflow.md`, 把手动命令与排障说明改为 `SIMPLE_PINHOLE` 口径.

### 验证
- full data 对照:
  - `PINHOLE`
    - `points=80107`
    - `Mean reprojection error=0.595019px`
    - `spans=[76.367331, 5.817529, 46.023958]`
  - `SIMPLE_PINHOLE`
    - `points=86581`
    - `Mean reprojection error=0.573127px`
    - `spans=[76.727743, 16.558864, 59.953666]`
- 新版脚本 smoke test:
  - `bash scripts/run_s01_fastgs.sh --overwrite --frame-limit 1 --iterations 10 --colmap-root data/s01_colmap_simple_smoke_verify --fastgs-root data/s01_fastgs_simple_smoke_verify --model-path output/s01_simple_smoke_verify`
  - 关键输出:
    - `feature_extractor 完成: cameras=6, images=6`
    - `exhaustive_matcher 完成: two_view_geometries=15`
    - `Reconstruction with 6 images and 1974 points`
    - `Training complete.`

## [2026-03-14 09:05:22 UTC] 错误名称: Lyra direct loader 首轮 backward 报 `cudaErrorInvalidConfiguration`

### 问题现象
- 真实命令:
  - `pixi run python train.py -s /workspace/lyra/assets/demo/static/diffusion_output_generated_my -m output/dj_style_direct_smoke --iterations 10 --eval -r 8`
- direct loader 已经成功读取 Lyra 场景.
- 但训练在第一次 backward 就失败:
  - `torch.AcceleratorError: CUDA error: invalid configuration argument`
- 最小复现定位到首轮选中的相机:
  - `dj-style_v4_f00071`

### 原因
- 根因不是目录识别失败, 也不是 `pose/intrinsics` 读取失败.
- 已通过静态与动态证据确认:
  - Lyra 的相机轨迹共同注视点在 `z≈8.855`
  - 旧版 direct loader 仍沿用“围绕原点”的随机点云初始化
  - 对失败相机 `dj-style_v4_f00071`, 原点在相机后方:
    - `dot_to_origin = -1.41003`
  - 共同注视点在相机前方:
    - `dot_to_focus = 7.44510`
  - 几何投影验证:
    - 原点初始化: `origin_front = 0`, `origin_inside = 0`
    - focus 初始化: `focus_front = 100000`, `focus_inside = 64612`
- 因此首轮报错的真正原因是:
  - 初始化点云没有落在场景公共关注区域内, 导致某些视角完全看不到任何点.

### 修复
- 在 `scene/dataset_readers.py` 中新增:
  - 从训练相机反推相机中心与前向方向
  - 用多条视线最小二乘估计共同注视点
  - 用 `median(camera_to_focus_distance) * 0.25` 估计初始化范围
  - 围绕 focus 中心生成 Lyra 初始化点云
- 同时新增:
  - `points3d_metadata.json`
  - 缓存版本校验
  - 自动重建旧版“围绕原点”的错误缓存

### 验证
- 静态校验:
  - `pixi run python -m py_compile scene/dataset_readers.py scene/__init__.py tests/test_lyra_generated_loader.py`
- 单元测试:
  - `pixi run python -m unittest discover -s tests -p 'test_lyra_generated_loader.py'`
  - 结果: `Ran 4 tests ... OK`
- 真实目录验证:
  - `readLyraGeneratedSceneInfo(...)` 生成了新的 `points3d_metadata.json`
  - `pcd_center ≈ [0.0035, -0.0092, 8.8539]`
- 真实 smoke train:
  - `pixi run python train.py -s /workspace/lyra/assets/demo/static/diffusion_output_generated_my -m output/dj_style_direct_smoke_focus --iterations 10 --eval -r 8`
  - 关键输出:
    - `Number of points at initialisation : 100000`
    - `Training progress ... 10/10`
    - `Training complete.`

## [2026-03-14 16:26:00 UTC] 错误名称: `run_lyra_flashvsr_fastgs.sh` 在 `phase prepare` 前即因 `DRY_RUN` 未初始化退出

### 问题现象
- 真实命令:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase prepare --view-ids 0 --flashvsr-output-root /tmp/flashvsr_xhc_prepare_actual --prepared-root data/flashvsr_xhc_prepare_actual_root --overwrite`
- 脚本还没进入真实超分, 就直接报错:
  - `scripts/run_lyra_flashvsr_fastgs.sh: line 761: DRY_RUN: unbound variable`

### 原因
- 根因不在长文件名, 也不在 FlashVSR 本体.
- 已通过失败位置确认:
  - 脚本启用了 `set -euo pipefail`
  - 但顶部没有给 `DRY_RUN` 赋默认值
  - 后面参数校验阶段直接访问 `DRY_RUN`, 于是被 `set -u` 打断

### 修复
- 在 `scripts/run_lyra_flashvsr_fastgs.sh` 中新增:
  - `DRY_RUN=0`
- 顺手补齐:
  - `--fallback-tile-size`
  - `--fallback-overlap`
  这两个选项从串联脚本到 `run_lyra_flashvsr_reference.sh` 的透传, 避免链路能力缩水

### 验证
- 静态校验:
  - `bash -n scripts/run_lyra_flashvsr_fastgs.sh`
- 修复后真实 `prepare`:
  - 命令同上
  - 成功生成 SR 视频与 symlink root
- 修复后真实 `train` smoke:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase train --view-ids 0 --flashvsr-output-root /tmp/flashvsr_xhc_prepare_actual --prepared-root data/flashvsr_xhc_prepare_actual_root --model-path output/flashvsr_xhc_chain_train_smoke --iterations 1 -r 8 --no-eval --overwrite`
  - 关键输出:
    - `Found Lyra generated multi-view root`
    - `Training complete.`

## [2026-03-14 17:45:00 UTC] 错误名称: `read_extrinsics_binary` 无法解析 `COLMAP images.bin` 中的中文文件名

### 问题现象
- 用户真实执行 `--pipeline colmap` 训练时, 报错:
  - `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xe6 in position 0: unexpected end of data`
- 调用栈定位到:
  - `scene/colmap_loader.py::read_extrinsics_binary`
- 后续回退到文本分支时, 又因为没有 `images.txt` 继续失败

### 原因
- 根因不是 `COLMAP` 没有重建出相机.
- 已通过静态对照和真实复现确认:
  - `images.bin` 中的 `image_name` 含中文 UTF-8 多字节字符
  - 当前解析器按单字节逐个 `.decode("utf-8")`
  - 这会把一个字符拆成多个字节, 从而直接解码失败
- 另外, 文本分支 `read_extrinsics_text(...)` 也存在潜在兼容性问题:
  - `line.split()` 会把带空格文件名拆坏

### 修复
- 在 `scene/colmap_loader.py` 中新增:
  - `read_null_terminated_utf8(fid)`
- 调整:
  - `read_extrinsics_binary(...)` 改为先积累完整字节串, 再一次性 `decode("utf-8")`
  - `read_extrinsics_text(...)` 改为 `encoding="utf-8"` + `split(maxsplit=9)`
- 新增回归测试:
  - `tests/test_colmap_loader.py`

### 验证
- 单元测试:
  - `pixi run python -m unittest tests.test_colmap_loader`
  - 结果:
    - `Ran 2 tests ... OK`
- 真实数据 smoke train:
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_flashvsr_colmap_fps12_unicode_smoke --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Reading camera 180/180`
    - `Training complete.`
- 真实 wrapper smoke train:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase train --pipeline colmap --video-fps 12 --fastgs-root /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 --model-path /workspace/FastGS/output/xhc_flashvsr_colmap_fps12_wrapper_smoke --iterations 1 -r 8 --overwrite`
  - 关键输出:
    - `Reading camera 180/180`
    - `Training complete.`

## [2026-03-15 06:20:00 UTC] 错误名称: `convert.py` 固定选择 `distorted/sparse/0` 导致首轮 `cudaErrorInvalidConfiguration`

### 问题现象
- 用户真实训练:
  - `/workspace/FastGS/output/xhc_bai_flashvsr_colmap_fps12`
- 关键失败信号:
  - `Reading camera 4/4`
  - `Number of points at initialisation : 2`
  - 首轮 `loss.backward()` 报:
    - `torch.AcceleratorError: CUDA error: invalid configuration argument`
- 同一份数据的数据库统计却显示:
  - `images=360`
  - `two_view_geometries=64620`

### 原因
- 根因不是 CUDA kernel 自身随机坏掉.
- 已通过静态和动态证据确认:
  - `mapper` 实际产出了多个 sparse 子模型:
    - `0`: `Registered images=4`, `Points=2`
    - `1`: `Registered images=15`, `Points=2581`
    - `2`: `Registered images=360`, `Points=92946`
  - 旧版 `convert.py` 却把 `image_undistorter` 的输入硬编码成:
    - `distorted/sparse/0`
- 结果就是:
  - undistort 和后续训练总是拿到最差模型
  - 最终把“COLMAP 有好模型”误降级成“训练只有 2 个初始点”

### 修复
- 在 `convert.py` 中新增:
  - `SparseModelStats`
  - 多子模型统计逻辑
  - `select_best_sparse_model(...)`
- 默认选择规则:
  - 先比 `registered_image_count`
  - 再比 `point_count`
  - 最后比 `camera_count`
- `image_undistorter` 改为使用自动选出的最佳模型路径, 不再硬编码 `sparse/0`.
- 同时新增回归测试:
  - `tests/test_convert.py`

### 验证
- 静态校验:
  - `pixi run python -m py_compile convert.py tests/test_convert.py`
- 单元测试:
  - `pixi run python -m unittest tests.test_convert`
  - 结果:
    - `Ran 3 tests ... OK`
- 真实转换验证:
  - `pixi run python convert.py --skip_matching -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12_convert_fix_verify`
  - 关键日志:
    - `Selected COLMAP sparse model '2'`
- 真实训练验证:
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12_convert_fix_verify -i images -m /workspace/FastGS/output/xhc_bai_convert_fix_verify_smoke --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Reading camera 360/360`
    - `Number of points at initialisation :  92946`
    - `Training complete.`

## [2026-03-23 15:03:08 UTC] 错误名称: VerseCrafter wrapper 默认把 `ffmpeg` 命令名误当成路径, 且双卡失败信息不够早

### 问题现象
- 对新脚本执行:
  - `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --phase superres --dry-run --overwrite`
- 最早暴露的错误是:
  - `ERROR: 文件不存在: /workspace/FastGS/ffmpeg`
- 修掉后继续做最小真实验证时, 还观察到:
  - 第二个 FlashVSR shard 运行到中途才报:
    - `RuntimeError: No CUDA GPUs are available`

### 原因
- 第一层原因:
  - `scripts/run_versecrafter_flashvsr_fastgs.sh` 之前会无条件把 `FFMPEG_BIN` 做路径归一化
  - 对默认值 `ffmpeg` 而言, 这会被误改成仓库内伪路径
- 第二层原因:
  - 旧脚本在真正分片前没有逐卡验证 local torch 环境是否能看到 CUDA
  - 结果是 GPU 不可用时, 用户只能在某个 shard 的深层日志里才看到失败

### 修复
- 新增“仅当参数本身是显式路径时才归一化”的逻辑.
- `COLMAP prepare` 阶段不再额外强塞 `CUDA_VISIBLE_DEVICES`, 避免 GPU index 与环境重映射歧义.
- `train` 阶段在已有 `FASTGS_ROOT/images + sparse/0` 时, 不再强依赖 `PREPARED_ROOT`.
- 对 local FlashVSR runner 新增逐卡预检:
  - 在真正分片前执行:
    - `CUDA_VISIBLE_DEVICES=<gpu_id> <local_python> -c 'import torch; ...'`
  - 如果该卡不可用, 直接给出明确错误并停止

### 验证
- 静态验证:
  - `bash -n scripts/run_versecrafter_flashvsr_fastgs.sh`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m py_compile convert.py`
- dry-run 验证:
  - `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --phase superres --dry-run --overwrite`
  - 已成功完成 12 视频分片与汇总
- 预检验证:
  - `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --scene-stem generated_video_0 --view-ids 0,1 --phase prepare --mode tiny --superres-gpu-ids 0,1 --colmap-gpu-index 0,1 --bridge-root /workspace/FastGS/data/my4_smoke_bridge --flashvsr-output-root /workspace/FastGS/data/my4_smoke_flashvsr --prepared-root /workspace/FastGS/data/my4_smoke_prepared --fastgs-root /workspace/FastGS/data/my4_smoke_fastgs --overwrite`
  - 关键输出:
    - `FlashVSR GPU 预检通过: gpu=0`
    - `gpu=1 torch.cuda.is_available()=False device_count=1`
    - `ERROR: FlashVSR local runner 当前无法使用 GPU 1`
- 真实故障目录就地修复验证:
  - 先备份旧坏产物:
    - `images -> images_bad_20260315_0625`
    - `sparse -> sparse_bad_20260315_0625`
  - 再执行:
    - `pixi run python convert.py --skip_matching -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12`
    - `pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_bai_flashvsr_colmap_fps12_fixed_smoke --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Selected COLMAP sparse model '2'`
    - `Reading camera 360/360`
    - `Number of points at initialisation :  92946`
    - `Training complete.`
- 原始报错输出路径回归验证:
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_bai_flashvsr_colmap_fps12 --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Reading camera 360/360`
    - `Number of points at initialisation :  92946`
    - `Training complete.`

## [2026-03-23 16:31:22 UTC] 错误名称: 收编 `FlashVSR` reference 模块后与 `FlashVSR-Pro/utils` 包撞名

### 问题现象
- 我把 lyra 里的实现先迁成了 `utils.flashvsr_reference`.
- 随后执行真实 dry-run:
  - `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --phase superres --view-ids 0,1 --dry-run ...`
- 结果失败:
  - `ModuleNotFoundError: No module named 'einops'`
- 调用栈显示 import 实际落到了:
  - `/workspace/FlashVSR-Pro/utils/__init__.py`

### 原因
- wrapper 为了让 `infer.py` 工作, 会设置:
  - `PYTHONPATH=/workspace/FlashVSR-Pro:/workspace/FastGS`
- 在这个顺序下, `import utils.flashvsr_reference` 会先命中 `FlashVSR-Pro/utils`.
- 这不是“新模块缺依赖”, 而是顶层包名 `utils` 与外仓重名.

### 修复
- 放弃使用 `utils.flashvsr_reference` 这个通用顶层名.
- 改为:
  - `scripts/flashvsr_reference_lib.py`
  - `scripts/__init__.py`
  - `from scripts.flashvsr_reference_lib import ...`

### 验证
- `pixi run python -m py_compile scripts/__init__.py scripts/flashvsr_reference_lib.py scripts/run_flashvsr_reference.py tests/test_flashvsr_reference.py`
- `pixi run python -m unittest discover -s tests -p 'test_flashvsr_reference.py'`
  - 结果: `Ran 9 tests ... OK`
- `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --phase superres --view-ids 0,1 --dry-run --bridge-root data/versecrafter_bridge_migrate_smoke --flashvsr-output-root data/versecrafter_flashvsr_migrate_smoke --overwrite`
  - 结果: 通过
  - 关键输出:
    - `执行: ... /workspace/FastGS/scripts/run_flashvsr_reference.py ...`
    - `status=succeeded`

## [2026-03-27 05:48:00 UTC] [Session ID: 119e250a-72a8-40a1-bad2-1a106f4b536a] 错误名称: shell 日志字符串里的反引号触发命令替换

### 问题现象
- 在给 `scripts/run_lyra_colmap_fastgs.sh` 增加“已准备好的 COLMAP 根目录自动识别”后, 真实执行:
  - `bash scripts/run_lyra_colmap_fastgs.sh --source-path /home/rais/FreeFix/data/my4_fullcolmap --phase prepare`
- 结果出现:
  - `scripts/run_lyra_colmap_fastgs.sh: line 276: --source-path: command not found`
- 但同一轮输出又显示:
  - `Prepared dataset root: .../my4_fullcolmap`

### 原因
- 根因不是目录识别失败.
- 也不是 `prepare` 分支逻辑错误.
- 真正原因是我把日志写成了:
  - `log "检测到 \`--source-path\` 已经是可训练的 ..."`
- shell 在双引号内仍会处理反引号, 于是把 `` `--source-path` `` 当成命令替换执行.

### 修复
- 去掉运行态日志和失败提示里的反引号.
- 保留帮助文档里的反引号, 因为那部分在单引号 heredoc 内, 不会被 shell 执行.

### 验证
- `bash -n scripts/run_lyra_colmap_fastgs.sh`
- `bash scripts/run_lyra_colmap_fastgs.sh --source-path /home/rais/FreeFix/data/my4_fullcolmap --phase prepare`
  - 关键输出:
    - `检测到 source-path 已经是可训练的 COLMAP / FastGS 根目录, 跳过 convert.py`
    - 没有再出现 `command not found`
- 额外回归:
  - `python3` 扫描脚本里的“带双引号且含反引号”的运行态字符串
  - 结果为空

## [2026-03-27 14:12:23 CST] [Session ID: a354b352-2b30-435e-b917-cd8fed8e5060] 错误名称: COLMAP 场景的 alpha mask 路径失效, 且缺少独立 mask 目录入口

### 问题现象
- 用户询问是否能用 mask 压掉空中“棉絮”.
- 代码静态阅读显示仓库里虽然有 `gt_alpha_mask` 路径, 但 `my4_fullcolmap` 当前没有 alpha 图, 也没有 `masks/` 目录.
- 最小动态验证进一步显示:
  - `PILtoTorch(RGBA)` 的输出是 `(4, H, W)`
  - 当前代码却检查 `shape[1] == 4`
  - 结果是普通 RGBA 图不会进入 mask 分支

### 原因
- `utils/camera_utils.py` 把通道维度写错了.
- `scene/dataset_readers.py` 的 COLMAP 读取路径只认 `images/`, 没有给独立 `mask_dir` 一个正式入口.
- 两者叠加后, 形成了“看起来像支持 alpha, 实际不真正可用”的假能力.

### 修复
- 将 alpha 检测条件改为 `shape[0] == 4`.
- 在 `arguments/__init__.py` 新增 `mask_dir`.
- 在 `scene/__init__.py` 把 `mask_dir` 透传给 COLMAP 场景读取.
- 在 `scene/dataset_readers.py` 新增:
  - `mask_dir` / 自动 `masks/` 解析
  - 按同名或同 stem 匹配 mask
  - 将外部 mask 合并进 alpha 通道
  - 缺失同名 mask 时直接报错, 避免静默脏训练
- 在 `scripts/run_lyra_colmap_fastgs.sh` 新增 `--mask-dir`.

### 验证
- 静态验证:
  - `python3 -m py_compile arguments/__init__.py scene/__init__.py scene/dataset_readers.py utils/camera_utils.py tests/test_mask_loading.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
- 动态验证:
  - `pixi run python -m unittest tests.test_mask_loading`
  - 结果: `Ran 3 tests ... OK`
- 回归覆盖:
  - RGBA 图能正确提取 alpha
  - 外部 mask 能合并成 RGBA
  - 启用 mask 目录但缺失对应文件时会明确失败

## [2026-03-27 14:20:35 CST] [Session ID: a354b352-2b30-435e-b917-cd8fed8e5060] 错误名称: PyTorch 2.6+ 默认 `weights_only=True` 导致 FastGS checkpoint 无法 resume

### 问题现象
- 我用真实命令做 `10 -> 12` 的最小续训回归:
  - 先跑:
    - `bash scripts/run_lyra_colmap_fastgs.sh --source-path /home/rais/FreeFix/data/my4_fullcolmap --phase train --iterations 10 -r 8 --video-iterations 10 --model-path output/my4_resume_verify2 --overwrite`
  - 再从 `ckpt_10.pth` 续到 `12`
- 第二段第一次失败, 关键报错:
  - `_pickle.UnpicklingError: Weights only load failed`
  - 报错明确指出 PyTorch 2.6 把 `torch.load` 默认值改成了 `weights_only=True`

### 原因
- FastGS 保存的 checkpoint 不只是纯 tensor 权重.
- 里面还包含:
  - optimizer state
  - shoptimizer state
  - numpy 标量
- 继续沿用 `torch.load(checkpoint)` 时, 在 PyTorch 2.6+ 会被新的安全默认值拦住.

### 修复
- 在 [train.py](/root/autodl-tmp/home/rais/FastGS/train.py) 新增 `load_training_checkpoint(...)`
- 优先使用:
  - `torch.load(checkpoint_path, weights_only=False)`
- 对旧版 PyTorch 保留 `TypeError` 回退, 继续兼容:
  - `torch.load(checkpoint_path)`

### 验证
- 静态验证:
  - `python3 -m py_compile train.py`
- 动态验证:
  - 第一段:
    - `... --iterations 10 --video-iterations 10 ...`
    - 成功生成 `checkpoints/ckpt_10.pth`
  - 第二段:
    - `... --iterations 12 --start-checkpoint .../ckpt_10.pth --video-iterations 12 --position_lr_max_steps 12 --densify_until_iter 12 --overwrite`
    - 成功继续训练到 `12`
    - 成功输出:
      - `[ITER 12] Saving Checkpoint`
      - `Training complete.`

## [2026-03-27 07:44:00 UTC] [Session ID: 019d2d07-3c10-70b0-a340-22753598e9ff] 错误名称: mask 训练把“忽略区域”误当成“必须拟合成黑色”

### 问题现象
- `my4_fullcolmap` 启用 `mask_dir` 后, 真实训练多次出现:
  - `cudaErrorIllegalAddress`
  - `cudaErrorInvalidAddressSpace`
- 但 true no-mask 对照在同一组稳态参数下可以稳定跑完 `9000`.
- 带 mask 修复后, 同样参数也能重新稳定跑完 `9000`.

### 原因
- 旧实现只做了:
  - `Camera.original_image *= gt_alpha_mask`
- 训练主 loss 和 FastGS densify 用到的:
  - `compute_photometric_loss(...)`
  - `metric_map`
  都没有把 render 图像同步套同一份 mask.
- 这导致被 mask 的亮点像素并没有真正退出优化.
- 它们只是被拿去和“被涂黑的 GT”比较, 等价于强行要求模型把这些位置拟合成黑色.

### 修复
- `scene/cameras.py`
  - 持久化 `gt_alpha_mask`
- `train.py`
  - 训练主 loss 改为先对 render 同步套 mask, 再与 GT 比较
- `utils/fast_utils.py`
  - `compute_photometric_loss(...)`
  - `metric_map` 生成
  都改成对 render 同步应用 mask
- `utils/loss_utils.py`
  - 新增 `apply_loss_mask(...)`

### 验证
- 静态校验:
  - `pixi run python -m py_compile train.py scene/cameras.py utils/fast_utils.py utils/loss_utils.py tests/test_mask_loss.py`
- 单元测试:
  - `pixi run python -m unittest tests.test_mask_loss tests.test_mask_loading`
  - 结果: `OK`
- 动态对照:
  - true no-mask:
    - `output/my4_nomask_true_9000`
    - 成功跑完 `9000`
- 带 mask 修复后:
    - `output/my4_mask_fixed_9000`
    - 同样参数成功跑完 `9000`

## [2026-03-27 17:55:35 UTC] [Session ID: 28616] 错误名称: `my5` 目录会误把辅助视频送进 COLMAP, 且 COLMAP 4.x 不认旧 GPU 参数

### 问题现象
- 真实目录 `/root/autodl-fs/my5` 下, 每个视角目录同时包含:
  - `generated_videos/generated_video_0.mp4`
  - `rendering_4D_maps/merged_mask.mp4`
  - `background_*` / `depth_*` / `3D_gaussian_*`
- 旧 `convert.py` 在缺少 `rgb/` 时会退到全局递归发现视频.
- 第一次真实 `prepare` 还进一步暴露:
  - 本机 COLMAP 4.0.2 报:
    - `unrecognised option '--SiftExtraction.use_gpu'`

### 原因
- 第1层:
  - 视频发现规则缺少 `generated_videos` 这类业务语义更明确的优先级, 递归兜底太宽.
- 第2层:
  - 旧前处理没有“mask 视频 -> mask 图”的正式入口.
- 第3层:
  - `convert.py` 把 GPU 参数名写死成 COLMAP 3.x 口径:
    - `--SiftExtraction.use_gpu`
    - `--SiftMatching.use_gpu`
  - 但本机 COLMAP 4.x 已改成:
    - `--FeatureExtraction.use_gpu`
    - `--FeatureMatching.use_gpu`

### 修复
- 在 `convert.py` 中:
  - 新增 `generated_videos` 优先发现
  - 新增 `merged_mask.mp4` 自动配对与同步抽帧
  - 新增运行前读取 `colmap <subcommand> -h` 的兼容层, 自动选择 3.x / 4.x 选项名
- 在 `scripts/run_lyra_colmap_fastgs.sh` 中:
  - 训练阶段自动优先使用 `<fastgs-root>/masks`
  - 默认 CUDA COLMAP 路径不存在时, 自动回退到 PATH 里的 `colmap`

### 验证
- 静态验证:
  - `python3 -m py_compile convert.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m unittest tests.test_convert`
- 真实动态验证:
  - `prepare` 已确认输出:
    - `972` 张 `input`
    - `972` 张 `masks`
    - `distorted/database.db`
  - 真实日志已确认:
    - `feature_extractor` 使用 `--FeatureExtraction.use_gpu`
    - `exhaustive_matcher` 使用 `--FeatureMatching.use_gpu`
    - 当前已进入 COLMAP `exhaustive_matcher`

## [2026-03-27 10:27:38 UTC] [Session ID: 80800] 错误名称: 把 `rendering_4D_maps/merged_mask.mp4` 误接成 FastGS 训练 mask

### 问题现象
- 在支持 `my5` 多镜头视频目录时, 我把 `generated_videos/generated_video_0.mp4` 同视角下的 `rendering_4D_maps/merged_mask.mp4` 自动抽成了 `<fastgs-root>/masks`.
- 后续 wrapper 和 `scene/dataset_readers.py` 都会把这个目录识别成训练 mask 目录.
- 这会让深度辅助 mask 误进入 RGB photometric loss.

### 原因
- 我之前把 `merged_mask.mp4` 的语义假设成了“普通训练 mask”.
- 用户后来明确说明: 它其实是“非深度数据区域”的 mask, 用于深度图链路, 不是训练 alpha mask.
- 错误不在 ffmpeg 或 COLMAP, 而在输入语义分类本身.

### 修复
- `convert.py`
  - 撤掉 `merged_mask.mp4 -> masks/` 的默认自动接线.
- `scene/dataset_readers.py`
  - 自动 mask 探测改成“目录存在且非空”才启用.
- `scripts/run_lyra_colmap_fastgs.sh`
  - 自动 mask 识别同步改成只认已有且非空的目录.
- 运行态数据处理:
  - 将 `data/my5_colmap_fastgs/masks` 挪到 `data/my5_colmap_fastgs/depth_masks_from_merged_mask_20260327_102621`.

### 验证
- 静态验证:
  - `python3 -m py_compile convert.py scene/dataset_readers.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
- 回归测试:
  - `pixi run python -m unittest tests.test_convert tests.test_mask_loading`
  - 输出: `Ran 11 tests ... OK`
- 动态状态:
  - 真实 `prepare` 会话 `26742` 仍在 COLMAP `exhaustive_matcher`, 说明修复发生在训练启动前.
  - 无 mask 训练等待器 `96836` 已启动, 会在 `prepare` 完成后自动接棒.
