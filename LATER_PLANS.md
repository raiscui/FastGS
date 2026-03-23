# LATER_PLANS

## 2026-02-25
- (暂无) 如果后续发现需要补充的二期改进点,在此追加记录.

## 2026-02-25
- 预训练模型下载加速: 如果需要在国内稳定高速下载,建议把 HuggingFace 的 `Goodsleepeverday/fastgs` 权重同步发布到 ModelScope,并在 `README.md` 将链接切换到对应的 `https://modelscope.cn/models/<owner>/<model>`.

## 2026-02-26
- 参数/文档一致性:
  - `train.py` 里 `training_report(...)` 调用目前被注释,导致 `--test_iterations` 在训练过程中不生效(当前评估主要靠 `render.py` + `metrics.py`).
  - `README.md` 的部分参数默认值/描述可能与 `arguments/__init__.py` 不一致.
  - 如果需要降低使用门槛,建议择一落地:
    - 方案1: 恢复 `training_report(...)` 调用,让 `--test_iterations` 真正生效,并明确其开销与默认行为.
    - 方案2: 同步更新 `README.md`,明确训练期不做评估,并以 `train_base.sh`/`train_big.sh` 为准给出参数解释.

## [2026-03-11 06:25:10 UTC] 多机位图片目录的 `convert.py` 支持
- 当前 `convert.py` 默认 `--ImageReader.single_camera 1`,更适合单机位视频或单套图片.
- 对 `data/s01` 这种多机位目录,当前只能通过手动 COLMAP CLI 绕开.
- 后续可考虑新增一套显式多机位模式,至少覆盖:
  - `--ImageReader.single_camera_per_folder 1`
  - 可选的 `PINHOLE` / `SIMPLE_PINHOLE` 选择
  - 保留 `--colmap_executable` 的 GPU 版 COLMAP 接入方式

## [2026-03-11 08:09:36 UTC] `scripts/run_s01_fastgs.sh` 支持固定已知渲染内参
- 当前脚本已经支持 `--camera-model <SIMPLE_PINHOLE|PINHOLE>`.
- 如果后续用户能从 3ds Max 导出真实 FOV / focal / sensor 信息, 可以继续补一档更强的控制:
  - 新增 `--camera-params`
  - 或支持“固定焦距, 不在 BA 中自由漂移”的方案
- 这会比单纯在 `SIMPLE_PINHOLE` / `PINHOLE` 间切换更可控, 尤其适合 synthetic 数据.

## [2026-03-14 08:34:09 UTC] `diffusion_output_generated_my` 这类自带 `pose/intrinsics` 的目录直连 FastGS
- 当前这类目录已经自带:
  - `rgb/*.mp4`
  - `pose/*.npz`
  - `intrinsics/*.npz`
- 现有 `convert.py` 虽然能识别视频并跑 COLMAP, 但会忽略已有位姿与内参.
- 后续更正确的支持方向:
  - 方案1: 新增一个通用一键脚本, 允许用户只传路径, 自动执行 `convert.py -> train.py`
  - 方案2: 新增 direct importer, 直接把 `.npz` 转成 `transforms_train.json` / `transforms_test.json` 或 COLMAP 等价模型, 避免重复 SfM
  - 方案3: 如果确认这些轨迹是多路相机或多条已知轨迹, 再决定 train/test 切分和抽帧策略

## [2026-03-14 09:05:22 UTC] 进展更新: direct importer 已落地
- 上一条里的“方案2: 新增 direct importer”已完成.
- 当前剩余的非必需后续项只剩:
  - 如果希望把命令入口再压缩成更像“一个脚本搞定”,可以再补一个 wrapper, 自动拼接 `train.py` 常用参数.
  - 如果后续还有其他生成器要接入, 可以考虑把当前 Lyra importer 再抽成通用的“已知 pose/intrinsics 视频场景”接口.

## [2026-03-14 09:54:08 UTC] 进展更新: Lyra wrapper 已支持训练与评估
- 上一条里的“补一个 wrapper”已完成.
- 当前剩余的后续项主要变成:
  - 如果后续要降低评估成本, 可以考虑补一个“仅 PSNR/SSIM, 跳过 LPIPS”模式, 避免首次下载 VGG 权重.
  - 如果后续还有其他生成器要接入, 可以把 `run_lyra_fastgs.sh` 再抽象成通用的 direct scene runner.

