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
