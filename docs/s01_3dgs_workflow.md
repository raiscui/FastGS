# `scripts/run_s01_fastgs.sh` 使用说明

这份文档只讲一件事:

如何使用仓库里的
`scripts/run_s01_fastgs.sh`
把 `data/s01` 从多机位序列图一路跑到 FastGS 训练结果。

它不再展开手动 COLMAP 命令。
如果你当前目标就是把 `s01` 跑起来, 直接用这份脚本就够了。

---

## 1. 这个脚本会做什么

脚本默认面向当前仓库里的 `data/s01`。

它会自动完成下面 4 步:

1. 把 `C01pick` 到 `C06pick` 这些相机目录整理成 COLMAP 可读结构
2. 运行 COLMAP 的 `feature_extractor`、`exhaustive_matcher`、`mapper`、`image_undistorter`
3. 整理出 FastGS 可直接读取的数据目录
4. 调用 `train.py` 开始训练

当前默认值是:

- 原始数据目录: `data/s01`
- COLMAP 工作目录: `data/s01_colmap`
- FastGS 数据目录: `data/s01_fastgs`
- 训练输出目录: `output/s01`
- 相机模型: `SIMPLE_PINHOLE`
- 训练分辨率: `-r 2`
- 训练迭代数: `30000`
- 增点间隔: `--densification_interval 100`
- `mult`: `0.5`
- `optimizer_type`: `default`

---

## 2. 适用前提

这份脚本适合下面这种输入:

- `s01` 是静态场景
- 数据按多机位目录组织
- 每个目录里是一串图片, 不是视频文件
- 图像没有镜头畸变

当前默认假设的数据布局大致是:

```text
data/s01/
  C01pick/
  C02pick/
  C03pick/
  C04pick/
  C05pick/
  C06pick/
```

运行前还需要满足两件事:

1. `pixi` 可用
2. GPU 版 COLMAP 可执行文件存在

当前脚本默认使用:

```bash
/workspace/colmap-cuda-install-3.12.6/bin/colmap
```

如果你的路径不同, 可以用 `--colmap-bin` 覆盖。

---

## 3. 最常用的几条命令

### 3.1 直接全流程

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh
```

这会从 `data/s01` 一路跑到 `output/s01`。

### 3.2 小样本 smoke test

如果你只是想先确认链路能不能通, 推荐先跑这个:

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh \
  --overwrite \
  --frame-limit 1 \
  --iterations 10 \
  --model-path output/s01_script_smoke
```

这条命令的意思是:

- 每个相机只取 1 张图
- 训练只跑 10 iter
- 用一个独立输出目录做烟雾验证

### 3.3 只做前处理, 不训练

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh --phase prepare
```

适合你只想先把 `data/s01_fastgs` 准备好。

### 3.4 只重训, 不重跑 COLMAP

如果 `data/s01_fastgs` 已经准备好了, 只是想改训练分辨率或训练步数, 用这个:

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh \
  --phase train \
  -r 1 \
  --iterations 30000 \
  --model-path output/s01_r1
```

这条命令不会重跑 COLMAP。
它只会直接调用 `train.py`。

### 3.5 带 test 切分训练

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh --eval
```

需要 test 视角评估时再加这个参数。

### 3.6 覆盖 FastGS 高级训练参数

如果你想把 `train_base.sh` / `train_big.sh` 里的调参思路直接套到 `s01`,
现在脚本也支持这组参数了:

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh \
  --phase train \
  -r 1 \
  --densification_interval 500 \
  --highfeature_lr 0.02 \
  --grad_abs_thresh 0.0008 \
  --dense 0.01 \
  --mult 0.7 \
  --model-path output/s01_tuned
```

这些参数的详细含义, 建议直接配合这份文档一起看:

[`docs/fastgs-train-scripts.md`](/workspace/FastGS/docs/fastgs-train-scripts.md)

---

## 4. `--phase` 怎么用

脚本支持 3 个阶段模式:

- `--phase all`
  - 默认值
  - 前处理和训练都执行
