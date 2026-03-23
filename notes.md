# 笔记: `FlashVSR -> FastGS` 串联脚本与长文件名验证

## [2026-03-14 16:35:00 UTC] 六文件摘要与续档说明

### 续档原因
- 旧 `notes.md` 已超过 1000 行.
- 已按规则续档到:
  - `archive/notes_2026-03-14_163400.md`

### 六文件摘要
- 任务目标:
  - 把 `FlashVSR-Pro` 超分接到 FastGS.
  - 同时支持 direct 与 colmap 两条后续路线.
  - 支持带空格、中文、逗号的长 `.mp4` 文件名.
- 关键决定:
  - 新增两个 wrapper:
    - `scripts/run_lyra_flashvsr_reference.sh`
    - `scripts/run_lyra_flashvsr_fastgs.sh`
  - 长文件名不要求用户再手抄 `scene_stem`, 优先支持 `--source-video`.
- 关键发现:
  - 真实历史超分命令来自 `/workspace/lyra/scripts/run_flashvsr_reference.py` 对 `/workspace/FlashVSR-Pro/infer.py` 的封装.
  - 长文件名场景在 6 个视角下共享同一个 `scene_stem`.
  - direct loader 已经能直接读取 `view_id/{rgb,pose,intrinsics}` 结构.
- 实际变更:
  - 新增独立 SR wrapper.
  - 新增 SR -> FastGS 串联脚本.
  - 已把串联脚本信息同步到 `specs/lyra_direct_loader.md`.
- 暂缓事项:
  - `--pipeline colmap` 路线当前已完成静态接线, 但这轮没有做完整动态训练验证.
- 错误与根因:
  - `run_lyra_flashvsr_fastgs.sh` 在 `set -u` 下访问了未初始化的 `DRY_RUN`.
- 可复用点候选:
  - bash 串联脚本里, 所有布尔开关都必须先初始化再进入参数校验.
  - 做长文件名支持时, 最稳的入口不是让用户重复输入 stem, 而是从 `--source-video` 反推上下文.
  - SR 中间产物与原始 `pose/intrinsics` 的拼接, 用 symlink root 比复制更稳也更省空间.
- 最适合写到哪里:
  - 当前复用价值最高的是项目规格文档, 已同步到 `specs/lyra_direct_loader.md`.
  - 暂无足够长期、足够通用的新规则需要写入根 `AGENTS.md`.

## [2026-03-14 16:36:00 UTC] 串联脚本动态验证

### 现象
- 静态检查:
  - `bash -n scripts/run_lyra_flashvsr_fastgs.sh`
  - 结果: 通过
- 长文件名 dry-run:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase superres --dry-run --flashvsr-output-root /tmp/flashvsr_xhc_dryrun_chain_verify`
  - 结果: 通过
- 首次真实 `prepare`:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase prepare --view-ids 0 --flashvsr-output-root /tmp/flashvsr_xhc_prepare_actual --prepared-root data/flashvsr_xhc_prepare_actual_root --overwrite`
  - 结果: 失败
  - 报错:
    - `scripts/run_lyra_flashvsr_fastgs.sh: line 761: DRY_RUN: unbound variable`

### 假设
- 主假设:
  - 串联脚本声明了 `--dry-run` 选项, 但没有给 `DRY_RUN` 默认值.
  - 在 `set -u` 下, 参数校验阶段访问 `DRY_RUN` 时就会提前退出.
- 备选解释:
  - 不是长文件名导致的 shell 解析问题.
  - 因为失败发生在真正进入超分前.

### 修复
- 在 `scripts/run_lyra_flashvsr_fastgs.sh` 顶部新增:
  - `DRY_RUN=0`
- 同时补齐两项参数透传:
  - `--fallback-tile-size`
  - `--fallback-overlap`

### 验证命令与结果
- 重新静态检查:
  - `bash -n scripts/run_lyra_flashvsr_fastgs.sh`
  - 结果: 通过
