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
