# FastGS: train_base.sh / train_big.sh 参数速查与调参指南

这份文档专门解释本仓库的两个训练脚本:
- `train_base.sh`: 速度与质量的平衡版本.
- `train_big.sh`: 更偏质量,训练会更慢一些.

重点只覆盖脚本里真的在用的参数,并且以代码实现为准,避免只看参数名"猜意思".

---

## 1. 一句话结论: 为什么每个场景的参数都不同?

因为 FastGS 的核心旋钮里,有一部分是"场景尺度相关"的,还有一部分是"纹理复杂度/噪声相关"的.

同一套固定超参,在某些场景上会出现这两类问题:
- 过于保守: 点数增长不够,细节出不来,画面偏糊.
- 过于激进: 很早就开始大量 densify/split,把噪声当细节,速度慢,显存压力大,还可能出现更多伪细节.

脚本按场景单独调参,本质是在做"质量/速度/显存"的局部最优折中.

---

## 2. 脚本在做的训练闭环是什么?

两份脚本都是三段式:

1) `train.py` 训练,输出到 `output/<run_name>/`.
2) `render.py` 渲染 test/train 视角,写回同一个 `output/<run_name>/`.
3) `metrics.py` 计算 PSNR/SSIM/LPIPS.

你可以把它理解成:

`train.py` -> `output/<run>/` -> `render.py` -> `output/<run>/` -> `metrics.py`

注意: 训练过程中"边训边测"的逻辑目前没开启,见本文第 7 节.

---

## 3. `OAR_JOB_ID` 是干什么的?

它不是训练超参.

脚本里写 `OAR_JOB_ID=bicycle_big` 的作用,是把输出目录名字固定下来.

`train.py` 里是这样决定输出目录的(原文摘录):

```python
if os.getenv('OAR_JOB_ID'):
    unique_str=os.getenv('OAR_JOB_ID')
...
args.model_path = os.path.join("./output/", unique_str)
```

也就是说:
- 你不传 `-m/--model_path` 时,会默认输出到 `./output/<OAR_JOB_ID>/`.
- 这能保证脚本后半段的 `render.py -m output/<name>` 找得到对应训练结果.

---

## 4. Base vs Big 的关键差异

脚本层最核心的差异是 densify 的频率:
- `train_base.sh` 大多用 `--densification_interval 500`
- `train_big.sh` 统一用 `--densification_interval 100`

直觉上:
- interval 更小 -> 更频繁 densify+prune -> 更容易补细节 -> 更慢.
- interval 更大 -> densify 更少 -> 更快更稳 -> 细节可能不够.

此外,`train_big.sh` 往往把 `--grad_abs_thresh` 调得更小.
这会让 split 更容易发生,用来进一步补细节.

---

## 5. 关键参数怎么影响训练? (按"作用域"分组)

下面每个参数都给出:
- 它在代码里的真实生效点.
- 值变大/变小的直观影响.

### 5.1 Densify/Prune 相关(最强耦合的一组)

#### 5.1.1 `--densification_interval`

生效点在 `train.py` 的训练循环里(原文摘录):

```python
if iteration > opt.densify_from_iter and iteration % opt.densification_interval == 0:
    ...
    importance_score, pruning_score = compute_gaussian_score_fastgs(..., DENSIFY=True)
    gaussians.densify_and_prune_fastgs(..., args=opt, ...)
```

重要细节:
- 每次 densify 后,梯度统计会被清零重算,见 `scene/gaussian_model.py` 的 `densification_postfix(...)`.
  这意味着 interval 越小,梯度统计窗口越短,模型更"短视",也更容易激进.

调参直觉:
- 画面糊,细节不够: 降低 `densification_interval`(更频繁 densify).
- 训练太慢,点数暴涨: 提高 `densification_interval`.

#### 5.1.2 `--loss_thresh`

它用于生成"高误差像素"的二值图,来自 `utils/fast_utils.py`(原文摘录):

```python
metric_map = (l1_loss_norm > args.loss_thresh).int()
```

直觉:
- `loss_thresh` 越小,越多像素会被判为"高误差".
- 这会让多视角统计更容易把某些 Gaussians 标成"应该 densify 的候选".

一般经验:
- 如果你发现模型总是"很吝啬",不怎么增点,可以适当降低 `loss_thresh`.
- 如果你发现模型"太贪婪",早期就疯狂增点,可以提高 `loss_thresh`.

#### 5.1.3 `--grad_thresh` 和 `--grad_abs_thresh`

这两个决定了 clone 与 split 的梯度门槛.

在 `scene/gaussian_model.py` 的 densify 逻辑里(原文摘录):

```python
grad_qualifiers = torch.where(torch.norm(grad_vars, dim=-1) >= args.grad_thresh, True, False)
grad_qualifiers_abs = torch.where(torch.norm(grads_abs, dim=-1) >= args.grad_abs_thresh, True, False)
```

直觉:
- `grad_thresh` 越小,越容易触发 clone.
- `grad_abs_thresh` 越小,越容易触发 split.

脚本里 Big 模式经常把 `grad_abs_thresh` 调小,就是为了让 split 更积极,细节更丰富.