- 重新真实 `prepare`:
  - 同上命令
  - 结果: 通过
  - 关键产物:
    - `/tmp/flashvsr_xhc_prepare_actual/full_scale2x/0/rgb/<长文件名>.mp4`
    - `/tmp/flashvsr_xhc_prepare_actual/full_scale2x/0/manifests/<长文件名>.json`
    - `/tmp/flashvsr_xhc_prepare_actual/flashvsr_reference_summary.json`
    - `/workspace/FastGS/data/flashvsr_xhc_prepare_actual_root/0/{rgb,pose,intrinsics}/...`
- symlink root 检查:
  - `rgb/*.mp4` 已正确链接到 SR 输出
  - `pose/*.npz` 与 `intrinsics/*.npz` 已正确链接回原始 Lyra 输入
- 进一步 smoke train:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase train --view-ids 0 --flashvsr-output-root /tmp/flashvsr_xhc_prepare_actual --prepared-root data/flashvsr_xhc_prepare_actual_root --model-path output/flashvsr_xhc_chain_train_smoke --iterations 1 -r 8 --no-eval --overwrite`
  - 结果: 通过
  - 关键输出:
    - `Found Lyra generated multi-view root, loading direct pose/intrinsics inputs!`
    - `Training complete.`

### 结论
- 当前已被动态证据支持的链路是:
  - 长文件名 `--source-video`
  - `FlashVSR` 真实超分
  - SR root 组织
  - direct 路线最小训练启动
- 这轮还没有完整动态验证 `--pipeline colmap` 的训练链路.

## [2026-03-14 17:45:00 UTC] `COLMAP images.bin` 中文文件名解码失败修复

### 现象
- 用户在真实 `--pipeline colmap` 训练阶段遇到:
  - `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xe6 in position 0: unexpected end of data`
- 调用栈显示失败点在:
  - `scene/colmap_loader.py::read_extrinsics_binary`
- 同一轮回退到文本分支后又继续失败:
  - `images.txt` 不存在
- 静态阅读代码可见当前实现是:
  - 从 `images.bin` 逐个字节读取
  - 每读 1 个字节就立刻 `.decode("utf-8")`

### 假设
- 主假设:
  - `images.bin` 中的 `image_name` 是合法 UTF-8
  - 但中文字符属于多字节编码
  - 逐字节解码会把一个字符拆坏, 导致解码异常
- 备选解释:
  - 即使二进制分支修好, 文本分支 `read_extrinsics_text(...)` 也仍会因为 `line.split()` 把带空格文件名拆坏

### 静态证据
- 官方 `COLMAP read_write_model.py` 的实现是:
  - 先把 `image_name` 原始字节完整累积
  - 再统一 `decode("utf-8")`
- 当前仓库实现与官方差异在于:
  - 逐字节 decode
- 当前文本分支实现与长文件名冲突点在于:
  - `line.split()` 会把 `NAME` 内部空格拆开

### 修复
- 修改 `scene/colmap_loader.py`:
  - 新增 `read_null_terminated_utf8(fid)`
  - 改为先收集完整字节串, 再统一 `decode("utf-8")`
  - 将 `read_extrinsics_text(...)` 改为:
    - `open(..., encoding="utf-8")`
    - `line.split(maxsplit=9)`
- 新增回归测试:
  - `tests/test_colmap_loader.py`
  - 覆盖:
    - 二进制 `images.bin` 的 UTF-8 中文文件名
    - 文本 `images.txt` 的“中文 + 空格”文件名

### 验证
- 静态校验:
  - `pixi run python -m py_compile scene/colmap_loader.py tests/test_colmap_loader.py`
- 单元测试:
  - `pixi run python -m unittest tests.test_colmap_loader`
  - 结果:
    - `Ran 2 tests ... OK`
- 真实数据最小训练:
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_flashvsr_colmap_fps12_unicode_smoke --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Reading camera 180/180`
    - `Training complete.`
- 真实 wrapper 最小训练:
  - `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase train --pipeline colmap --video-fps 12 --fastgs-root /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 --model-path /workspace/FastGS/output/xhc_flashvsr_colmap_fps12_wrapper_smoke --iterations 1 -r 8 --overwrite`
  - 关键输出:
    - `Reading camera 180/180`
    - `Training complete.`

