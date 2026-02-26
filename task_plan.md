# 任务计划: 生成仓库贡献指南(AGENTS.md)

## 目标
- 生成 `AGENTS.md` 作为本仓库贡献指南,内容覆盖目录结构、常用命令、代码风格、测试方式、提交与PR规范.
- 文档需简洁(约200-400词),标题固定为 "Repository Guidelines",并使用清晰的Markdown结构.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 研究/收集信息
- [ ] 阶段3: 执行/构建
- [ ] 阶段4: 审查和交付

## 关键问题
1. 仓库的核心入口脚本与主要模块目录是什么?
2. 本仓库的环境配置、构建/运行/评估命令有哪些,哪些适合本地快速验证?
3. 是否存在单元测试或CI? 若没有,应如何做最小可行的回归验证?
4. git 历史里 commit message 的惯例是什么,需要在指南中如何约束?

## 做出的决定
- [决定] 基于真实仓库内容生成: 优先读取 `README.md`、`environment.yml`、常用脚本(`train_base.sh`/`train_big.sh`)以及 `git log`,避免写出与仓库不符的说明.

## 状态
**目前在阶段1**
- 2026-02-25 14:57 UTC: 初始化任务,开始扫描仓库结构与常用命令.

## 进度更新

**目前在阶段4**
- 2026-02-25 15:00 UTC: 已完成仓库结构/命令/风格/提交习惯梳理,并生成 `AGENTS.md`(约307词) 作为贡献指南交付.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 研究/收集信息
- [x] 阶段3: 执行/构建
- [x] 阶段4: 审查和交付

---

# 任务计划: 检查预训练模型在 ModelScope 是否有镜像

## 目标
- 确认仓库是否存在 "从 HuggingFace 下载预训练模型" 的逻辑或链接.
- 在 `https://modelscope.cn/models` 检索是否存在对应模型.
- 若存在可用镜像,将链接/下载入口从 HuggingFace 替换为 ModelScope,以提升国内下载速度.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 研究/收集信息
- [ ] 阶段3: 执行/构建
- [ ] 阶段4: 审查和交付

## 关键问题
1. 仓库里是否有自动下载权重的代码(例如 huggingface_hub / snapshot_download)?
2. ModelScope 上是否存在同名或等价的模型仓库?
3. 若不存在,是否需要创建/同步一个 ModelScope 仓库作为镜像?

## 状态
**目前在阶段4**
- 2026-02-25 16:35 UTC: 已扫描仓库,仅发现 `README.md` 的 HuggingFace 预训练模型链接,未发现自动下载代码.
- 2026-02-25 16:35 UTC: 已在 ModelScope 验证 `Goodsleepeverday/fastgs` 等可能路径,页面 `window.__detail_data__ = \"null\"`,判断模型未上架/不可用,因此本次不做链接替换.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 研究/收集信息
- [x] 阶段3: 执行/构建
- [x] 阶段4: 审查和交付

---

# 任务计划: 使用 pixi 初始化依赖环境

## 目标
- 用 pixi 接管并复现 `environment.yml` 的依赖环境,在仓库根目录生成 `pixi.toml`(以及必要时的 `pixi.lock`).
- 让新贡献者可以用一组稳定命令完成: 创建环境 -> 编译本地 CUDA 扩展 -> 运行训练/渲染/指标脚本.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 研究/收集信息
- [ ] 阶段3: 执行/构建
- [ ] 阶段4: 审查和交付

## 关键问题
1. pixi 能否直接从 `environment.yml` 导入生成 `pixi.toml`,并保留 channels 与版本 pin?
2. `submodules/` 下 3 个 CUDA 扩展应如何声明为 pixi 的 PyPI 本地可编辑依赖(编译时机/可复现性)?
3. 是否需要提交 `pixi.lock` 来锁定解析结果? 是否需要补 `.gitignore` 忽略 `.pixi/` 与训练输出?
4. README/贡献指南里,应该如何给出最小可用的 pixi 命令闭环?