#### 5.1.4 `--dense`(强烈的"场景尺度相关"参数)

它决定某个 Gaussian 该走 clone 还是 split 的"尺寸分界".

在 `scene/gaussian_model.py`(原文摘录):

```python
clone_qualifiers = torch.max(self.get_scaling, dim=1).values <= args.dense*extent
split_qualifiers = torch.max(self.get_scaling, dim=1).values > args.dense*extent
```

这里的 `extent` 是场景尺度,来自 `Scene.cameras_extent`.

所以 `dense` 本质是在说:
- "以场景半径为 1 的单位",多大的点算"大点".

直觉:
- `dense` 越小,更多点会被归类为"大点"(更容易 split),训练更激进.
- `dense` 越大,更多点会走 clone,整体更保守.

### 5.2 SH 特征学习率(主要影响颜色/高频细节拟合速度)

#### 5.2.1 `--lowfeature_lr`

它用于 `features_dc`(低阶 SH/基色)的学习率,在 `scene/gaussian_model.py` 的参数组里:

```python
{'params': [self._features_dc], 'lr': training_args.lowfeature_lr, "name": "f_dc"},
```

#### 5.2.2 `--highfeature_lr`

它用于 `features_rest`(高阶 SH 系数)的学习率,但注意这里被除以了 20(原文摘录):

```python
sh_l = [{'params': [self._features_rest], 'lr': training_args.highfeature_lr / 20.0, "name": "f_rest"}]
```

这点很容易被忽略:
- 你在命令行里填的 `highfeature_lr`,实际落到优化器里的 lr 是 `highfeature_lr / 20`.

直觉:
- 提高特征学习率通常会更快拟合细节与颜色,但也更容易引入噪声与过拟合.
- 不同数据集/场景的纹理复杂度差别很大,所以脚本按场景调整这两个值是合理的.

### 5.3 `--mult`: compact box 的渲染/速度拨杆

这个参数会传入 CUDA rasterizer,用于 compact box 的 bbox/tiles 计算.

在 `submodules/diff-gaussian-rasterization_fastgs/cuda_rasterizer/auxiliary.h` 里有一行非常关键(原文摘录):

```cpp
t = mult * t; // beta in Compact Box
```

直觉(以代码行为推导):
- `mult` 越大,compact box 更保守,可能覆盖更多 tiles.
- 通常更不容易漏渲染/漏计数,但会更慢.

脚本里 Tanks&Temples 和 Deep Blending 统一用了 `--mult 0.7`.
并且渲染时也传了同样的 `--mult 0.7`.

重要建议:
- 训练用的 `mult` 和 `render.py` 用的 `mult`,尽量保持一致.
  否则你可能得到"训练时的分布"和"评估时的分布"不一致的结果.

### 5.4 `--optimizer_type`

这是优化器分支开关,在 `train.py` 里:
- `default`: 走 `gaussians.optimizer_step(iteration)`(本仓库的主路径).
- `sparse_adam`: 走 `SparseGaussianAdam`.

脚本里目前全是 `--optimizer_type default`.

### 5.5 `--eval`

它影响数据集 train/test 切分.

以 COLMAP 场景为例,`scene/dataset_readers.py` 的逻辑是:
- `eval=True` 时,按 LLFF hold-out 的方式切分,每隔 `llffhold` 张取一张做 test.
- `eval=False` 时,test 集为空.

---

## 6. 给新数据集的调参顺序(推荐)

如果你要跑一个"脚本里没有的场景",建议按下面顺序改.
这样每一步的影响相对可控,不会一下子把系统推到不可解释的状态.

1) 先选一个最接近的数据域脚本行当起点
- 类似 MipNeRF360: 从 `train_base.sh` 的某个 MipNeRF360 场景行拷贝.
- 类似 Tanks&Temples/DB: 从对应段落拷贝,并先保留 `--mult 0.7`.

2) 先用 `densification_interval` 控制速度与点数
- 太慢,点数爆炸: 把 interval 往上调.
- 太糊,细节不够: 把 interval 往下调.

3) 再用 `grad_abs_thresh`/`loss_thresh` 做细节与噪声的二次平衡
- 细节不够: 适当降低 `grad_abs_thresh`,或降低 `loss_thresh`.
- 噪声多,伪细节: 提高 `grad_abs_thresh`,或提高 `loss_thresh`.

4) 最后才动 `dense`
- 这是强场景尺度相关参数.
- 只有当你确认"clone/split 的比例明显不对"时,再去调它.

---

## 7. 一个容易踩的坑: `--test_iterations` 目前基本无效

`train.py` 里本来有 `training_report(...)` 用于在训练中做 test-set 评估.

但当前训练循环里这行调用被注释掉了:
- `train.py` 里能看到类似 `# training_report(...)` 的注释调用.

所以脚本里写 `--test_iterations 30000` 的效果是:
- 参数被解析了.
- 但训练中不会触发评估输出.

目前这套仓库的主评估路径是:
- 训练结束后跑 `render.py`
- 再跑 `metrics.py`

如果你希望"训练中间也能看到 test 指标",需要恢复 `training_report(...)` 的调用,并接受它带来的额外开销.