### 结论
- 当前根因已经被静态与动态证据共同支持:
  - 不是 COLMAP 重建坏了
  - 是 FastGS 侧 COLMAP 解析器不兼容 UTF-8 中文文件名
- 修复后:
  - 真实 `xhc_flashvsr_colmap_fps12` 数据可被成功读取
  - `--pipeline colmap` 路线已完成最小训练验证

## [2026-03-15 06:16:00 UTC] `xhc_bai_flashvsr_colmap_fps12` 首轮 `cudaErrorInvalidConfiguration` 排查

### 现象
- 用户真实训练命令绑定的源目录是:
  - `/workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12`
- 失败日志关键信号:
  - `Reading camera 4/4`
  - `Number of points at initialisation : 2`
  - 随后首轮 `loss.backward()` 报:
    - `torch.AcceleratorError: CUDA error: invalid configuration argument`
- 输出目录中的 `input.ply` 只有 283 字节.
- 源数据侧静态检查:
  - `images/` 里只有 4 张 undistorted 图片
  - `distorted/database.db` 里却有 `images=360`, `two_view_geometries=64620`

### 假设
- 主假设:
  - `mapper` 实际产出了多个 sparse 子模型.
  - `convert.py` 把 `image_undistorter` 的输入硬编码成 `distorted/sparse/0`.
  - 当前 `0` 正好是最差子模型, 所以训练只拿到 4 张图和 2 个点.
- 备选解释:
  - 这批素材本身就无法稳定重建.
  - 即使切到其他 sparse 子模型, 训练仍会失败.

### 静态证据
- `convert.py` 当前实现固定写死:
  - `--input_path <source_path>/distorted/sparse/0`
- 真实目录里存在 3 个 sparse 子模型:
  - `distorted/sparse/0`
  - `distorted/sparse/1`
  - `distorted/sparse/2`
- `colmap model_analyzer` 结果:
  - `sparse/0`: `Registered images=4`, `Points=2`
  - `sparse/1`: `Registered images=15`, `Points=2581`
  - `sparse/2`: `Registered images=360`, `Points=92946`

### 动态验证
- 手动让 undistorter 改走最佳模型:
  - `colmap image_undistorter --image_path /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12/input --input_path /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12/distorted/sparse/2 --output_path /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12_besttmp --output_type COLMAP`
- 再把结果整理为 FastGS 可读结构后, 执行:
  - `CUDA_LAUNCH_BLOCKING=1 pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12_bestverify -i images -m /workspace/FastGS/output/xhc_bai_bestverify_smoke --iterations 1 -r 8 --eval`
- 关键输出:
  - `Reading camera 360/360`
  - `Number of points at initialisation :  92946`
  - `Training complete.`

### 结论
- 上一条“素材本身不可训练”的备选解释已经被动态证据推翻.
- 当前根因已经被静态与动态证据共同支持:
  - 不是 CUDA kernel 自身随机出错
  - 也不是这批素材天然不能重建
  - 而是 `convert.py` 在多模型场景下固定选择 `distorted/sparse/0`, 误把最差子模型送进了训练链路
- 最合理的修复方向:
  - 在 `convert.py` 里自动选择最佳 sparse 子模型
  - 默认优先注册图像数最多者, 点数作为次排序键

## [2026-03-23 00:00:00 UTC] VerseCrafter `my4` 到 FastGS 的命令判断依据

### 现象
- `/workspace/VerseCrafter/demo_data/my4` 不是 FastGS 现成支持的 Lyra 风格目录.
- 当前真实结构是:
  - `view_id/generated_videos/generated_video_0.mp4`
  - `view_id/custom_camera_trajectory.npz`
  - `shared/estimated_depth/depth_intrinsics.npz`
- 数据检查结果:
  - 共 `0..11` 12 个视角目录
  - `custom_camera_trajectory.npz` 只有键 `extrinsics`, 形状为 `(81, 4, 4)`
  - `depth_intrinsics.npz` 里有 `intrinsic`, 形状为 `(3, 3)`

### 假设
- 主假设:
  - VerseCrafter 这批数据更适合先轻量转成 FastGS direct loader 所需格式
  - 然后走 `FlashVSR -> FastGS direct`
  - 对“最高质量”目标, 复用已知相机轨迹通常比重新跑 COLMAP 更稳