## 做出的决定
- [决定] 优先用 `pixi init --import environment.yml` 自动生成 manifest,减少手写toml带来的语法/语义偏差.
- [决定] 3 个本地 CUDA 扩展用 `[pypi-dependencies]` 的 `path + editable=true` 方式接入,确保开发迭代时改动可即时生效.

## 状态
**目前在阶段1**
- 2026-02-25 15:02 UTC: 开始将 Conda 环境迁移为 pixi,计划先导入 `environment.yml` 再补齐本地扩展依赖与锁文件.

## 进度更新

**目前在阶段4**
- 2026-02-25 16:30 UTC: 已落地 `pixi.toml`/`pixi.lock`,并补充 `.gitignore` 与 README/贡献指南中的 pixi 用法说明.
- 关键踩坑与处理:
  - `pixi init --import environment.yml` 因 pip 依赖为裸路径(`submodules/...`)解析失败,最终改为手写/补齐 `pixi.toml`.
  - 由于网络/DNS 限制无法访问 `conda.anaconda.org`,最终统一使用 `https://prefix.dev/conda-forge` 作为 conda channel.
  - 本仓库 3 个本地 CUDA 扩展(`diff_gaussian_rasterization_fastgs`/`simple_knn`/`fused_ssim`)在 `setup.py` 中依赖 `torch`:
    - `pip install -e` 默认 build isolation 会导致构建环境缺少 torch,已在 `pixi run setup` 中加入 `--no-build-isolation`.
    - `simple_knn` 缺少 `__init__.py` 会导致 editable import 失败,已补 `submodules/simple-knn/simple_knn/__init__.py`.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 研究/收集信息
- [x] 阶段3: 执行/构建
- [x] 阶段4: 审查和交付

---

# 任务计划: 执行 pixi install 安装依赖(本机)

## 目标
- 在当前仓库目录基于 `pixi.lock` 安装/更新依赖环境,确保 `pixi` 环境可用.
- (可选) 若本机具备 CUDA 编译工具链,再执行 `pixi run setup` 安装本地 CUDA 扩展.

## 阶段
- [x] 阶段1: 计划和设置
- [x] 阶段2: 安装依赖
- [x] 阶段3: 编译本地扩展(可选)
- [x] 阶段4: 验证与交付

## 关键问题
1. `pixi install --frozen` 是否能在本机成功解析并安装?
2. 本机是否具备 `nvcc`/编译器,能否执行 `pixi run setup`?

## 状态
**目前在阶段4**
- 2026-02-26 00:31 UTC: 收到请求,准备先执行 `pixi install --frozen` 以确保依赖环境按锁文件可复现地安装.
- 2026-02-26 00:32 UTC: 开始执行 `pixi install --frozen`.
- 2026-02-26 00:32 UTC: `pixi install --frozen` 已成功完成,准备执行 `pixi run setup` 编译并安装本仓库的本地 CUDA 扩展.
- 2026-02-26 00:39 UTC: `pixi run setup` 已成功完成,3 个本地 CUDA 扩展已编译并以 editable 方式安装.
- 2026-02-26 00:39 UTC: 已验证 `pixi run python` 下 `torch` 与 3 个本地扩展(import)均正常.

---

# 任务计划: 解释 train_big.sh 参数差异与作用

## 目标
- 解释 `train_big.sh`/`train_base.sh` 中出现的 FastGS 训练参数,以及它们在代码里真实影响的逻辑.
- 说明为什么不同数据集/场景会需要不同参数,并给出可复用的调参思路(速度/质量/显存的权衡).

## 两种方向(供选择)
- 方案A(不惜代价,最佳): 把参数解释整理成"速查表 + 调参流程"落盘到 README 或 docs,并对 README 中与代码不一致的默认值做一次同步.
- 方案B(先能用,后面再优雅): 先在对话中把参数作用讲清楚,并在 `notes.md` 记录关键对照点,后续再决定是否做文档同步.

## 阶段
- [x] 阶段1: 计划和设置
- [x] 阶段2: 研究/收集信息
- [ ] 阶段3: 输出解释与建议
- [ ] 阶段4: 记录与交付

