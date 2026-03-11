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