- 备选解释:
  - 如果 VerseCrafter 导出的相机矩阵语义和 FastGS 不一致
  - 或 direct loader 对这类目录仍有隐藏不兼容
  - 则应该退回 `--pipeline colmap`

### 静态证据
- FastGS direct loader 输入要求, 来自:
  - `specs/lyra_direct_loader.md`
  - `scene/dataset_readers.py`
- 其要求为:
  - `pose/*.npz`
    - `data:[T,4,4]`
    - `inds:[T]`
  - `intrinsics/*.npz`
    - `data:[T,4]`
    - `inds:[T]`
- VerseCrafter Blender 导出代码 `blender_addon/operators.py` 明确写着:
  - `cam_obj.matrix_world`
  - 注释: `camera-to-world in Blender`
  - 最终保存到 `custom_camera_trajectory.npz` 的 `extrinsics`
- 这说明 `custom_camera_trajectory.npz` 的语义接近 FastGS 所需的 `c2w`

### 推断
- 可以把 VerseCrafter 数据做一次轻量转换:
  - `generated_videos/generated_video_0.mp4` -> `rgb/generated_video_0.mp4`
  - `extrinsics` -> `pose/generated_video_0.npz`
  - 共享 `intrinsic` -> 每帧重复展开为 `[fx, fy, cx, cy]`, 写成 `intrinsics/generated_video_0.npz`
- 这样就能直接复用 FastGS 已验证过的:
  - `scripts/run_lyra_flashvsr_fastgs.sh`
  - `--pipeline direct`

### 待验证点
- 还需要做一次 `--phase superres --dry-run` 动态验证
- 目的是确认:
  - 转换后的目录能被 wrapper 正确识别
  - `scene_stem` / `view_ids` / 输出路径拼装都成立

### 动态验证
- 已用真实 `my4` 数据临时生成:
  - `/tmp/versecrafter_my4_fastgs_input`
- 该临时目录结构为:
  - `view_id/rgb/generated_video_0.mp4` -> 指向 VerseCrafter 原视频的软链接
  - `view_id/pose/generated_video_0.npz`
  - `view_id/intrinsics/generated_video_0.npz`
- 执行 dry-run:
  - `bash /workspace/FastGS/scripts/run_lyra_flashvsr_fastgs.sh --source-path /tmp/versecrafter_my4_fastgs_input --phase superres --pipeline direct --scene-stem generated_video_0 --view-ids 0,1,2,3,4,5,6,7,8,9,10,11 --flashvsr-output-root /tmp/versecrafter_my4_flashvsr --prepared-root /tmp/versecrafter_my4_prepared --model-path /tmp/versecrafter_my4_model --mode full --scale 2.0 --dtype bf16 --quality 10 --dry-run`
- 关键输出:
  - `将处理 12 个视频。`
  - 每个视角都成功映射到:
    - `/tmp/versecrafter_my4_flashvsr/full_scale2x/<view_id>/rgb/generated_video_0.mp4`
  - 汇总文件已写入:
    - `/tmp/versecrafter_my4_flashvsr/flashvsr_reference_summary.json`

### 当前结论
- 上面的备选解释暂时没有被触发.
- 目前最合适的对外建议是:
  - 先把 VerseCrafter `my4` 转成 Lyra 风格输入
  - 再走 `scripts/run_lyra_flashvsr_fastgs.sh --pipeline direct`
  - 并用:
    - `--mode full`
    - `--scale 2.0`
    - `--quality 10`
    - `-r 1`
    - `--iterations 30000`
  - 作为“优先画质”的命令口径

## [2026-03-23 00:00:00 UTC] 回滚记录: VerseCrafter `my4` 当前不应直接推荐 FastGS direct 训练

### 新现象
- 为了把前一条假设继续推进到动态证据, 执行了:
  - `CUDA_VISIBLE_DEVICES=0 pixi run python train.py -s /tmp/versecrafter_my4_fastgs_input -m /tmp/versecrafter_my4_direct_smoke --iterations 1 -r 8 --eval`
