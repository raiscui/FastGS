## [2026-03-29 09:21:05 UTC] [Session ID: 019d38e4-25b6-7442-96f0-f2e4c43ccb82] 笔记: `my8` 漂浮棉絮伪影的仓库证据回读

## 来源

### 来源1: `task_plan__my7_my8_35000.md` 与 `WORKLOG__my7_my8_35000.md`

- `my7` 与 `my8` 已按同一套流程完成:
  - `nomask`
  - `5.333333333333 fps`
  - `35000` 训练
  - `resolution=1`
  - `eval=True`
- 这意味着:
  - `my7` 可作为同流程对照组.
  - `my8` 的异常不应直接归因于“脚本没跑对”.

### 来源2: `README.md` 与 `scripts/generate_particle_masks.py`

- `README.md` 明确写到:
  - `If your COLMAP scene has floating bright particles or indoor dust specks, you can first auto-generate per-image masks and then train FastGS with --mask-dir`
- `scripts/generate_particle_masks.py` 文件头与实现口径都明确针对:
  - `室内空中颗粒 / 尘埃 / 小亮点`
- 这说明:
  - “漂浮小亮点会被学进 3DGS” 在本仓库里是已知问题类型.
  - 仓库已经给出官方处理方向: 先做 mask, 再训练.

### 来源3: `my7` / `my8` 的产物静态对照

- `cfg_args` 对照:
  - `my7` 与 `my8` 都是 `resolution=1`, `mask_dir=''`, `eval=True`
- 点云计数:
  - `my7 input.ply`: `12167`
  - `my8 input.ply`: `20789`
  - `my7 iteration_35000/point_cloud.ply`: `35704`
  - `my8 iteration_35000/point_cloud.ply`: `52683`
- 这说明:
  - `my8` 无论在 COLMAP 初始点还是最终 Gaussian 数量上, 都明显高于 `my7`.
  - 当前至少可以确认: `my8` 确实更容易保留或长出更多空间点.

### 来源4: `my7` / `my8` 输入图的最小颗粒检测抽查

- 用 `scripts/generate_particle_masks.py` 里的同一套检测逻辑抽查了 6 个对应帧.
- 抽查结果并没有显示 `my8` 显著高于 `my7`.
- 这条证据只能说明:
  - “`my8` 一定是因为输入里有更多亮颗粒” 目前证据不足.
  - 原先把数据颗粒当成主假设, 需要降级为候选解释.

## 综合发现

### 现象
- 用户主观观察到 `my8` 有空中棉絮状漂浮.
- `my8` 与 `my7` 用的是同一套训练流程.
- `my8` 的初始稀疏点与最终 Gaussian 数量都明显更多.

### 当前主假设
- `my8` 更像“场景/位姿/重建本身更容易在空中留下可被 densify 的支撑点”, 而不只是训练脚本 bug.
- 这类问题的第一优先处理方向仍然是:
  - 先屏蔽可疑漂浮像素
  - 再必要时收紧 densify / prune 口径

### 最强备选解释
- `my8` 的某些镜头里确实有会被 3DGS 学进去的小亮点或局部反射, 只是本轮抽查样本还不足以证明它显著多于 `my7`.

### 当前还缺的证据
- 还没有对 `my8` 全量训练图跑完整的 particle mask summary.
- 还没有对 `my8` 的 COLMAP 位姿连续性与稀疏点外点做专门对照.

### 当前结论
- 现在最稳的口径不是“直接继续硬调训练超参”.
- 优先顺序应当是:
  1. 先用现成 `particle mask` 流程验证并屏蔽可疑漂浮像素.
  2. 若仍有漂浮, 再回到 COLMAP / 训练超参做第二轮收紧.

## [2026-03-29 09:29:40 UTC] [Session ID: 019d38e4-25b6-7442-96f0-f2e4c43ccb82] 笔记: `my8` 的 particle mask v1 落地结果与对照

## 来源

### 来源1: `generate_particle_masks.py` 全量运行

- 已成功生成:
  - `data/my8_colmap_fastgs/masks_particle_v1`
  - `data/my8_colmap_fastgs/mask_debug_particle_v1`
  - `data/my8_colmap_fastgs/mask_summary_particle_v1.json`
- summary 结果:
  - `image_count = 324`
  - `total_masked_pixels = 63971`
  - `average_mask_ratio = 0.0002142375846622085`
  - `max_mask_ratio = 0.0007443576388888889`
- 这说明这版 mask 很保守.

### 来源2: 带 mask 冒烟训练

- `output/my8_mask_particle_smoke` 已成功完成 `100` 轮.
- 动态证据:
  - 明确打印 `Using mask directory`
  - `324` 张相机正常读入
  - 没有缺 mask / 尺寸不匹配问题

### 来源3: `my8_mask_particle_v1` guarded 训练

