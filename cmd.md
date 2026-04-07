# `nt1` COLMAP `exhaustive` 命令

更新时间: `2026-04-08 UTC`

说明:
- 这条命令对应 `/home/rais/VerseCrafter/demo_data/nt1` 的正式 `COLMAP prepare` 口径。
- 输入是 `12` 路 `generated_videos/generated_video_0.mp4`。
- 抽帧方式不是 `fps=`，而是按帧号采样:
  - `--video-frame-step 3`
- 输出命名使用交错布局:
  - `--video-naming interleaved`
- `COLMAP` matcher 使用:
  - `exhaustive`
- 使用的 CUDA 版 `COLMAP` 可执行文件:
  - `/home/rais/.local/opt/colmap-env/bin/colmap`

命令:

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --phase prepare \
  --source-path /home/rais/VerseCrafter/demo_data/nt1 \
  --fastgs-root data/nt1_step3_interleaved_exhaustive \
  --colmap-bin /home/rais/.local/opt/colmap-env/bin/colmap \
  --python-bin /root/autodl-tmp/home/rais/FastGS/.pixi/envs/default/bin/python \
  --video-frame-step 3 \
  --video-naming interleaved \
  --matcher exhaustive \
  --overwrite
```

这条命令的预期结果:
- `data/nt1_step3_interleaved_exhaustive/images = 324`
- `data/nt1_step3_interleaved_exhaustive/sparse/0` 可直接作为后续 FastGS 输入

结果校验:

```bash
find data/nt1_step3_interleaved_exhaustive/images -type f | wc -l
/home/rais/.local/opt/colmap-env/bin/colmap model_analyzer --path data/nt1_step3_interleaved_exhaustive/sparse/0
```

本次实跑结果:
- `Registered images = 324`
- `Points = 37560`
- `Mean reprojection error = 1.247355 px`

## `nt1` COLMAP `sequential` 对照命令

说明:
- 这条命令与上面的 `exhaustive` 保持相同抽帧与命名口径:
  - `--video-frame-step 3`
  - `--video-naming interleaved`
- 唯一核心差异是 matcher 改为:
  - `sequential`
- 适合做“速度优先”的 COLMAP 对照.

命令:

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --phase prepare \
  --source-path /home/rais/VerseCrafter/demo_data/nt1 \
  --fastgs-root data/nt1_step3_interleaved_sequential \
  --colmap-bin /home/rais/.local/opt/colmap-env/bin/colmap \
  --python-bin /root/autodl-tmp/home/rais/FastGS/.pixi/envs/default/bin/python \
  --video-frame-step 3 \
  --video-naming interleaved \
  --matcher sequential \
  --overwrite
```

结果校验:

```bash
find data/nt1_step3_interleaved_sequential/images -type f | wc -l
/home/rais/.local/opt/colmap-env/bin/colmap model_analyzer --path data/nt1_step3_interleaved_sequential/sparse/0
```

本次实跑结果:
- `Registered images = 324`
- `Points = 17939`
- `Mean reprojection error = 1.265856 px`

对照结论:
- `sequential` 同样实现了 `324/324` 全注册
- 但稀疏点数量明显少于 `exhaustive`
- 如果更看重 COLMAP 几何质量, 继续优先使用 `exhaustive`


# `my4` 当前命令与参数说明
worst-view 分析



更新时间: `2026-03-27 09:11:19 UTC`
会话: `019d2d07-3c10-70b0-a340-22753598e9ff`

说明:
- 我这里按“你问的是最近 `my4_mask_guarded_v4` 这组真正跑过的训练参数”来整理.
- 下面的参数,不是只看脚本默认值猜的.
- 其中“实际守护日志”来自:
  - `output/my4_mask_guarded_v4/guarded_resume_20260327.log`

先说结论:
- `my4_mask_guarded_v4` 这套输出,这次实际跑的是:
  - 已准备好的 COLMAP 数据
  - 再接 FastGS / 3DGS 训练与评估
- 也就是说:
  - `COLMAP` 不是在 `output/my4_mask_guarded_v4` 这次训练里重新解的
  - 它已经提前体现在源目录 `/home/rais/FreeFix/data/my4_fullcolmap` 里了