- 训练日志先成功进入:
  - `Found Lyra generated multi-view root, loading direct pose/intrinsics inputs!`
  - `Generating focus-centered point cloud (100000) for Lyra generated scene`
  - `Loading Training Cameras`
  - `Loading Test Cameras`
  - `Number of points at initialisation :  100000`
- 但随后首轮 backward 失败:
  - `torch.AcceleratorError: CUDA error: invalid configuration argument`

### 结论回滚
- 上一条“推荐 direct 路线”不成立.
- 推翻它的证据不是静态猜测, 而是最小训练动态验证.
- 当前能确认的边界是:
  - 目录转换没问题
  - `pose/intrinsics` 语义至少足以让 direct loader 成功读入
  - 但这批 VerseCrafter 数据在当前 FastGS 版本下, direct 训练还不稳定

### 目前对用户的正确建议
- 如果用户当前目标是:
  - 先把 12 个视频超分
  - 再稳定地产生一版 3DGS
- 那当前推荐应切回:
  - 先做同样的 Lyra 风格目录转换
  - 再走 `scripts/run_lyra_flashvsr_fastgs.sh --pipeline colmap`

## [2026-03-23 15:03:08 UTC] VerseCrafter wrapper 双卡与 CUDA COLMAP 验证记录

### 现象
- 用户新约束已经明确:
  - 不使用 VerseCrafter 自带相机参数
  - 要 CUDA COLMAP 自己解算
  - 想尽量利用双显卡
- 当前新脚本目标是:
  - `scripts/run_versecrafter_flashvsr_fastgs.sh`
  - 固定走 `FlashVSR -> CUDA COLMAP -> FastGS`

### 假设
- 主假设:
  - 新 wrapper 的主要风险在脚本接线与 GPU 透传
  - 只要 dry-run 和最小真实验证通过, 就能给用户稳定命令
- 备选解释:
  - 如果双卡在当前环境里并不都可见
  - 那即便 wrapper 正确, 真实运行仍会在 FlashVSR 或 COLMAP 阶段暴露环境错误

### 静态验证
- 执行:
  - `bash -n scripts/run_versecrafter_flashvsr_fastgs.sh`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m py_compile convert.py`
- 结果:
  - 三项均通过
- 新发现并已修复:
  - `scripts/run_versecrafter_flashvsr_fastgs.sh` 之前会把默认 `ffmpeg` 命令名误归一化成:
    - `/workspace/FastGS/ffmpeg`
  - 现在只有显式路径才做归一化

### dry-run 验证
- 执行:
  - `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --phase superres --dry-run --overwrite`
- 关键输出:
  - `Scene stem: generated_video_0`
  - `View ids: 0,1,10,11,2,3,4,5,6,7,8,9`
  - `Video fps: 16`
  - `启动超分分片: gpu=0 views=0,10,2,4,6,8`
  - `启动超分分片: gpu=1 views=1,11,3,5,7,9`
  - 两个 shard 都生成了各自 summary
  - 最终汇总写到:
    - `/workspace/FastGS/data/my4_generated_video_0_flashvsr_reference/flashvsr_reference_summary.json`

### 最小真实验证
- 执行:
  - `bash scripts/run_versecrafter_flashvsr_fastgs.sh --source-path /workspace/VerseCrafter/demo_data/my4 --scene-stem generated_video_0 --view-ids 0,1 --phase prepare --mode tiny --scale 2.0 --superres-gpu-ids 0,1 --colmap-gpu-index 0,1 --bridge-root /workspace/FastGS/data/my4_smoke_bridge --flashvsr-output-root /workspace/FastGS/data/my4_smoke_flashvsr --prepared-root /workspace/FastGS/data/my4_smoke_prepared --fastgs-root /workspace/FastGS/data/my4_smoke_fastgs --overwrite`
- 先观察到的事实:
  - wrapper 确实把 `gpu=0` 和 `gpu=1` 两个 shard 启动起来了
- 随后看到的失败:
  - `view=1` 那个 FlashVSR 任务日志报:
    - `[WARNING] CUDA not available, falling back to CPU`
    - `RuntimeError: No CUDA GPUs are available`

### 最小环境证据
- Lyra / FlashVSR Python:
  - `CUDA_VISIBLE_DEVICES=0 /workspace/lyra/.pixi/envs/default/bin/python3.10 -c 'import torch; ...'`
    - 输出:
      - `gpu0 True 1`
      - `NVIDIA A800-SXM4-80GB`
  - `CUDA_VISIBLE_DEVICES=1 /workspace/lyra/.pixi/envs/default/bin/python3.10 -c 'import torch; ...'`
    - 输出:
      - `gpu1 False 1`
      - `NA`
- FastGS pixi Python:
  - `CUDA_VISIBLE_DEVICES=0 pixi run python -c 'import torch; ...'`
    - 输出:
      - `fastgs_gpu0 True 1`
      - `NVIDIA A800-SXM4-80GB`
  - `CUDA_VISIBLE_DEVICES=1 pixi run python -c 'import torch; ...'`
    - 输出:
      - `fastgs_gpu1 False 1`
      - `NA`
- CUDA COLMAP:
  - 用 2 张真实图片执行:
    - `/workspace/colmap-cuda-install-3.12.6/bin/colmap feature_extractor ... --SiftExtraction.use_gpu 1 --SiftExtraction.gpu_index 1`
  - 关键输出:
    - `ERROR:   Cannot set device to 1`
    - `WARNING: Use # 0 device instead (out of 1)`