- 完整直跑在约 `21320` 左右触发 CUDA 错误.
- 改为 `1000` 步一段 guarded 训练后, 已成功完成到 `35000`.
- 动态证据:
  - `12000->13000` 在 `seed=0` 失败, `seed=1` 成功
  - `33000->34000` 在 `seed=0` 失败, `seed=1` 成功
  - 最终日志输出: `[guard-my8-mask] completed through 35000`
- 这说明:
  - 带 mask 版在这台机器上同样需要 guarded 策略
  - 但 guarded 策略确实能把它稳定交付到终点

### 来源4: 最终产物与无 mask 对照

- 带 mask 版最终产物:
  - `ckpt_35000.pth` = `40324469` bytes
  - `point_cloud.ply` = `13811162` bytes
  - `train_iter35000.mp4` = `6498006` bytes
  - `test_iter35000.mp4` = `1380710` bytes
- 顶点数对照:
  - `my8_nomask_v1`: `52683`
  - `my8_mask_particle_v1`: `55684`
- 粗粒度图像差异统计(基于 test 集 mean absolute diff):
  - `my8_nomask_v1`: `avg = 7.6374564472532755`, `max = 16.241316189236112`
  - `my8_mask_particle_v1`: `avg = 7.801363923469964`, `max = 15.571675708912037`
- 标准指标对照:
  - `my8_nomask_v1`:
    - `SSIM = 0.8846099`
    - `PSNR = 25.6491432`
    - `LPIPS = 0.2307853`
  - `my8_mask_particle_v1`:
    - `SSIM = 0.8832615`
    - `PSNR = 25.3352108`
    - `LPIPS = 0.2330082`

## 综合发现

### 现象
- particle mask v1 路线已经真实跑通并交付了完整 `35000` 版本.
- 但从当前这一版的粗指标与标准指标看, 并没有出现整体质量提升.
- 同时最终 Gaussian 数量反而略多.

### 当前结论
- 当前可以确认的是:
  - `particle mask v1 + guarded` 是可执行方案
  - 但它还不能被表述成“已经解决了 `my8` 漂浮问题”
- 更准确的口径应是:
  - 这版 mask 属于一次保守尝试
  - 已经验证了训练链与交付链
  - 但效果层面还需要进一步调参或转向位姿/外点分析

### 下一步更值得做的方向
- 方向1: 把 `particle mask` 做得更有针对性, 例如:
  - 提高 `dilation_radius`
  - 放宽亮点连通域面积上限
  - 结合具体漂浮区域定制阈值
- 方向2: 回到 COLMAP / 稀疏点云分析:
  - 检查 `my8` 空中外点
  - 检查漂浮主要出现在哪些视角与时间段
  - 判断更像重建外点, 还是训练中被保留下来的半透明反射

## [2026-03-29 09:57:05 UTC] [Session ID: c1ad2430-46ff-4852-89ec-356e70f96f49] 笔记: 用户删图后的 `my8` 当前数据状态与重跑入口判断

## 来源

### 来源1: 当前目录计数

- `data/my8_colmap_fastgs/input = 277`
- `data/my8_colmap_fastgs/images = 324`
- `data/my8_colmap_fastgs/sparse/0 = 6`
- 视角分布:
  - `001..004, 007..012` 各 `27` 张
  - `005` 只剩 `7` 张
  - `006` 已经完全不存在

### 来源2: `convert.py`

- `prepare_input_directory()` 在 `video_source is None` 时, 会直接把 `<source_path>/input` 当作图片模式入口.
- 随后 `feature_extractor -> exhaustive_matcher -> mapper -> image_undistorter` 都会基于这套 `input` 运行.
- 这说明当前并不需要回到视频抽帧流程, 直接对新的图片目录重跑 COLMAP 即可.

### 来源3: `scripts/run_lyra_colmap_fastgs.sh`

- 这层 wrapper 对“已准备好的数据根”识别没问题.
- 但它的 `prepare_dataset()` 默认是“原始视频源 -> convert.py --video_path ...”语义.
- 对这次“只有图片 input, 没有原始视频”的场景, 更稳的做法是:
  - 先手工调用 `convert.py`
  - 再用 wrapper 的 `train/render` 阶段接上训练和导出

## 综合发现

### 现象
- 用户已经改了原始输入, 但旧 prepared dataset 还停留在删图前状态.
- 继续沿用旧 `images + sparse/0` 训练, 会得到错误的对照结果.

### 当前主假设
- 这次最关键的第一步不是训练, 而是先把新的 `input` 变成一套新的 prepared dataset.

### 最强备选解释
- 如果新的 COLMAP 注册明显变差, 也可能导致结果比旧版更差.
- 所以本轮应该把目标定义成“得到一版真实对应 pruned input 的 nomask 结果”, 而不是预设它一定更好.

