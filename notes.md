# 笔记: FastGS 仓库贡献指南素材

## 来源

### 来源1: `README.md`
- 要点:
  - 项目基于 PyTorch + CUDA 扩展,用 Conda 环境(`environment.yml`)搭建.
  - 常用入口: `train.py`(训练),`render.py`(渲染),`metrics.py`(指标).
  - 训练快捷脚本: `train_base.sh`、`train_big.sh`.

### 来源2: `environment.yml`
- 要点:
  - Conda env 名称: `fastgs`
  - Python 3.7.13, PyTorch 1.12.1, cudatoolkit 11.6.
  - pip 安装本地 CUDA 扩展: `submodules/diff-gaussian-rasterization_fastgs`、`submodules/simple-knn`、`submodules/fused-ssim`.

### 来源3: 仓库目录与脚本
- 要点:
  - 主要目录: `arguments/`(参数组),`gaussian_renderer/`(渲染与GUI/WS),`scene/`(数据/场景/模型封装),`utils/`(工具函数),`submodules/`(CUDA扩展源码),`assets/`(README图片).
  - 数据集目录 `datasets/` 不在仓库内,运行时按 README 约定放置.
  - 训练输出默认落在 `output/`(由脚本创建,不应提交到git).

### 来源4: `git log`
- 要点:
  - commit subject 多为简短祈使句/动词开头,例如 "Update README.md", "clean".
  - 部分提交使用方括号scope,例如 "[FastGS] Code release.".

## 综合发现

### 文档写作策略
- 只写本仓库确实存在且可执行的命令与路径.
- 测试部分说明: 当前未发现 pytest/unittest 测试目录,用 "小迭代训练 + render + metrics" 作为最小验证闭环.
- PR 要求尽量贴近研究代码贡献: 说明硬件、数据集、速度/指标变化,附复现实验命令.

---

# 笔记: pixi 环境初始化(从 environment.yml 迁移)

## 来源

### 来源1: pixi CLI 帮助
- 要点:
  - `pixi init --import environment.yml --format pixi` 支持从现有 conda `environment.yml` 导入生成 `pixi.toml`.

### 来源2: pixi 文档(Concepts: Conda + PyPI)
- 要点:
  - 可在 `pixi.toml` 中同时声明 `[dependencies]`(conda) 与 `[pypi-dependencies]`(PyPI).
  - 本地包可用 `path` + `editable = true` 的形式接入(适合本仓库 `submodules/*` 的 CUDA 扩展).

## 综合发现
- 迁移策略: 先自动导入 conda 依赖,再手动补齐 3 个本地 CUDA 扩展为可编辑 PyPI 依赖,最后生成 `pixi.lock` 保证可复现.

## 实际落地(最终方案)
- 由于 `pixi init --import environment.yml` 不能解析 pip 裸路径依赖,最终采用手写 `pixi.toml` 的方式,并以 `pixi lock` 生成 `pixi.lock`.
- conda channel 统一使用 `https://prefix.dev/conda-forge`(避免 `conda.anaconda.org` DNS 不可达).
- PyTorch 栈固定为:
  - `python=3.13.*`
  - `pytorch-gpu=2.9.1.*`
  - `torchvision=0.24.1.*`
  - `torchaudio=2.9.1.*`
  - `cuda-version=12.9.*`
- 本地 CUDA 扩展的安装方式改为 pixi task:
  - `pixi run setup` -> `pip install --no-build-isolation -e submodules/...`
  - 原因: 这些扩展在 `setup.py` 里 import torch,需要禁用 build isolation 才能在当前环境内构建.

---

# 笔记: 预训练模型是否在 ModelScope 上可用

## 结论
- 当前未在 ModelScope 找到 HuggingFace 上的 `Goodsleepeverday/fastgs` 镜像模型.
- 访问 `https://modelscope.cn/models/Goodsleepeverday/fastgs` 返回的是通用 SPA HTML,其中 `window.__detail_data__ = "null"`,与 ModelScope 已存在模型页面(会内嵌 JSON)的表现不一致,因此判断该模型未上架/不可用.

## 验证方式(可复现)
- 对比一个已存在的模型页面与目标页面:
  - 已存在模型页面示例: `https://modelscope.cn/models/damo/nlp_structbert_sentiment-classification_chinese-base` 会在 HTML 中出现很长的 `window.__detail_data__ = "{...}"`.
  - 目标页面: `https://modelscope.cn/models/Goodsleepeverday/fastgs` 的 `window.__detail_data__` 为 `null`.

---

# 笔记: train_big.sh 参数差异(与代码对照)

## 来源

### 来源1: `train_big.sh` / `train_base.sh`
- 关键差异:
  - `densification_interval`: Big 用 `100`,Base 用 `500`.
  - `grad_abs_thresh`: Big 普遍更小(更容易触发 split).
  - 部分场景设置 `mult=0.7`(例如 Tanks&Temples、Deep Blending).
  - 部分场景覆盖 `dense`/`highfeature_lr`/`lowfeature_lr`/`loss_thresh`.

### 来源2: `train.py`
- Densification 触发点:
  - `iteration > densify_from_iter` 且 `iteration % densification_interval == 0` 时,会执行 FastGS 的 densify+prune.
- 注意: 训练中间的 `training_report(...)` 调用目前被注释掉了,因此 `--test_iterations` 实际不会触发训练中评估.

### 来源3: `utils/fast_utils.py`
- 多视角一致性评分:
  - `metric_map = (l1_loss_norm > args.loss_thresh).int()` 用 `loss_thresh` 生成高误差像素图.
  - `importance_score` 是多视角 `accum_metric_counts` 的 floor-average,用于 densify 的 `metric_mask`.

### 来源4: `scene/gaussian_model.py`
- Feature 学习率如何落到参数组:
  - `features_dc` 使用 `lowfeature_lr`.
  - `features_rest` 使用 `highfeature_lr / 20.0`.
- clone/split 的核心判定(与 `dense`/梯度阈值强相关):
  - clone: `max_scaling <= dense * extent` 且 `grad >= grad_thresh`
  - split: `max_scaling > dense * extent` 且 `abs_grad >= grad_abs_thresh`
- densify 后会重置梯度统计:
  - `densification_postfix(...)` 会把 `xyz_gradient_accum`/`denom` 等重置为 0,因此 densify 越频繁,梯度统计窗口越短.

### 来源5: `diff-gaussian-rasterization_fastgs`(CUDA rasterizer)
- compact box 的 `mult` 直接参与 bbox/tiles 计算:
  - `t = mult * t; // beta in Compact Box`

## 综合发现
- `densification_interval` 与 `grad_abs_thresh`/`dense`/`loss_thresh` 是一组强耦合旋钮:
  - densify 更频繁会更快增点,也更可能在早期把噪声当细节,需要用阈值压住.
  - densify 更稀疏会更快更稳,但细节可能不够,点数也更少.
- `mult` 更像"渲染稳定性 vs 速度"拨杆:
  - 值更大 -> compact box 更保守 -> 覆盖更多 tiles -> 更慢但更不容易漏渲染/漏计数.

## 交付物
- 2026-02-26 02:17 UTC: 已将本次答疑整理为文档 `docs/fastgs-train-scripts.md`,后续如果要同步 README,可直接从该文档抽取段落.