- `--phase prepare`
  - 只做 COLMAP 和 FastGS 数据整理
- `--phase train`
  - 只训练
  - 要求 `FASTGS_ROOT` 已经存在

可以这样理解:

- 第一次完整跑: `all`
- 只想重新出 COLMAP: `prepare`
- 只想换 `-r` 或 `--iterations`: `train`

---

## 5. 重要参数说明

### 5.1 `-r, --resolution`

这是传给 `train.py` 的训练分辨率参数。

现在脚本已经同时支持:

```bash
-r 4
```

和:

```bash
--resolution 4
```

常见用法:

- `-r 1`
  - 原始分辨率训练
  - 更清晰
  - 更吃显存
- `-r 2`
  - 默认值
  - 一般是比较稳的起点
- `-r 4`
  - 更省显存
  - 也更快

很重要的一点:

如果你只是改 `-r`,
不需要重新跑 COLMAP。
直接用 `--phase train` 重训就可以。

### 5.2 `--iterations`

训练迭代数。

例如:

```bash
--iterations 1000
```

适合快速看结果。

```bash
--iterations 30000
```

适合正式训练。

### 5.3 `--camera-model`

当前支持:

- `SIMPLE_PINHOLE`
- `PINHOLE`

默认值是:

```bash
--camera-model SIMPLE_PINHOLE
```

这是当前 `data/s01` 上已经做过真实对照后的结论。
对这批无畸变渲染图, `SIMPLE_PINHOLE` 更稳。

如果你手动改成:

```bash
--camera-model PINHOLE
```

脚本也能跑。
但当前 `s01` 上它更容易把空间几何拉得不自然。

### 5.4 `--frame-step`

每隔多少帧取 1 张。

例如:

```bash
--frame-step 2
```

表示每个相机隔 1 张取 1 张。

这个参数只影响前处理阶段。

### 5.5 `--frame-limit`

限制每个相机最多取多少张图。

例如:

```bash
--frame-limit 8
```

表示每个相机最多取 8 张。

这个参数很适合做 smoke test。

### 5.6 `--overwrite`

允许覆盖脚本生成的旧结果。

这个参数的行为和阶段有关:

- `--phase all`
  - 会清理 `COLMAP_ROOT`
  - 会清理 `FASTGS_ROOT`
  - 训练前还会清理 `MODEL_PATH`
- `--phase prepare`
  - 会清理 `COLMAP_ROOT`
  - 会清理 `FASTGS_ROOT`
- `--phase train`
  - 只会清理 `MODEL_PATH`

如果你不想覆盖旧结果, 更推荐直接换目录名。

### 5.7 路径覆盖参数

这些参数都可以改默认目录:

- `--scene-root`
- `--colmap-root`
- `--fastgs-root`
- `--model-path`
- `--colmap-bin`
- `--pixi-bin`

这很适合做多组对照实验。

例如:

```bash
bash scripts/run_s01_fastgs.sh \
  --colmap-root data/s01_colmap_rerun \
  --fastgs-root data/s01_fastgs_rerun \
  --model-path output/s01_rerun
```

---

## 6. 常见工作流

### 6.1 第一次完整跑

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh --overwrite
```

适合你要从头重建一遍当前 `s01`。

### 6.2 已经出过 COLMAP, 只想改训练分辨率

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh \
  --phase train \
  -r 4 \
  --iterations 30000 \
  --model-path output/s01_r4
```

这时候不需要重新跑 COLMAP。

### 6.3 想重做 COLMAP, 但先不训练

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh \
  --phase prepare \
  --overwrite \
  --camera-model SIMPLE_PINHOLE
```

### 6.4 想比较不同相机模型

```bash
cd /workspace/FastGS

bash scripts/run_s01_fastgs.sh \
  --phase prepare \
  --overwrite \
  --camera-model SIMPLE_PINHOLE \
  --colmap-root data/s01_colmap_simple \
  --fastgs-root data/s01_fastgs_simple