### 结论
- 上面的备选解释成立了.
- 当前不能马上“吃满双卡”的原因已经被动态证据锁定为环境可见性问题, 不是 VerseCrafter wrapper 的命令拼接问题.
- 当前仓库层面的稳定结论:
  - wrapper 已经能正确:
    - 识别 VerseCrafter 根目录
    - 自动生成 bridge root
    - 做 FlashVSR 分片
    - 透传 CUDA COLMAP 参数
  - 但当前机器实际只稳定暴露了 1 张可用 CUDA 设备给 torch / COLMAP
- 这次为避免用户再踩黑盒报错, 已新增:
  - local FlashVSR GPU 逐卡预检

## [2026-03-23 15:36:50 UTC] 为什么明明有两张卡, 但现在只能稳定用 GPU0

### 现象
- 用户质疑:
  - 机器明明有两张卡, 为什么脚本只建议用 `0`
- 先前已知现象:
  - `CUDA_VISIBLE_DEVICES=1` 下, torch 返回不可用
  - COLMAP 指定 GPU1 也无法真正用到 1 号卡

### 最小验证
- 物理 GPU 枚举:
  - `nvidia-smi -L`
  - 输出:
    - `GPU 0: NVIDIA A800-SXM4-80GB`
    - `GPU 1: NVIDIA A800-SXM4-80GB`
- 设备节点:
  - `ls -l /dev/nvidia*`
  - 输出里同时存在:
    - `/dev/nvidia0`
    - `/dev/nvidia1`
- torch 直接初始化 GPU1:
  - `CUDA_VISIBLE_DEVICES=1 /workspace/lyra/.pixi/envs/default/bin/python3.10 - <<'PY' ... torch.cuda.init()`
  - 关键输出:
    - `is_available= False`
    - `device_count= 1`
    - `RuntimeError: No CUDA GPUs are available`
- 驱动层状态:
  - `nvidia-smi -q -i 0`
    - `MIG Mode / Current : Enabled`
  - `nvidia-smi -q -i 1`
    - `MIG Mode / Current : Disabled`
- CUDA COLMAP:
  - `... colmap feature_extractor ... --SiftExtraction.gpu_index 1`
  - 关键输出:
    - `ERROR: Cannot set device to 1`
    - `WARNING: Use # 0 device instead (out of 1)`

### 已确认结论
- “只有 0 能用”不是说机器只有一张卡.
- 已确认的真实含义是:
  - 驱动能枚举到两张物理卡
  - 但当前 CUDA 应用运行时只能稳定初始化 GPU0
  - GPU1 对 torch / COLMAP 当前都不可用