## 关键问题
1. `train_big.sh` 里每个参数在代码的哪个位置生效?
2. 哪些参数主要影响"点数增长/显存/速度",哪些主要影响"画质/细节"?
3. 为什么同一套参数不适合所有数据集/场景? 哪些量是场景尺度相关的?

## 做出的决定
- [决定] 先按方案B交付: 以代码为准解释参数与调参方向,并把对照点写入 `notes.md`.
- [决定] 把"README 默认值与代码不一致"作为后续可选改进,先记入 `LATER_PLANS.md`,避免本次答疑被打断.

## 状态
**目前在阶段3**
- 2026-02-26 02:08 UTC: 已对照 `train_big.sh`/`train_base.sh` 与 `train.py`/`utils/fast_utils.py`/`scene/gaussian_model.py`/CUDA rasterizer,确认参数的真实用途与相互关系,准备输出解释与调参建议.

## 进度更新

**目前在阶段4**
- 2026-02-26 02:11 UTC: 已完成参数作用解释与调参建议输出,并将关键对照点追加记录到 `notes.md`/`WORKLOG.md`,同时把文档一致性改进点记入 `LATER_PLANS.md`.

- [x] 阶段3: 输出解释与建议
- [x] 阶段4: 记录与交付

---

# 任务计划: 将 train_big.sh 参数总结到 docs

## 目标
- 把 `train_big.sh`/`train_base.sh` 里用到的参数,以及它们在代码中的真实生效位置,整理成一份可长期复用的文档,放入 `docs/`.
- 文档目标读者: 需要改数据集/改参数的贡献者,以及需要理解作者为什么"每个场景参数不同"的使用者.

## 两种方向(供选择)
- 方案A(不惜代价,最佳): 形成 `docs/` 文档后,同步改造 `README.md` 的参数说明段落,保证默认值与代码一致,并补充对 `train_base.sh`/`train_big.sh` 的差异解释.
- 方案B(先能用,后面再优雅): 仅新增 `docs/` 文档,不改动 `README.md`,避免影响面扩大.

## 阶段
- [x] 阶段1: 计划和设置
- [x] 阶段2: 收集与对照(代码为准)
- [x] 阶段3: 编写 docs 文档
- [x] 阶段4: 回填四文件上下文

## 关键问题
1. 文档要覆盖哪些"脚本层参数",才能让新手不再靠猜?
2. 哪些参数强耦合,必须放在一起解释(例如 densify 相关)?
3. 哪些容易误解或目前实际无效(例如 `--test_iterations`)需要明确写出来?

## 做出的决定
- [决定] 先按方案B交付: 新增 `docs/fastgs-train-scripts.md`,把脚本与参数的关系讲清楚.

## 状态
**目前在阶段4**
- 2026-02-26 02:15 UTC: 收到请求,准备创建 `docs/` 并落地训练脚本参数说明文档.
- 2026-02-26 02:17 UTC: 已创建 `docs/` 并新增 `docs/fastgs-train-scripts.md`,当前准备回填四文件上下文记录交付物.
- 2026-02-26 02:20 UTC: 已完成回填: 更新 `task_plan.md` 阶段状态,并追加记录到 `notes.md`/`WORKLOG.md`.

---

# 任务计划: Git 提交并推送到 raiscui/FastGS

## 目标
- 将当前工作区所有预期改动提交到 Git.
- 将 `main` 分支推送到 `https://github.com/raiscui/FastGS.git`.

## 两种方向(供选择)
- 方案A(不惜代价,最佳): 按语义拆分为多个 commits(例如: Pixi 环境、docs 文档、仓库指南),并在 push 前做一次最小验证闭环.
- 方案B(先能用,后面再优雅): 先把当前改动合并为 1 个 commit 推上去,后续需要时再整理提交历史.

## 阶段
- [ ] 阶段1: 检查工作区与远端
- [ ] 阶段2: 整理变更并提交
- [ ] 阶段3: 配置远端并 push
- [ ] 阶段4: 验证与收尾

## 状态
**目前在阶段1**
- 2026-02-26 03:45 UTC: 收到请求,已检查 `git status`/当前 `origin` 远端,准备按方案B执行: 提交一次并推送到 raiscui/FastGS.