### 当前结论
- 本轮执行口径已经确定:
  1. 新建 pruned 数据根, 保留旧数据根用于对照
  2. 直接用图片模式重跑 COLMAP
  3. 再复用已验证的 guarded `1000` 步分段 nomask 训练链

## [2026-03-29 11:03:20 UTC] [Session ID: c1ad2430-46ff-4852-89ec-356e70f96f49] 笔记: 删图后的 `my8` pruned COLMAP 已完成重建

## 来源

### 来源1: `convert.py` 真实动态输出

- `feature_extractor` 完成 `277/277`.
- `exhaustive_matcher` 真实跑完整个 `6x6` block 网格.
- `mapper` 最终出现:
  - `Keeping successful reconstruction`
  - `registered_images=277`
  - `points=8515`
- `image_undistorter` 随后跑到 `Undistorting image [277/277]` 并输出 `Done.`.

### 来源2: 新数据根落盘核对

- `data/my8_colmap_fastgs_input_pruned_v1/input = 277`
- `data/my8_colmap_fastgs_input_pruned_v1/images = 277`
- `data/my8_colmap_fastgs_input_pruned_v1/sparse/0 = 5`
- `sparse/0` 统计:
  - `cameras = 1`
  - `registered_images = 277`
  - `points = 8515`

### 来源3: 与旧版 `my8` prepared dataset 的静态对照

- 旧版 `my8 input.ply` 点数是 `20789`.
- 这次删图后重建出来的新 sparse points 是 `8515`.
- 这说明删掉 `006` 全组和 `005` 一部分之后, 初始稀疏点规模已经明显收缩.

## 综合发现

### 现象
- 新的 pruned 数据根已经真实生成完成, 而且 `277` 张图全部注册成功.
- 稀疏点规模相比旧版显著下降.

### 当前主假设
- 这版 pruned nomask 训练很可能会学出一套明显不同于旧 `my8_nomask_v1` 的几何基础.
- 但是否会减少“空中棉絮漂浮”, 仍需等训练与渲染证据.

### 最强备选解释
- 即便初始 sparse points 变少, 后续训练仍可能因为剩余视角的不稳定区域继续 densify 出漂浮物.

### 当前结论
- 现在已经具备进入正式 nomask 训练的全部前提.
- 下一步直接复用项目里已验证的 guarded `1000` 步分段训练链, 跑到 `35000`.

## [2026-03-29 11:11:55 UTC] [Session ID: c1ad2430-46ff-4852-89ec-356e70f96f49] 笔记: pruned nomask `35000` 训练、渲染与旧版对照结果

## 来源

### 来源1: 新版最终产物核对

- 已成功生成:
  - `output/my8_nomask_input_pruned_v1/checkpoints/ckpt_35000.pth`
  - `output/my8_nomask_input_pruned_v1/point_cloud/iteration_35000/point_cloud.ply`
  - `output/my8_nomask_input_pruned_v1/videos/train_iter35000.mp4`
  - `output/my8_nomask_input_pruned_v1/videos/test_iter35000.mp4`
- 文件大小:
  - `ckpt_35000.pth = 19716533`
  - `point_cloud.ply = 6752090`
  - `train_iter35000.mp4 = 4137700`
  - `test_iter35000.mp4 = 805539`

### 来源2: 几何规模对照

- 旧版 `my8_nomask_v1`:
  - `input sparse points = 20789`
  - `iteration_35000 point count = 52683`
- 新版 `my8_nomask_input_pruned_v1`:
  - `input sparse points = 8515`
  - `iteration_35000 point count = 27220`
- 这说明:
  - 删掉 `006` 全组和 `005` 一部分之后, 初始几何和最终高斯数量都显著下降.

### 来源3: 标准指标对照

- 旧版 `output/my8_nomask_v1/results.json`:
  - `SSIM = 0.8846098780632019`
  - `PSNR = 25.64914321899414`
  - `LPIPS = 0.2307853251695633`
- 新版 `output/my8_nomask_input_pruned_v1/results.json`:
  - `SSIM = 0.8324441313743591`
  - `PSNR = 20.68596076965332`
  - `LPIPS = 0.34029364585876465`

## 综合发现

### 现象
- pruned 版已经完整交付成功.
- 几何规模明显更小.
- 但标准指标整体明显差于旧版.

### 当前主假设
- 当前更像是: 这次删图确实削掉了大量几何支撑点和最终高斯, 但也伤到了原本对重建质量有价值的视角覆盖.

### 最强备选解释
- 也可能不是“删得太多”, 而是 `005` / `006` 之外剩余视角的覆盖关系本来就不足, 所以在删掉关键视角后质量明显下滑.

### 当前结论
- 本轮可以确认的不是“删图后效果更好”.
- 更准确的结论是:
  - 这版 `277` 图 pruned nomask 已经真实重建并训练完成
  - 它会显著收缩点数与高斯数
  - 但从指标看, 当前质量明显差于旧 `324` 图版本