## [2026-03-14 11:58:30 UTC] `run_lyra_colmap_fastgs.sh` 的快速模式与公平对比模式
- 当前脚本已经能完成传统 COLMAP 流程, 但存在两类明显不同的实验目标:
  - 快速拿结果:
    - 适合 `--video-fps 4` 这类轻量口径
  - 严格公平对比:
    - 需要和 direct 路线使用相同抽帧集合 / 相同切分
- 后续值得补两档显式模式:
  - `--preset quick-video`
  - `--preset fair-compare`
- 如果继续优化视频型 COLMAP, 可以考虑:
  - 暴露 matcher 选择
  - 增加 sequential matcher 路线
  - 或提供“先统一抽帧, 再分别 direct / COLMAP”的对比工作流

## [2026-03-14 12:28:00 UTC] 同步 `lyra` 文档中的旧 FlashVSR Python 路径
- 当前 `FastGS` 侧 wrapper 已经默认改用:
  - `/workspace/lyra/.pixi/envs/default/bin/python3`
- 但 `lyra/docs/*.md` 中仍有多处示例写着:
  - `/usr/local/miniconda3/envs/flashvsr/bin/python3`
- 这条旧路径在当前机器上已经不存在.
- 后续若要减少跨仓库踩坑, 应考虑回到 `/workspace/lyra` 同步更新这些文档.

## [2026-03-14 16:34:00 UTC] `run_lyra_flashvsr_fastgs.sh` 的 `--pipeline colmap` 全链路动态验证
- 当前串联脚本已经完成:
  - 长文件名路径解析
  - FlashVSR 真实超分
  - SR root 组织
  - direct 路线最小训练验证
- 但 `--pipeline colmap` 这条分支, 这轮只做了静态接线检查, 还没有做完整动态训练验证.
- 如果后续要把它作为稳定公开入口, 建议补一条真实验证:
  - 复用已存在的 SR 输出
  - 至少跑到 `--phase prepare`
  - 最好再补一次小迭代训练

## [2026-03-14 17:45:00 UTC] 进展更新: `--pipeline colmap` 最小训练验证已完成
- 上一条里的动态验证已完成:
  - 真实数据 `xhc_flashvsr_colmap_fps12` 已完成 1 iter smoke train
  - wrapper 入口 `run_lyra_flashvsr_fastgs.sh --phase train --pipeline colmap` 也已完成 1 iter smoke train
- 这次额外修掉了一个真实兼容性 bug:
  - `scene/colmap_loader.py` 之前无法解析 UTF-8 中文文件名
- 因此上一条待办现在可以视为已落地, 不再是未验证状态

## [2026-03-15 06:20:00 UTC] `convert.py` 的 sparse 模型手动覆盖入口
- 当前 `convert.py` 已经会自动选择“注册图像数最多, 点数次优先”的最佳 sparse 子模型.
- 如果后续出现“自动选择不符合实验需求”的场景, 可以考虑补一个显式覆盖参数:
  - `--sparse-model-id`
  - 或 `--sparse-model-path`
- 这样在研究型实验里就能同时支持:
  - 默认自动选择
  - 人工指定某个特定子模型做对照

## [2026-03-23 15:03:08 UTC] 排查当前机器的 GPU1 可见性
- 这轮 VerseCrafter wrapper 验证已经证明:
  - `CUDA_VISIBLE_DEVICES=1` 对 torch 不可用
  - `COLMAP --SiftExtraction.gpu_index 1` 也无法真正选中 GPU1
- 如果后续还要追求“超分双卡 + COLMAP 双卡”, 需要单独排查:
  - 驱动 / 容器 / 权限 / CUDA 可见性映射
  - 为什么 `nvidia-smi` 能看到 2 张卡, 但应用层只稳定可用 1 张

## [2026-03-23 16:31:22 UTC] VerseCrafter / FlashVSR 的零配置 local runner
- 这轮已经把 lyra 子脚本收编回 FastGS, 但 `FlashVSR-Pro` 真正执行 `infer.py` 的 local Python 运行时, 仍然需要独立的 FlashVSR 依赖环境.
- 当前已落地的是:
  - 本地 reference 脚本不再依赖 lyra
  - local runner 会提前明确报缺少的模块
- 后续若要做到“删掉 lyra 后, 不传任何 `--local-python` 也能直接本地超分”, 还需要二选一:
  - 方案1: 为 `FlashVSR-Pro` 单独固化一个新环境路径, 并让 wrapper 自动探测
  - 方案2: 把 `FlashVSR-Pro` 的运行依赖正式纳入 FastGS 自己的环境管理