- 这个源目录已经存在:
  - `images/`
  - `sparse/0/`
  - `distorted/`
- 按 `scripts/run_lyra_colmap_fastgs.sh` 的逻辑, 只要 `--source-path` 已经有 `images/` 和 `sparse/0/`, 就会:
  - 跳过 `convert.py`
  - 不再重新跑 COLMAP
  - 直接进入 FastGS 训练

---

## 1. 这套输出里, COLMAP 和 FastGS 各自对应什么

### 1.1 COLMAP 部分

对 `my4_mask_guarded_v4` 这套结果来说, COLMAP 的真实状态是:

- 已经提前完成
- 产物就在:
  - `/home/rais/FreeFix/data/my4_fullcolmap`
- 这次训练不是“从原始视频重新抽帧 -> 重新做 COLMAP”
- 而是“直接复用现成 COLMAP 根目录”

所以如果你要写“这套结果的 COLMAP 命令”, 最准确的写法不是伪造一条新的重建命令, 而是写成下面这个校验入口:

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --source-path /home/rais/FreeFix/data/my4_fullcolmap \
  --phase prepare \
  --overwrite
```

这个 `prepare` 在这套数据上做的事情是:
- 检查源目录是否合法
- 识别它已经是 `images + sparse/0` 的 COLMAP / FastGS 根目录
- 跳过 `convert.py`

也就是说, 它不是重新做 COLMAP.

### 1.2 FastGS / 3DGS 部分

`my4_mask_guarded_v4` 真正对应的主体, 是下面这段:

- 读取 `/home/rais/FreeFix/data/my4_fullcolmap`
- 读取 `/home/rais/FreeFix/data/my4_fullcolmap/masks`
- 用 FastGS 训练到 `30000`
- 然后导出 `10000 / 20000 / 30000` 的 render、mp4 和指标

---

## 2. 这轮真正使用的关键参数

这轮最终跑到 `30000` 的主参数是:

- `--source-path /home/rais/FreeFix/data/my4_fullcolmap`
- `--mask-dir /home/rais/FreeFix/data/my4_fullcolmap/masks`
- `-r 1`
- `--iterations 30000`
- `--densification_interval 500`
- `--opacity_reset_interval 3000`
- `--densify_until_iter 15000`
- `--position_lr_max_steps 35000`
- `--loss_thresh 0.1`
- `--grad_thresh 0.0002`
- `--grad_abs_thresh 0.0012`
- `--highfeature_lr 0.005`
- `--lowfeature_lr 0.0025`
- `--dense 0.001`
- `--mult 0.5`
- `--optimizer_type default`
- `--eval`

---

## 3. 等价的整段训练命令

如果不考虑“分段守护 + 自动换 seed 重试”, 这轮配置可以写成下面这条等价命令:

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --source-path /home/rais/FreeFix/data/my4_fullcolmap \
  --mask-dir /home/rais/FreeFix/data/my4_fullcolmap/masks \
  --phase train \
  -r 1 \
  --iterations 30000 \
  --densification_interval 500 \
  --opacity_reset_interval 3000 \
  --densify_until_iter 15000 \
  --position_lr_max_steps 35000 \
  --loss_thresh 0.1 \
  --grad_thresh 0.0002 \
  --grad_abs_thresh 0.0012 \
  --highfeature_lr 0.005 \
  --lowfeature_lr 0.0025 \
  --dense 0.001 \
  --mult 0.5 \
  --optimizer_type default \
  --eval \
  --model-path output/my4_mask_guarded_v4 \
  --overwrite
```

注意:
- 真实执行时, 我们不是一口气从 `0 -> 30000`.
- 实际是每 `1000` 步一个 checkpoint 分段推进.
- 某一段炸了, 就换 `seed` 重新跑那一段.

---

## 4. 实际最后一段命令长什么样

`29000 -> 30000` 这一段, 日志里真实执行的是:

```bash
pixi run python train.py \
  -s /root/autodl-tmp/home/rais/FreeFix/data/my4_fullcolmap \
  -i images \
  -m /root/autodl-tmp/home/rais/FastGS/output/my4_mask_guarded_v4 \
  --iterations 30000 \
  -r 1 \
  --densification_interval 500 \
  --opacity_reset_interval 3000 \
  --densify_until_iter 15000 \
  --position_lr_max_steps 35000 \
  --loss_thresh 0.1 \
  --grad_thresh 0.0002 \
  --grad_abs_thresh 0.0012 \
  --highfeature_lr 0.005 \
  --lowfeature_lr 0.0025 \
  --dense 0.001 \
  --mult 0.5 \
  --optimizer_type default \
  --seed 51 \
  --mask_dir /root/autodl-tmp/home/rais/FreeFix/data/my4_fullcolmap/masks \
  --eval \
  --start_checkpoint /root/autodl-tmp/home/rais/FastGS/output/my4_mask_guarded_v4/checkpoints/ckpt_29000.pth \
  --save_iterations 30000 \
  --checkpoint_iterations 30000
```

这里最容易看错的一点:
- `--iterations 30000` 在 resume 场景里表示“全局目标步数到 30000”.
- 它不是“再额外跑 30000 步”.

---

## 5. 训练后导出视频和指标的命令

这轮结果最终对应的是:
- `10000`
- `20000`
- `30000`

评估和视频导出可以整理成:

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --source-path /home/rais/FreeFix/data/my4_fullcolmap \
  --phase evaluate \
  --model-path output/my4_mask_guarded_v4 \
  --video-iterations 10000,20000,30000 \
  --overwrite
```

当前结果文件:
- `output/my4_mask_guarded_v4/results.json`
- `output/my4_mask_guarded_v4/videos/train_iter10000.mp4`
- `output/my4_mask_guarded_v4/videos/train_iter20000.mp4`
- `output/my4_mask_guarded_v4/videos/train_iter30000.mp4`
- `output/my4_mask_guarded_v4/videos/test_iter10000.mp4`
- `output/my4_mask_guarded_v4/videos/test_iter20000.mp4`
- `output/my4_mask_guarded_v4/videos/test_iter30000.mp4`

---

## 6. 如果你想把它理解成“COLMAP + FastGS 跑 3DGS”, 最准确的命令顺序

对 `my4_mask_guarded_v4` 这套结果, 最准确的顺序是:

### 6.1 COLMAP 侧

这一步不是本次现跑的重建, 而是“确认现成 COLMAP 数据可用”:

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --source-path /home/rais/FreeFix/data/my4_fullcolmap \
  --phase prepare \
  --overwrite
```

### 6.2 FastGS 训练侧

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --source-path /home/rais/FreeFix/data/my4_fullcolmap \
  --mask-dir /home/rais/FreeFix/data/my4_fullcolmap/masks \
  --phase train \
  -r 1 \
  --iterations 30000 \
  --densification_interval 500 \
  --opacity_reset_interval 3000 \
  --densify_until_iter 15000 \
  --position_lr_max_steps 35000 \
  --loss_thresh 0.1 \
  --grad_thresh 0.0002 \
  --grad_abs_thresh 0.0012 \
  --highfeature_lr 0.005 \
  --lowfeature_lr 0.0025 \
  --dense 0.001 \
  --mult 0.5 \
  --optimizer_type default \
  --eval \
  --model-path output/my4_mask_guarded_v4 \
  --overwrite
```

### 6.3 评估与导视频

```bash
bash scripts/run_lyra_colmap_fastgs.sh \
  --source-path /home/rais/FreeFix/data/my4_fullcolmap \
  --phase evaluate \
  --model-path output/my4_mask_guarded_v4 \
  --video-iterations 10000,20000,30000 \
  --overwrite