bash scripts/run_s01_fastgs.sh \
  --phase prepare \
  --overwrite \
  --camera-model PINHOLE \
  --colmap-root data/s01_colmap_pinhole \
  --fastgs-root data/s01_fastgs_pinhole
```

这样两套结果不会互相覆盖。

---

## 7. 运行后会产出什么

### 7.1 `COLMAP_ROOT`

默认是:

```text
data/s01_colmap
```

里面会有:

- `database.db`
- `images/`
- `sparse/`
- `undistorted/`

### 7.2 `FASTGS_ROOT`

默认是:

```text
data/s01_fastgs
```

里面会有:

```text
images/
sparse/0/
```

这就是 `train.py` 直接读取的输入。

### 7.3 `MODEL_PATH`

默认是:

```text
output/s01
```

里面会有训练输出, 比如:

- `cfg_args`
- `cameras.json`
- `point_cloud/iteration_*/point_cloud.ply`

---

## 8. 常见问题

### 8.1 改 `-r` 要不要重新出 COLMAP

不要。

`-r` 只影响训练阶段。
直接用 `--phase train` 重训即可。

### 8.2 什么时候必须重新跑 COLMAP

下面这些情况建议重新跑前处理:

- 改了 `--camera-model`
- 改了 `--frame-step`
- 改了 `--frame-limit`
- 改了原始输入目录
- 你怀疑当前 COLMAP 结果本身就不对

### 8.3 脚本报“输出目录已存在”

两种处理方式:

1. 加 `--overwrite`
2. 改成新的 `--colmap-root` / `--fastgs-root` / `--model-path`

如果你是做实验对比, 更推荐第二种。

### 5.7 FastGS 高级训练参数

为了方便直接复用
[`docs/fastgs-train-scripts.md`](/workspace/FastGS/docs/fastgs-train-scripts.md)
里的调参方法,
`scripts/run_s01_fastgs.sh` 现在已经支持下面这些训练参数:

- `--densification_interval`
- `--loss_thresh`
- `--grad_thresh`
- `--grad_abs_thresh`
- `--highfeature_lr`
- `--lowfeature_lr`
- `--dense`
- `--mult`
- `--optimizer_type`

这些参数会原样传给 `train.py`。

如果你只是想知道这些参数到底会怎么影响点数、速度、细节和显存,
直接看:

[`docs/fastgs-train-scripts.md`](/workspace/FastGS/docs/fastgs-train-scripts.md)

### 8.4 训练结果看起来空间比例怪

先看你是不是手动把相机模型改成了 `PINHOLE`。

当前 `data/s01` 默认推荐:

```bash
--camera-model SIMPLE_PINHOLE
```

如果你用了 `PINHOLE`, 又看到空间被压扁或高度不自然, 先切回默认值再重跑前处理。

### 8.5 `--phase train` 报找不到 `images` 或 `sparse/0`

说明 `FASTGS_ROOT` 还没准备好。

先执行:

```bash
bash scripts/run_s01_fastgs.sh --phase prepare
```

或者直接跑:

```bash
bash scripts/run_s01_fastgs.sh
```

### 8.6 动态内容能不能直接这样训

不建议。

如果不同时间帧里的物体、姿态、灯光真的在变, 普通 3DGS 很容易重影或发糊。
这份脚本更适合静态场景, 或者“同一时刻的多机位图”。

---

## 9. 查看脚本帮助

任何时候不确定参数, 先看这个:

```bash
cd /workspace/FastGS
bash scripts/run_s01_fastgs.sh --help
```

如果你已经习惯短参数, 分辨率也可以直接写成:

```bash
bash scripts/run_s01_fastgs.sh -r 1
```

---

## 10. 一句话建议

如果你只是想稳定跑通当前 `s01`,
先用这条:

```bash
bash scripts/run_s01_fastgs.sh --overwrite
```

如果你只是想试不同训练清晰度,
不要重跑 COLMAP,
直接用:

```bash
bash scripts/run_s01_fastgs.sh --phase train -r 1 --model-path output/s01_r1
```