### 候选根因
- 主候选假设:
  - 两张卡的 MIG 配置不一致, 当前环境不干净
  - GPU0 是 `MIG Enabled`, GPU1 是 `MIG Disabled`
  - 这是一条很可疑的异常信号
- 最强备选解释:
  - 容器 / cgroup / 运行时设备可见性映射异常
  - 虽然 `/dev/nvidia1` 节点存在, 但 CUDA runtime 仍没法真正初始化它

### 当前口径
- 现在可以确定“症状发生在哪一层”:
  - 不是 VerseCrafter wrapper
  - 不是 FlashVSR 命令拼接
  - 而是更底层的 CUDA 初始化
- 但还不能把“MIG 不一致”直接写成已确认根因

## [2026-03-23 16:15:49 UTC] VerseCrafter wrapper 收编 lyra 子脚本

### 当前目标
- 用户要求把 `scripts/run_versecrafter_flashvsr_fastgs.sh` 依赖的 lyra 子脚本迁回 FastGS.
- 背景约束是 `../lyra` 目录即将删除, 不能再让核心流程依赖外仓脚本.

### 当前假设
- 主假设:
  - VerseCrafter wrapper 并不是直接依赖整套 lyra 业务逻辑.
  - 更可能只依赖少数 shell / Python 子脚本, 以及它们约定的输入输出目录.
- 备选解释:
  - 也可能存在“脚本 A 调脚本 B, B 再调 lyra Python 模块”的隐式依赖.
  - 如果是这种情况, 迁移就不能只复制入口脚本, 还要一并收编实现文件.

### 下一步
- 先读完整个 `scripts/run_versecrafter_flashvsr_fastgs.sh`.
- 再把所有 `lyra` 路径引用和实际被调用的脚本列成清单.

## [2026-03-23 16:31:22 UTC] `run_versecrafter_flashvsr_fastgs.sh` 收编 lyra 子脚本

### 现象
- `run_versecrafter_flashvsr_fastgs.sh` 自己不直接执行 `../lyra/scripts/*.sh`.
- 真正的外仓依赖链是:
  - `run_versecrafter_flashvsr_fastgs.sh`
  - `run_lyra_flashvsr_reference.sh`
  - `../lyra/scripts/run_flashvsr_reference.py`
  - `../lyra/src/refinement_v2/flashvsr_reference.py`
- 同时还存在两个隐藏绑定:
  - 默认脚本 Python 指向 `../lyra/.pixi/envs/default/bin/python3`
  - `PYTHONPATH` 里同时挂了 `FlashVSR-Pro` 与本仓库

### 假设
- 主假设:
  - 只把 `run_flashvsr_reference.py` 搬过来还不够.
  - 还必须一起解除默认 Python 对 `lyra` 的路径绑定.
- 备选解释:
  - 如果本地模块继续放在通用名 `utils.*`, 可能会被 `FlashVSR-Pro/utils` 抢走 import.

### 最小验证
- 静态搜索:
  - `rg -n "lyra|run_lyra|flashvsr_reference" scripts/...`
  - `ast-grep` 对 `"\"$REPO_ROOT/scripts/run_lyra_flashvsr_reference.sh\""` 的搜索确认了真实调用点.
- 环境验证:
  - `pixi run python` 初始缺少 `imageio`
  - `FlashVSR-Pro/requirements.txt` 明确包含 `imageio==2.37.0`

### 第一次实现后的新现象
- 初版把模块收编成 `utils.flashvsr_reference`.
- 真实 dry-run 命令失败:
  - `ModuleNotFoundError: No module named 'einops'`
- 调用栈显示实际 import 进入了:
  - `/workspace/FlashVSR-Pro/utils/__init__.py`

### 结论
- 主假设成立, 且备选解释也被动态证据命中:
  - 不仅要搬脚本
  - 还要避免与 `FlashVSR-Pro` 的 `utils` 顶层包撞名
- 最终修正为:
  - 新增 `scripts/run_flashvsr_reference.py`
  - 新增 `scripts/flashvsr_reference_lib.py`
  - 新增 `scripts/__init__.py`
  - shell wrapper 改用 `--script-python`
  - `run_versecrafter_flashvsr_fastgs.sh` 不再要求 `../lyra` 存在
