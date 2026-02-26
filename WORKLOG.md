# WORKLOG

## 2026-02-25
- 初始化四文件上下文,用于记录本次任务过程与交付物.
- 生成 `AGENTS.md` 贡献指南: 覆盖项目结构、Conda 环境搭建、训练/渲染/指标命令、代码风格与提交/PR 约定.
- 使用 pixi 初始化依赖环境:
  - 新增 `pixi.toml`/`pixi.lock`,并通过 `pixi run setup` 统一编译安装本地 CUDA 扩展.
  - 新增 `.gitignore` 忽略 `.pixi/`、`output/`、`datasets/` 等运行产物.
  - README 增补 pixi 安装与运行示例.
- 预训练模型镜像检查:
  - 仓库内仅在 `README.md` 有 HuggingFace 预训练模型链接.
  - 已检查 ModelScope,当前未找到 `Goodsleepeverday/fastgs` 对应模型页面,因此未替换链接.

## 2026-02-26
- 在本机执行依赖安装:
  - `pixi install --frozen` 成功(按 `pixi.lock` 复现环境).
  - `pixi run setup` 成功编译并以 editable 方式安装 3 个本地 CUDA 扩展.
  - 已用 `pixi run python` 验证 `torch` 与本地扩展 import 正常.
- 梳理 `train_big.sh`/`train_base.sh` 的训练参数:
  - 对照 `train.py`/`utils/fast_utils.py`/`scene/gaussian_model.py`/CUDA rasterizer,确认 `densification_interval`、`loss_thresh`、`grad_abs_thresh`、`dense`、`highfeature_lr`、`lowfeature_lr`、`mult`、`optimizer_type`、`test_iterations` 的真实作用与相互关系.
- 将参数说明落盘到 `docs/`:
  - 新增 `docs/fastgs-train-scripts.md`,作为 `train_base.sh`/`train_big.sh` 的参数速查与调参指南.
- 准备将当前工作区改动提交并推送到 `https://github.com/raiscui/FastGS.git`,用于对外同步.
