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