```

一句话概括:
- `my4_fullcolmap` 负责“COLMAP 已完成”
- `my4_mask_guarded_v4` 负责“FastGS / 3DGS 训练输出”

---

## 7. 每个关键参数是干什么的

### `--source-path`

- 训练输入根目录.
- 这里用的是已经准备好的 COLMAP 根目录:
  - `/home/rais/FreeFix/data/my4_fullcolmap`

### `--mask-dir`

- 给每张训练图提供同名 mask.
- 这轮主要用于压掉室内空中颗粒、亮点、尘埃一类干扰.

### `-r 1`

- 表示按原始训练分辨率跑.
- 不是 `1/1` 这种数学含义, 而是脚本里的“最高这一档”.

### `--iterations 30000`

- 总目标迭代数.
- 如果是 resume, 它表示“全局终点”.
- 例如从 `ckpt_29000.pth` 接着跑到 `30000`, 这里只写 `30000`.

### `--densification_interval 500`

- 每隔多少步触发一次 densify.
- 当前代码默认值其实是 `100`.
- 这轮改成 `500`, 属于更保守、更稳一点的做法.
- 一般来说:
  - 更小: 更频繁增点, 更激进, 细节可能更强, 但更慢也更容易噪.
  - 更大: 更稳, 点数涨得更慢.

### `--opacity_reset_interval 3000`

- 每隔多少步重置一次 opacity.
- 这轮保持默认 `3000`.
- 它主要影响早中期的清理与再分配节奏.

### `--densify_until_iter 15000`

- densify 只跑到 `15000`.
- 过了这个点, 后面更像收敛和整理, 不再继续主动增点.
- 所以单纯从 `30000` 往后多跑, 收益本来就不会像前面那么大.

### `--position_lr_max_steps 35000`

- 控制 xyz 位置学习率衰减的总步长.
- 默认是 `30000`.
- 这轮拉到 `35000`, 是为了让 `30000` 附近不要太早进入“快没位置学习率”的状态.

### `--loss_thresh 0.1`

- FastGS 多视角里, 判定“高误差像素”的阈值.
- 更小: 更容易把像素判成高误差, 模型会更积极地认为需要补点.
- 更大: 更保守.

### `--grad_thresh 0.0002`

- clone 的梯度阈值.
- 这轮保持默认值.

### `--grad_abs_thresh 0.0012`

- split 的梯度阈值.
- 更小: 更容易 split, 更容易补细节, 也更容易带来噪声.
- 更大: 更保守.
- 这轮保持默认值.

### `--dense 0.001`

- clone / split 的尺寸分界.
- 它和场景尺度有关.
- 这轮保持默认值.

### `--mult 0.5`

- compact box 的拨杆.
- 训练和渲染最好保持一致.
- 按代码行为理解:
  - 更大: box 更保守, 覆盖更多 tiles, 通常更不容易漏, 但可能更慢.
  - 更小: 更激进.
- 这轮用的是默认 `0.5`.

### `--eval`

- 开启 train/test 切分.
- 不开的话, 很多时候只有 train 集, 后面就不方便标准化看 test 指标.

### `--start_checkpoint`

- 只在 resume 时用.
- 指向上一个稳定锚点, 例如:
  - `output/my4_mask_guarded_v4/checkpoints/ckpt_29000.pth`

### `--save_iterations` / `--checkpoint_iterations`

- 指定在哪些步数落盘 point cloud 和 checkpoint.
- 守护训练里, 每一段结尾都会显式写一次, 这样炸了也只回退最近 `1000` 步.

---

## 8. 当前这组参数的实际含义, 一句话版

这组参数不是“最激进追细节”.

它更像:
- 原分辨率训练
- 用 mask 先压掉空中颗粒
- densify 走保守节奏
- 在 `15000` 前完成主要结构扩张
- `15000` 后以更稳的方式收敛到 `30000`

所以它的目标偏向:
- 稳定
- 可跑完
- 控制漂浮噪声

而不是“拼命把细节炸到最多”.

---

## 9. 现在这个文件最该怎么用

如果你只是想回看“当时到底是怎么跑的”, 直接看:
- 第 3 节: 等价整段训练命令
- 第 4 节: 实际最后一段 resume 命令

如果你是想继续调参, 最值得优先盯的是:
- `--densification_interval`
- `--densify_until_iter`
- `--position_lr_max_steps`
- `--grad_abs_thresh`
- `--mult`

补一句:
- 现在训练我已经先停了.
- 因为当前更像是素材 / COLMAP 位姿可能有问题, 不一定是“参数还不够猛”.
