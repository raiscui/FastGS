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
- [x] 阶段1: 检查工作区与远端
- [x] 阶段2: 整理变更并提交
- [x] 阶段3: 配置远端并 push
- [x] 阶段4: 验证与收尾

## 状态
**目前在阶段4**
- 2026-02-26 03:45 UTC: 收到请求,已检查 `git status`/当前 `origin` 远端,准备按方案B执行: 提交一次并推送到 raiscui/FastGS.
- 2026-02-26 03:51 UTC: 已提交: `3ca9b46` (`[FastGS] Add Pixi workspace and docs`).
- 2026-02-26 03:51 UTC: 已推送: `main` -> `https://github.com/raiscui/FastGS.git`(remote: `raiscui`).
- 2026-02-26 03:51 UTC: 已验证工作区干净: `git status` 无未提交改动.

---

# 任务计划: 改造 convert.py 支持直接处理整个视频文件夹

## 目标
- 保持  现有图片输入流程可用.
- 新增直接读取一个视频文件夹,将其中所有视频视为同一套数据,自动抽帧后复用原有 COLMAP 流程.
- 为视频输入提供最少但够用的参数,避免用户还要手动先做一轮 ffmpeg 抽帧.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 研究/收集信息
- [ ] 阶段3: 执行/构建
- [ ] 阶段4: 审查和交付

## 关键问题
1. 视频输入应该是替代  目录,还是先自动生成  再走原流程?
2. 如何在不破坏现有图片工作流的前提下,最小代价支持整文件夹视频?
3. 抽帧参数是否需要可配置,默认值应选择多少才更稳?
4. 对已有  图片与新生成帧之间的覆盖关系,应如何避免误混用?

## 做出的决定
- [决定] 先以“自动抽帧到  再复用原有 COLMAP 流程”为主方案. 理由: 与训练侧约定完全兼容,对现有  主流程侵入最小.
- [决定] 默认保留原有图片模式,新增显式视频目录参数启用视频模式. 理由: 避免把原先只放图片的数据集行为改坏.

## 状态
**目前在阶段1**
- 2026-03-10 04:05:33 UTC: 收到需求,准备先记录上下文并分析  的输入/输出约束.


## 进度更新

**目前在阶段4**
- 2026-03-10 04:10:59 UTC: 已完成 `convert.py` 视频目录模式改造, 支持直接把整个视频文件夹视为一套输入自动抽帧.
- 2026-03-10 04:10:59 UTC: 已完成静态验证: `python3 -m py_compile convert.py` 与 `python3 convert.py --help`.
- 2026-03-10 04:10:59 UTC: 已完成最小动态验证: 用 fake `ffmpeg` + fake `colmap` 跑通了“视频目录直输”和“旧 input 图片模式”两条路径.
- 2026-03-10 04:10:59 UTC: 本次曾出现一次 shell 反引号命令替换误触发, 已记录到 `ERRORFIX.md`, 本轮已改用 `python3` 追加文件避免再次发生.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 研究/收集信息
- [x] 阶段3: 执行/构建
- [x] 阶段4: 审查和交付


---

# 任务计划: 按真实素材目录调整 convert.py 输入发现逻辑

## 目标
- 根据 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 的真实目录结构, 判断 `convert.py` 应该支持递归扫描哪些输入.
- 让脚本能直接消费该目录结构, 不要求用户手工搬运 0/1/2/3/4/5 子目录里的素材.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 研究/收集信息
- [ ] 阶段3: 执行/构建
- [ ] 阶段4: 审查和交付

## 关键问题
1. `rgb/` 目录里装的是视频文件还是图片序列?
2. 当前层级是否固定为 `<root>/<index>/rgb/*`, 还是存在更深或更多变体?
3. 新逻辑应递归扫描全部媒体文件, 还是只识别 `rgb` 目录, 以降低误收集风险?

## 状态
**目前在阶段1**
- 2026-03-10 05:39:30 UTC: 收到用户提供的真实素材路径, 先核实目录结构与文件类型, 再决定 `convert.py` 的改法.


## 进度更新

**目前在阶段4**
- 2026-03-10 05:41:24 UTC: 已确认真实素材路径 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 会被识别为 `rgb_recursive` 模式,共发现 6 个视频.
- 2026-03-10 05:41:24 UTC: 已完成最小动态验证: 仿真 `<root>/<index>/rgb/*.mp4` 结构可成功抽帧到 `input/`,并继续产出 `images/` 与 `sparse/0/`.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 研究/收集信息
- [x] 阶段3: 执行/构建
- [x] 阶段4: 审查和交付


---

# 任务计划: 在真实 flashvsr_reference 素材目录执行 convert.py

## 目标
- 直接对 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 运行 `convert.py`.
- 产出可用于训练的 `input/`、`images/`、`sparse/0/`.
- 基于真实执行结果判断下一步是否可直接进入训练.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 环境与依赖检查
- [ ] 阶段3: 执行转换
- [ ] 阶段4: 验证与交付

## 状态
**目前在阶段1**
- 2026-03-10 05:42:49 UTC: 用户确认继续, 准备在真实素材目录上直接执行 `convert.py`.


## 进度更新

**目前在阶段4**
- 2026-03-10 06:02:57 UTC: 已在真实路径 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 成功执行 `python3 convert.py -s /workspace/lyra/outputs/flashvsr_reference/full_scale2x --video_fps 2 --no_gpu`.
- 2026-03-10 06:02:57 UTC: 真实执行结果: 递归 `rgb` 模式识别到 6 个视频,抽帧得到 60 张图, COLMAP 成功重建出 60 张图像和 21007 个稀疏点.
- 2026-03-10 06:02:57 UTC: 输出目录已核查通过: `input/` 60 张, `images/` 60 张, `sparse/0/` 含 `cameras.bin` / `images.bin` / `points3D.bin`.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 环境与依赖检查
- [x] 阶段3: 执行转换
- [x] 阶段4: 验证与交付


---

# 任务计划: 对真实 full_scale2x 数据运行 100 iter 烟雾训练

## 目标
- 用真实数据目录 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 跑一次 100 iter 短训练.
- 验证 FastGS 训练链路能否正确读取刚生成的 `images/` 和 `sparse/0/`.
- 在最小成本下确认是否可以进入正式训练.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 环境与输出目录准备
- [ ] 阶段3: 执行 100 iter 烟雾训练
- [ ] 阶段4: 验证与交付

## 状态
**目前在阶段1**
- 2026-03-10 06:17:22 UTC: 用户选择先跑 100 iter 烟雾训练, 准备创建独立输出目录并启动短训练.

- 2026-03-10 06:20 UTC: 继续上次未完成的阶段3. 先核查上一轮 smoke test 会话与  目录状态, 判断那次训练是否真的启动成功, 避免在不明确状态下重复训练.

- 2026-03-10 06:20 UTC: 继续上次未完成的阶段3. 先核查上一轮 smoke test 会话与 `output/` 目录状态, 判断那次训练是否真的启动成功, 避免在不明确状态下重复训练.

- 2026-03-10 06:21 UTC: 已确认上一轮 smoke test 其实已经正常跑完, 输出目录落在默认 `output/032e12b6-bfff-411f-a6c6-088cda08ac69`. 下一步核查训练产物与关键日志, 确认短训练链路完整可用.
## 进度更新

**目前在阶段4**
- 2026-03-10 06:21 UTC: 已回收上一轮 smoke test 会话输出, 确认训练并未失败, 而是因为 `-m` 参数为空回退到了默认目录 `output/032e12b6-bfff-411f-a6c6-088cda08ac69`.
- 2026-03-10 06:22 UTC: 已验证 100 iter 烟雾训练完整跑通. 训练读取了 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x/images` 与 `sparse/0/`, 初始化点数 21007, 第 100 iter 成功保存点云, 无 error 退出.
- 2026-03-10 06:23 UTC: 已补充核查 `--video_fps 2` 的真实抽帧结果. 这批视频实际时长约 5.04 秒, 每段在 2 fps 下各抽出 10 张, 6 段合计 60 张.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 环境与输出目录准备
- [x] 阶段3: 执行 100 iter 烟雾训练
- [x] 阶段4: 验证与交付

---

# 任务计划: 对 full_scale2x 启动正式训练并保留原始分辨率

## 目标
- 基于真实数据目录 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x` 启动一轮正式 FastGS 训练.
- 显式传入 `--resolution 1`, 避免训练阶段自动把图像宽度缩到 1.6K.
- 在启动后尽快确认训练已经进入正常迭代, 没有因为显存或输入数据问题立即失败.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 训练命令与输出目录准备
- [ ] 阶段3: 启动正式训练并观察首轮日志
- [ ] 阶段4: 核查状态并交付当前进展

## 关键问题
1. 正式训练输出目录应使用什么命名, 才能和前面的 smoke test 清晰区分?
2. `--resolution 1` 下是否会在训练启动阶段就出现显存或数据读取错误?
3. 是否需要额外传参, 还是先用仓库默认训练配置最稳?

## 做出的决定
- [决定] 先沿用仓库默认训练参数, 只额外加 `--resolution 1`. 理由: 当前已验证数据链路通, 先只改变分辨率这一项, 便于把风险收敛到单一变量.
- [决定] 输出目录使用带时间戳的独立路径. 理由: 避免和前面的 100 iter smoke test 或后续别的尝试互相覆盖.

## 状态
**目前在阶段1**
- 2026-03-10 06:26 UTC: 用户选择方案2, 准备启动正式训练, 并显式保留原始分辨率.
- 2026-03-10 06:33 UTC: 已准备正式训练输出目录 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357`. 下一步直接用 `pixi run python train.py -s /workspace/lyra/outputs/flashvsr_reference/full_scale2x -m /workspace/FastGS/output/full_scale2x_res1_20260310_063357 --resolution 1` 启动训练, 并观察首轮日志是否稳定.
- 2026-03-10 06:35 UTC: 正式训练已成功进入迭代, 当前 `--resolution 1` 配置下无即时报错, 且 `cfg_args` 已确认 `resolution=1`. 由于这轮训练预计不是特别长, 继续直接守到训练完成, 再统一核查最终产物.
## 进度更新

**目前在阶段4**
- 2026-03-10 06:33 UTC: 已创建正式训练输出目录 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357`, 并启动 `pixi run python train.py -s /workspace/lyra/outputs/flashvsr_reference/full_scale2x -m /workspace/FastGS/output/full_scale2x_res1_20260310_063357 --resolution 1`.
- 2026-03-10 06:34 UTC: 已确认训练成功进入迭代, `cfg_args` 中明确记录 `resolution=1`, 且训练日志里不再出现“自动缩到 1.6K”的提示.
- 2026-03-10 06:40 UTC: 正式训练完整结束. 关键结果: `30000` iter 完成, 最终保存目录 `point_cloud/iteration_30000`, Gaussian 数量 `154271`, 训练耗时约 `332.24` 秒, 无 error 退出.
- 2026-03-10 06:41 UTC: 已核查最终产物齐全: `cfg_args`、`cameras.json`、`input.ply`、`train.log`、`point_cloud/iteration_30000/point_cloud.ply` 均存在.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 训练命令与输出目录准备
- [x] 阶段3: 启动正式训练并观察首轮日志
- [x] 阶段4: 核查状态并交付当前进展

---

# 任务计划: 评估 full_scale2x 正式训练结果的 PSNR

## 目标
- 对 `/workspace/FastGS/output/full_scale2x_res1_20260310_063357` 这轮正式训练结果执行渲染与指标评估.
- 用仓库自带 `render.py` 与 `metrics.py` 计算真实 PSNR, 而不是根据 loss 主观猜测.
- 如果脚本同时给出 SSIM/LPIPS, 一并记录下来, 方便后续对比.

## 阶段
- [ ] 阶段1: 计划和设置
- [ ] 阶段2: 确认评估命令与输入
- [ ] 阶段3: 渲染并计算指标
- [ ] 阶段4: 汇总结果并交付

## 关键问题
1. 当前这轮训练输出是否已经具备 `render.py` / `metrics.py` 所需的全部输入?
2. 评估结果是只包含 test, 还是 train/test 都会给出?
3. 如果没有可评估的 test 集, 脚本会怎样表现?

## 做出的决定
- [决定] 直接对刚完成的正式训练目录做标准闭环评估: 先 `render.py`, 再 `metrics.py`. 理由: 这是仓库文档给出的标准验证路径, 结果最可信.

## 状态
**目前在阶段1**
- 2026-03-10 06:42 UTC: 用户追问 PSNR, 准备直接跑渲染与指标脚本拿真实数值.
- 2026-03-10 07:05 UTC: 发现当前正式训练目录没有可用的 test 视角. `render.py --skip_train` 的动态结果是 `[test] Rendered 0 frames`, 说明暂时拿不到 test PSNR. 下一步先确认是否由 `eval=False` 导致, 再改为渲染 train 视角并计算可用的重建 PSNR.
## 进度更新

**目前在阶段4**
- 2026-03-10 07:05 UTC: 已验证当前正式训练目录没有 test 视角. `render.py --skip_train` 的动态结果是 `[test] Rendered 0 frames`, 与 `cfg_args` 里的 `eval=False` 相符.
- 2026-03-10 07:07 UTC: 已完成 train 视角渲染, 共 60 帧, 输出位于 `output/full_scale2x_res1_20260310_063357/train/ours_30000`.
- 2026-03-10 07:08 UTC: 已按仓库同一套 `psnr` / `ssim` 实现完成 train 集指标统计. 结果: `PSNR = 26.6863`, `SSIM = 0.8609`, 样本数 60.

- [x] 阶段1: 计划和设置
- [x] 阶段2: 确认评估命令与输入
- [x] 阶段3: 渲染并计算指标
- [x] 阶段4: 汇总结果并交付

---

# 任务计划: 提交并推送当前 FastGS 改动

## 目标
- 核对当前工作区改动与远端信息.
- 只提交本轮真实产生的相关改动, 避免误带无关内容.
- 将提交推送到当前分支对应远端.

## 阶段
- [ ] 阶段1: 核查工作区与远端
- [ ] 阶段2: 审阅改动范围并准备提交
- [ ] 阶段3: 提交并推送
- [ ] 阶段4: 验证结果并交付

## 关键问题
1. 当前工作区里是否只有本轮相关改动?
2. 是否存在 submodule 需要同步处理?
3. 当前分支和远端跟踪关系是否明确?

## 状态
**目前在阶段1**
- 2026-03-10 07:10 UTC: 用户要求执行 git 推送, 先核对工作区改动、当前分支和远端信息.
## 进度更新

**目前在阶段4**
- 2026-03-10 07:11 UTC: 已确认当前分支 `main` 相对 `origin/main` 处于 `ahead 1`, 待推送提交为 `e469b93 convert`.
- 2026-03-10 07:11 UTC: 已尝试执行 `git push origin main`, 但失败. 现象是 Git 走到了失效的 VS Code askpass 通道, 报错 `Missing or invalid credentials` 与 `connect ENOENT /tmp/vscode-git-32d97efe37.sock`.
- 2026-03-10 07:12 UTC: 已补充核查本机认证状态: 无可用 SSH key, `ssh -T git@github.com` 返回 `Permission denied (publickey)`; 同时也未发现 `~/.git-credentials` / `~/.netrc` / `gh` 等可复用认证入口.
- 2026-03-10 07:12 UTC: 结论是当前环境缺少可用 GitHub 凭据, 因此本轮无法由我直接完成远端推送. 本地提交仍保留在 `main` 上, 未丢失.

- [x] 阶段1: 核查工作区与远端
- [x] 阶段2: 审阅改动范围并准备提交
- [x] 阶段3: 提交并推送
- [x] 阶段4: 验证结果并交付

---

# 任务计划: 检查本机 SSH 是否允许密码登录

## 目标
- 不触碰任何密码内容,只核查本机 SSH 服务是否启用了密码登录.
- 给出基于有效配置的结论,避免只看单个配置文件造成误判.

## 阶段
- [x] 阶段1: 读取上下文与历史记录
- [ ] 阶段2: 核查 SSH 有效配置
- [ ] 阶段3: 整理结论并回写记录

## 关键问题
1. `sshd` 的有效 `PasswordAuthentication` 当前是什么值?
2. 是否存在 `Include` 或发行版默认文件导致“主配置看似关闭/开启,实际生效不同”的情况?

## 做出的决定
- [决定] 优先查看 `sshd -T` 的有效配置,因为它比只看 `/etc/ssh/sshd_config` 更接近真实运行结果.
- [决定] 同时补看配置文件来源,避免结论只有结果没有依据.

## 状态
**目前在阶段2**
- 2026-03-10 08:23:39 UTC: 已读完上下文文件,现在开始核查 `sshd` 的有效配置与配置来源.

## 进度更新
- 2026-03-10 08:24:49 UTC: 已完成 `sshd -T`、`/etc/ssh/sshd_config`、监听端口与运行进程核查.
- 已确认有效配置为 `PasswordAuthentication yes`.
- 已确认当前监听端口为 `23`,且 `PermitRootLogin yes`.

## 当前待办
- [x] 阶段1: 读取上下文与历史记录
- [x] 阶段2: 核查 SSH 有效配置
- [x] 阶段3: 整理结论并回写记录

## 状态
**目前已完成**
- 2026-03-10 08:24:49 UTC: 结论已形成,准备向用户返回带证据的结果.

---

# 任务计划: 判断本机是否可以支持 GPU 版 COLMAP

## 目标
- 判断 `convert.py` 是否还需要改代码才能支持 GPU 版 COLMAP.
- 判断当前机器是否具备安装或编译 CUDA 版 `colmap` 的基础条件.
- 给出最稳的落地方案,避免把“环境问题”误判成“脚本问题”.

## 阶段
- [x] 阶段1: 读取上下文与历史记录
- [ ] 阶段2: 核查 `convert.py` 与当前 `colmap` 能力
- [ ] 阶段3: 核查本机 CUDA / 编译环境
- [ ] 阶段4: 形成结论并回写记录

## 关键问题
1. `convert.py` 当前默认是不是已经会请求 COLMAP 使用 GPU?
2. 当前真正的限制是在脚本层,还是在 `/usr/bin/colmap` 的构建方式?
3. 这台机器是否有足够的 CUDA / CMake / 编译环境去落地 GPU 版 COLMAP?

## 做出的决定
- [决定] 先看代码和当前 `colmap -h`, 因为这是区分“代码问题”和“环境问题”的最小证据.
- [决定] 再看 `nvidia-smi`、`nvcc`、`cmake`, 只在确认环境具备条件后再讨论安装路径.

## 状态
**目前在阶段3**
- 2026-03-11 00:00:00 UTC: 已确认 `convert.py` 默认会在未传 `--no_gpu` 时请求 COLMAP 使用 GPU.
- 2026-03-11 00:00:00 UTC: 已确认当前 `/usr/bin/colmap` 自报 `without CUDA`, 当前主假设是“脚本已支持, 限制在系统安装的 COLMAP 二进制”.

## 当前待办
- [x] 阶段1: 读取上下文与历史记录
- [x] 阶段2: 核查 `convert.py` 与当前 `colmap` 能力
- [ ] 阶段3: 核查本机 CUDA / 编译环境
- [ ] 阶段4: 形成结论并回写记录

## 进度更新
- 2026-03-11 05:46:33 UTC: 已完成本机 GPU / CUDA / 编译环境核查.
- 已确认本机显卡为 `NVIDIA A800-SXM4-80GB`, 驱动 `580.105.08`, `nvcc` 为 `12.6`, `cmake` 为 `3.22.1`, `g++` 为 `11.4.0`.
- 已结合官方安装文档确认: Linux 默认仓库中的 `colmap` 包通常不带 CUDA 支持, 若要 GPU 版,需要自行编译或使用单独的 CUDA 版构建.
- 已确认 `convert.py` 已有 `--colmap_executable`, 因此即使安装第二份 GPU 版 `colmap`, 也不必覆盖系统的 CPU 版.

## 当前待办
- [x] 阶段1: 读取上下文与历史记录
- [x] 阶段2: 核查 `convert.py` 与当前 `colmap` 能力
- [x] 阶段3: 核查本机 CUDA / 编译环境
- [x] 阶段4: 形成结论并回写记录

## 状态
**目前已完成**
- 2026-03-11 05:46:33 UTC: 结论已形成. 当前不是脚本缺少 GPU 支持,而是系统安装的 `colmap` 为 CPU 版. 若需要 GPU 版,建议单独编译安装,并通过 `--colmap_executable` 指向新二进制.

---

# 任务计划: 在 /workspace 编译支持 CUDA 的 COLMAP

## 目标
- 在 `/workspace` 下获取并编译一份支持 CUDA 的 `colmap`.
- 尽量不覆盖系统已有的 `/usr/bin/colmap`, 保留 CPU 版作为回退路径.
- 最终给出可直接用于 `convert.py` 的 GPU 版二进制路径.

## 阶段
- [x] 阶段1: 读取上下文与历史记录
- [ ] 阶段2: 确认官方构建方式与依赖
- [ ] 阶段3: 准备源码与依赖环境
- [ ] 阶段4: 编译并验证 CUDA 版 COLMAP
- [ ] 阶段5: 记录结果并交付

## 关键问题
1. 官方当前推荐的 Linux CUDA 构建路径是什么?
2. 本机是否缺少编译 COLMAP 所需的系统依赖?
3. 编译产物应该放在 `/workspace` 的哪个位置, 便于后续复用且不污染系统路径?

## 做出的决定
- [决定] 保留系统 CPU 版 `colmap`, 目标安装前缀优先使用 `/workspace/colmap-cuda-install`.
- [决定] 先走官方依赖和 CMake 路线, 避免使用不明来源的第三方打包脚本.
- [决定] 编译完成后先用 `colmap -h` 或 `feature_extractor -h` 验证是否脱离 `without CUDA` 口径, 再交付.

## 状态
**目前在阶段2**
- 2026-03-11 05:47:30 UTC: 已开始读取上下文, 并准备核对官方 CUDA 构建说明.

## 当前待办
- [x] 阶段1: 读取上下文与历史记录
- [ ] 阶段2: 确认官方构建方式与依赖
- [ ] 阶段3: 准备源码与依赖环境
- [ ] 阶段4: 编译并验证 CUDA 版 COLMAP
- [ ] 阶段5: 记录结果并交付

## 进度更新
- 2026-03-11 06:02:10 UTC: 官方依赖已安装完成, 当前进入源码准备阶段.
- 补充动态证据: `ldconfig -p` 当前解析到的 `libcuda.so.1` 与 `libnvidia-ml.so.1` 指向的是 `580.105.08` 版本的实际库, `apt` 安装后的空文件告警暂不构成当前主阻塞.

## 进度更新
- 2026-03-11 06:05:40 UTC: CMake 配置已成功完成.
- 关键输出已确认:
  - `The CUDA compiler identification is NVIDIA 12.6.20`
  - `Enabling CUDA support (version: 12.6.20, archs: 80)`
  - `Enabling GPU support (OpenGL: ON, CUDA: ON)`
- 当前进入正式编译阶段.

## 进度更新
- 2026-03-11 06:09:49 UTC: 已完成安装后的动态验证.
- 使用 2 张真实图片执行:
  - `/workspace/colmap-cuda-install-3.12.6/bin/colmap feature_extractor --SiftExtraction.use_gpu 1 ...`
- 关键动态输出:
  - `Creating SIFT GPU feature extractor`
  - 2 张图均成功提取特征, 未出现 CUDA 初始化失败.
- 当前待办已全部完成.

## 当前待办
- [x] 阶段1: 读取上下文与历史记录
- [x] 阶段2: 确认官方构建方式与依赖
- [x] 阶段3: 准备源码与依赖环境
- [x] 阶段4: 编译并验证 CUDA 版 COLMAP
- [x] 阶段5: 记录结果并交付

## 状态
**目前已完成**
- 2026-03-11 06:09:49 UTC: `/workspace/colmap-cuda-install-3.12.6/bin/colmap` 已编译、安装并完成 GPU 特征提取动态验证, 可供 `convert.py` 通过 `--colmap_executable` 使用.

---

# 任务计划: 固化 GPU 版 COLMAP 构建文档

## 目标
- 将这次在 `/workspace` 成功编译 CUDA 版 `colmap` 的真实步骤写入仓库文档.
- 文档要覆盖依赖、源码/构建/安装目录、编译命令、验证命令, 以及如何与 `convert.py` 集成.
- 文档内容优先基于这台机器上的真实验证结果, 而不是泛泛转述官方文档.

## 阶段
- [x] 阶段1: 读取上下文与现有文档风格
- [ ] 阶段2: 整理本次真实构建路径与验证证据
- [ ] 阶段3: 编写 `docs/colmap_cuda_build.md`
- [ ] 阶段4: 自检文档命令与交付

## 关键问题
1. 文档应该写成“通用官方安装步骤”, 还是“本机已验证路径”? 
2. 是否要把 `convert.py` 的接入命令直接写进去, 让用户可立即复用?
3. 是否需要记录这次遇到的环境侧注意事项, 比如系统 CPU 版 `colmap` 并存策略?

## 做出的决定
- [决定] 以“本机已验证路径”为主线, 因为这是当前最有复用价值的事实证据.
- [决定] 文档中直接给出 `convert.py --colmap_executable` 的使用示例, 减少二次推断.
- [决定] 保留系统 CPU 版与并行安装 CUDA 版的策略说明, 避免未来误覆盖.

## 状态
**目前在阶段2**
- 2026-03-11 06:11:20 UTC: 已收到用户选择, 继续把 GPU 版 COLMAP 的成功构建路径沉淀成仓库文档.

## 当前待办
- [x] 阶段1: 读取上下文与现有文档风格
- [ ] 阶段2: 整理本次真实构建路径与验证证据
- [ ] 阶段3: 编写 `docs/colmap_cuda_build.md`
- [ ] 阶段4: 自检文档命令与交付

## 进度更新
- 2026-03-11 06:14:10 UTC: 已新增 `docs/colmap_cuda_build.md`, 内容覆盖依赖、目录、CMake 配置、编译、静态验证、动态验证以及 `convert.py` 接入方式.
- 2026-03-11 06:14:10 UTC: 已在 `README.md` 的环境设置段落补充轻量入口链接, 便于后续发现这份文档.
- 2026-03-11 06:14:10 UTC: 已完成自检, 文档中的关键命令与路径均来自本轮真实执行结果.

## 当前待办
- [x] 阶段1: 读取上下文与现有文档风格
- [x] 阶段2: 整理本次真实构建路径与验证证据
- [x] 阶段3: 编写 `docs/colmap_cuda_build.md`
- [x] 阶段4: 自检文档命令与交付

## 状态
**目前已完成**
- 2026-03-11 06:14:10 UTC: GPU 版 COLMAP 的成功构建路径已沉淀进仓库文档, 并在 README 中加入入口.

## 遇到的错误
- 2026-03-11 06:15:10 UTC: 首轮文档自检时,把带反引号的文本直接作为 `rg` 正则传入,触发了 `rg: the literal "\\n" is not allowed in a regex`.
- 处理: 改为 `rg -F` 逐条做固定字符串校验, 避免把文档里的特殊字符误当成正则.

---

# 任务计划: 整理 `data/s01` 的 3DGS 前处理与训练命令文档

## 目标
- 将 `data/s01` 这套 3ds Max 渲染的多机位序列图,整理成一份可直接复制执行的 FastGS 文档.
- 文档覆盖: 数据前提、COLMAP 稀疏重建、FastGS 训练命令、A800 80G 下的推荐分辨率.
- 明确记录用户指定的 GPU 版 COLMAP 路径:`/workspace/colmap-cuda-install-3.12.6/bin/colmap`.

## 两种方向
- 方案A(不惜代价,最佳): 新增一份 `docs/` 文档,并在 `README.md` 增加轻量入口,方便以后直接复用.
- 方案B(先能用,后面再优雅): 仅新增 `docs/` 文档,先不改 README,减少影响面.

## 阶段
- [x] 阶段1: 读取上下文与现有文档
- [ ] 阶段2: 核对 `s01` 数据前提与命令口径
- [ ] 阶段3: 编写命令文档
- [ ] 阶段4: 自检并回填上下文

## 关键问题
1. 这份文档应该以 `convert.py` 为主,还是以手动 COLMAP CLI 为主?
2. `s01` 当前缺少哪些训练必需物,需要在文档里明确说明?
3. A800 80G 下该推荐 `-r 2` 还是 `-r 1`,以及是否保留 smoke test 命令?

## 做出的决定
- [决定] 采用方案A,因为这份文档很可能会被重复使用,在 README 增加入口更容易发现.
- [决定] 文档主线使用手动 COLMAP CLI,因为当前 `convert.py` 默认 `single_camera=1`,不适合多机位目录.
- [决定] 统一使用用户指定的 GPU 版 COLMAP 路径,并在文档中用环境变量 `COLMAP_BIN` 收口.

## 状态
**目前在阶段2**
- 2026-03-11 06:18 UTC: 已读取上下文文件、现有 docs 与 README 入口,准备整理 `s01` 的最终命令口径.

## 当前待办
- [x] 阶段1: 读取上下文与现有文档
- [ ] 阶段2: 核对 `s01` 数据前提与命令口径
- [ ] 阶段3: 编写命令文档
- [ ] 阶段4: 自检并回填上下文

## 进度更新
- 2026-03-11 06:24 UTC: 已按最新动态事实重核 `data/s01`, 当前 `C01pick` ~ `C06pick` 六个目录均有 51 张图, 不再沿用早先“`C03pick` 为空”的旧判断.
- 2026-03-11 06:24 UTC: 已新增 `docs/s01_3dgs_workflow.md`, 文档主线采用手动 COLMAP CLI, 并统一使用用户指定的 GPU 版 COLMAP 路径.
- 2026-03-11 06:24 UTC: 已在 `README.md` 增加 `data/s01` 命令文档入口, 方便后续直接发现.
- 2026-03-11 06:24 UTC: 已完成自检, 核对了 README 入口、`COLMAP_BIN` 路径、`single_camera_per_folder`、smoke test 与正式训练命令的一致性.

## 当前待办
- [x] 阶段1: 读取上下文与现有文档
- [x] 阶段2: 核对 `s01` 数据前提与命令口径
- [x] 阶段3: 编写命令文档
- [x] 阶段4: 自检并回填上下文

## 状态
**目前已完成**
- 2026-03-11 06:24 UTC: `data/s01` 的 3DGS 前处理与训练命令文档已落盘到 `docs/s01_3dgs_workflow.md`, 并在 `README.md` 增加入口.

---

# 任务计划: 为 `data/s01` 落地可直接执行的一键脚本并完成实测

## 目标
- 提供一个真正可直接运行的脚本,从 `data/s01` 完成多机位 COLMAP 前处理并接 FastGS 训练.
- 脚本要内建当前已验证的正确口径:
  - 使用 GPU 版 COLMAP
  - 多机位目录按 `single_camera_per_folder`
  - 避免“目录软链接导致 COLMAP 读到 0 张图”的坑
- 在真实机器上完成至少一轮 smoke test,给出动态验证证据.

## 阶段
- [x] 阶段1: 回读上下文与已有文档
- [ ] 阶段2: 定位 `mapper` 失败的真实原因
- [ ] 阶段3: 编写一键脚本
- [ ] 阶段4: 在真实数据上执行脚本验证
- [ ] 阶段5: 回填上下文并交付

## 关键问题
1. 用户当前 `mapper` 报 “No images with matches found in the database” 的直接原因是什么?
2. 一键脚本应该用 bash 还是 python 更稳?
3. 真实验证时,应该跑全量数据还是先用子采样 smoke test 验链路?

## 做出的决定
- [决定] 先按“现象 -> 假设 -> 最小验证”排查 `mapper` 报错,避免直接围绕旧文档补丁式修改.
- [决定] 优先落 bash 脚本,因为用户要的是“直接跑的完整一键脚本”,shell 入口最直接.
- [决定] 真实验证先跑可控的 smoke test,必要时再放大全量范围.

## 状态
**目前在阶段2**
- 2026-03-11 06:44 UTC: 已开始复盘用户贴出的 `mapper` 错误, 先核查数据库计数和 `images/` 目录组织方式.

## 进度更新
- 2026-03-11 06:46 UTC: 已验证用户当前失败现场中 `database.db` 的 `cameras/images/keypoints/matches` 计数全部为 0.
- 2026-03-11 06:46 UTC: 已完成最小对照实验:
  - “目录软链接”输入 -> COLMAP 数据库计数为 0
  - “真实目录 + 文件复制”输入 -> 正常入库
  - “真实目录 + 文件软链接”输入 -> 正常入库
- 2026-03-11 06:46 UTC: 当前主结论已转为已验证结论: 失败根因不是 `mapper`, 而是 `feature_extractor` 没有跟进目录软链接,导致数据库为空.

## 当前待办
- [x] 阶段1: 回读上下文与已有文档
- [x] 阶段2: 定位 `mapper` 失败的真实原因
- [ ] 阶段3: 编写一键脚本
- [ ] 阶段4: 在真实数据上执行脚本验证
- [ ] 阶段5: 回填上下文并交付

## 进度更新
- 2026-03-11 06:50 UTC: 已新增 `scripts/run_s01_fastgs.sh`, 默认从 `data/s01` 一路执行到 `output/s01`, 并支持 `--phase`、`--overwrite`、`--frame-limit`、`--iterations`、`--eval` 等参数.
- 2026-03-11 06:50 UTC: 已完成脚本静态校验:
  - `bash -n scripts/run_s01_fastgs.sh`
  - `bash scripts/run_s01_fastgs.sh --help`
- 2026-03-11 06:50 UTC: 已在真实 `data/s01` 上完成端到端 smoke test:
  - 命令:
    - `bash scripts/run_s01_fastgs.sh --overwrite --frame-limit 1 --iterations 10 --colmap-root data/s01_colmap_script_smoke --fastgs-root data/s01_fastgs_script_smoke --model-path output/s01_script_smoke`
  - 关键动态证据:
    - `feature_extractor 完成: cameras=6, images=6`
    - `exhaustive_matcher 完成: two_view_geometries=15`
    - `Reconstruction with 6 images and 2389 points`
    - `Training complete.`
    - 产物:
      - `data/s01_fastgs_script_smoke/sparse/0/points3D.ply`
      - `output/s01_script_smoke/point_cloud/iteration_10/point_cloud.ply`
- 2026-03-11 06:50 UTC: 已同步修正文档:
  - `docs/s01_3dgs_workflow.md` 改为“真实目录 + 文件级软链接”
  - `README.md` 增加一键脚本入口

## 当前待办
- [x] 阶段1: 回读上下文与已有文档
- [x] 阶段2: 定位 `mapper` 失败的真实原因
- [x] 阶段3: 编写一键脚本
- [x] 阶段4: 在真实数据上执行脚本验证
- [x] 阶段5: 回填上下文并交付

## 状态
**目前已完成**
- 2026-03-11 06:50 UTC: `data/s01` 的一键脚本、文档修正与真实 smoke test 已全部完成.

---

# 任务计划: 补充 `--resolution` 与 COLMAP 关系的文档说明

## 目标
- 将“修改 `--resolution` 不需要重新跑 COLMAP”这条规则补进 `docs/s01_3dgs_workflow.md`.
- 把这条说明放到训练章节附近, 让后续做分辨率实验时更容易看到.

## 阶段
- [x] 阶段1: 回读上下文与定位文档位置
- [ ] 阶段2: 更新 `docs/s01_3dgs_workflow.md`
- [ ] 阶段3: 自检并回填上下文

## 做出的决定
- [决定] 只改 `docs/s01_3dgs_workflow.md`, 不扩大到其他文档面.
- [决定] 把说明放在训练分辨率说明之后, 与 `-r 1 / -r 2 / -r 4` 的使用语境放在一起.

## 状态
**目前在阶段2**
- 2026-03-11 06:54 UTC: 已定位到训练章节, 准备补充 “改 `--resolution` 只需重训, 不需重出 COLMAP” 的说明.

## 进度更新
- 2026-03-11 06:55 UTC: 已在 `docs/s01_3dgs_workflow.md` 的训练章节补入 `8.1.1` 小节, 明确说明改 `--resolution` 时不需要重跑 COLMAP.
- 2026-03-11 06:55 UTC: 已补充两条可直接复用的训练示例:
  - `output/s01_r2`
  - `output/s01_r1`
- 2026-03-11 06:55 UTC: 自检时首轮 `rg` 命令把带反引号的文本放进 shell 双引号, 触发了命令替换; 随后已改为 `rg -F` 固定字符串校验, 文档内容无误.

## 当前待办
- [x] 阶段1: 回读上下文与定位文档位置
- [x] 阶段2: 更新 `docs/s01_3dgs_workflow.md`
- [x] 阶段3: 自检并回填上下文

## 状态
**目前已完成**
- 2026-03-11 06:55 UTC: `docs/s01_3dgs_workflow.md` 已补充“改 `--resolution` 不需要重跑 COLMAP”说明.

---

# 任务计划: 排查 `scripts/run_s01_fastgs.sh --overwrite` 训练后空间被压扁

## 目标
- 解释用户观察到的“空间高度像正常的一半,整体被压扁”的现象.
- 通过最小对照实验确认问题更接近 COLMAP 前处理,还是 FastGS 训练阶段.
- 如果证据足够,直接修正脚本默认参数与文档,并补充验证说明.

## 两种方向
- 方案A(不惜代价,最佳): 跑完整对照重建,比较不同相机模型下的内参与 sparse 几何,再决定是否修改脚本默认值.
- 方案B(先能用,后面再优雅): 先给用户一个试验命令切换相机模型,不改默认脚本,等待更多反馈.

## 阶段
- [x] 阶段1: 回读上下文与收集现象证据
- [ ] 阶段2: 建立主假设与备选解释
- [ ] 阶段3: 进行最小可证伪实验
- [ ] 阶段4: 根据证据修正脚本/文档
- [ ] 阶段5: 验证与交付

## 关键问题
1. “压扁”是训练阶段引入的, 还是 COLMAP 稀疏重建阶段已经存在?
2. 当前 `PINHOLE` 是否把无畸变渲染图的 `fx/fy` 优化到了异常比例?
3. 若改用 `SIMPLE_PINHOLE`, 是否能显著改善几何比例?

## 当前已知现象
- 2026-03-11 07:40 UTC: 当前 `PINHOLE` 结果中, `cameras.bin`/`cameras.json` 出现异常内参比例, 例如 `fx≈3231`, `fy≈8161`.
- 2026-03-11 07:40 UTC: `data/s01_colmap/sparse/0/points3D.bin` 的包围盒高度明显偏薄, 说明异常在 COLMAP 阶段就已经出现.
- 2026-03-11 07:40 UTC: FastGS 训练后点云包围盒反而更接近立方, 所以“压扁感”不能直接归因到训练代码.

## 当前主假设与备选解释
- 主假设: 对这批“无畸变渲染图”, `PINHOLE` 的自由度偏高, 造成 COLMAP 把 `fx/fy` 拟合到异常比例, 进而拉扁稀疏几何.
- 备选解释: 数据本身竖直视差不足, 即便换成 `SIMPLE_PINHOLE` 也仍会压扁; 那就需要进一步固定内参或重审取帧方式.

## 状态
**目前在阶段3**
- 2026-03-11 08:02 UTC: 已续跑 full data + `SIMPLE_PINHOLE` 的对照实验, 当前正在等待 `exhaustive_matcher/mapper` 完成, 然后对比相机内参与 sparse 几何比例.

---

# 任务计划: 解释 drjohnson 训练命令参数含义

## 目标
- 结合当前仓库代码,解释用户给出的训练命令中环境变量与训练参数的真实含义.
- 说明每个参数主要影响哪一段训练逻辑,以及它更偏向速度、质量、稳定性还是显存/点数.

## 阶段
- [ ] 阶段1: 读取历史上下文并确认已有结论
- [ ] 阶段2: 核对当前代码中的参数定义与使用位置
- [ ] 阶段3: 归纳参数之间的联动关系与调参影响
- [ ] 阶段4: 面向用户交付解释

## 关键问题
1. 这些参数分别在哪里定义,默认值是什么?
2. 哪些参数真的会生效,哪些可能只是历史遗留或当前路径未启用?
3. 这些参数对最终效果的方向性影响是什么?

## 状态
**目前在阶段1**
- 2026-03-11 07:57:31 UTC: 收到参数解释请求,已先回读六文件上下文,准备按代码定义逐项核对.


## 进度更新

**目前在阶段4**
- 2026-03-11 07:58:42 UTC: 已完成代码核对,确认 `OAR_JOB_ID` 只影响输出目录命名,`--test_iterations` 当前训练中不生效,其余关键参数已定位到 densify / SH 学习率 / compact box / train-test 切分等真实代码路径.

- [x] 阶段1: 读取历史上下文并确认已有结论
- [x] 阶段2: 核对当前代码中的参数定义与使用位置
- [x] 阶段3: 归纳参数之间的联动关系与调参影响
- [x] 阶段4: 面向用户交付解释

## 进度更新
- 2026-03-11 08:09:36 UTC: 已完成 full data 相机模型对照实验:
  - `PINHOLE`: `fx≈3231`, `fy≈8162`, `points=80107`, `spans=[76.37, 5.82, 46.02]`, `Mean reprojection error=0.595px`
  - `SIMPLE_PINHOLE`: `f≈3231`, `points=86581`, `spans=[76.73, 16.56, 59.95]`, `Mean reprojection error=0.573px`
- 2026-03-11 08:09:36 UTC: 主假设已升级为已验证结论: `data/s01` 的“空间被压扁”主要发生在 COLMAP 阶段, 当前触发点是 `PINHOLE` 把这批无畸变渲染图拟合成了异常 `fx/fy` 比例.
- 2026-03-11 08:09:36 UTC: 已修正 `scripts/run_s01_fastgs.sh`:
  - 默认相机模型改为 `SIMPLE_PINHOLE`
  - 新增 `--camera-model <SIMPLE_PINHOLE|PINHOLE>` 覆盖开关
  - 新增参数校验与启动日志打印
- 2026-03-11 08:09:36 UTC: 已同步更新 `docs/s01_3dgs_workflow.md`, 补入真实对照证据与“为什么默认 `SIMPLE_PINHOLE`”说明.
- 2026-03-11 08:09:36 UTC: 已完成动态验证:
  - `bash -n scripts/run_s01_fastgs.sh`
  - `bash scripts/run_s01_fastgs.sh --help`
  - `bash scripts/run_s01_fastgs.sh --overwrite --frame-limit 1 --iterations 10 --colmap-root data/s01_colmap_simple_smoke_verify --fastgs-root data/s01_fastgs_simple_smoke_verify --model-path output/s01_simple_smoke_verify`
  - 关键输出:
    - `feature_extractor 完成: cameras=6, images=6`
    - `exhaustive_matcher 完成: two_view_geometries=15`
    - `Reconstruction with 6 images and 1974 points`
    - `Training complete.`

## 当前待办
- [x] 阶段1: 回读上下文与收集现象证据
- [x] 阶段2: 建立主假设与备选解释
- [x] 阶段3: 进行最小可证伪实验
- [x] 阶段4: 根据证据修正脚本/文档
- [x] 阶段5: 验证与交付

## 状态
**目前已完成**
- 2026-03-11 08:09:36 UTC: `data/s01` 的“空间被压扁”问题已完成定位、修复与脚本级验证. 现默认推荐相机模型为 `SIMPLE_PINHOLE`.

---

# 任务计划: 为 `scripts/run_s01_fastgs.sh` 增加 `-r` 短参数

## 目标
- 让 `scripts/run_s01_fastgs.sh` 支持用 `-r` 代替 `--resolution`.
- 同步更新脚本帮助文本, 并完成最小语法与帮助验证.

## 阶段
- [ ] 阶段1: 确认当前参数解析逻辑
- [ ] 阶段2: 修改脚本并同步帮助文本
- [ ] 阶段3: 验证与回填上下文

## 状态
**目前在阶段1**
- 2026-03-11 08:10:30 UTC: 已读取脚本, 确认当前只有 `--resolution`, 还没有 `-r` 短参数入口.

## 进度更新
- 2026-03-11 08:11:05 UTC: 已在 `scripts/run_s01_fastgs.sh` 中为 `--resolution` 增加 `-r` 短参数别名.
- 2026-03-11 08:11:05 UTC: 已完成最小验证:
  - `bash -n scripts/run_s01_fastgs.sh`
  - `bash scripts/run_s01_fastgs.sh --help | rg -n "resolution"`
  - `bash scripts/run_s01_fastgs.sh -r 4 --help`

## 当前待办
- [x] 阶段1: 确认当前参数解析逻辑
- [x] 阶段2: 修改脚本并同步帮助文本
- [x] 阶段3: 验证与回填上下文

## 状态
**目前已完成**
- 2026-03-11 08:11:05 UTC: `scripts/run_s01_fastgs.sh` 已支持 `-r` 作为 `--resolution` 的短参数.

---

# 任务计划: 将 `docs/s01_3dgs_workflow.md` 改写为 `scripts/run_s01_fastgs.sh` 使用说明

## 目标
- 清空旧的手动 COLMAP 流程型文档.
- 将 `docs/s01_3dgs_workflow.md` 改写为纯粹围绕 `scripts/run_s01_fastgs.sh` 的使用说明.
- 文档要覆盖: 前置条件、默认行为、常用命令、参数解释、输出目录、重跑策略和常见问题.

## 阶段
- [ ] 阶段1: 回读脚本与旧文档, 提炼需要保留的真实行为
- [ ] 阶段2: 重写文档正文
- [ ] 阶段3: 用脚本帮助输出核对文档一致性
- [ ] 阶段4: 回填上下文并交付

## 状态
**目前在阶段2**
- 2026-03-11 08:13:10 UTC: 已确认用户希望文档只保留脚本用法, 不再保留手动 COLMAP 步骤. 准备整页重写.

## 进度更新
- 2026-03-11 08:15:20 UTC: 已将 `docs/s01_3dgs_workflow.md` 整页重写为 `scripts/run_s01_fastgs.sh` 使用说明.
- 2026-03-11 08:15:20 UTC: 新文档不再展开手动 COLMAP 命令, 只保留脚本的:
  - 前置条件
  - 默认行为
  - 常用命令
  - 参数解释
  - 输出目录
  - 重跑策略
  - 常见问题
- 2026-03-11 08:15:20 UTC: 已完成一致性核对:
  - `bash scripts/run_s01_fastgs.sh --help`
  - 固定字符串核对 `--phase prepare` / `--camera-model` / `-r, --resolution` / `--overwrite` 均已出现在新文档中.

## 当前待办
- [x] 阶段1: 回读脚本与旧文档, 提炼需要保留的真实行为
- [x] 阶段2: 重写文档正文
- [x] 阶段3: 用脚本帮助输出核对文档一致性
- [x] 阶段4: 回填上下文并交付

## 状态
**目前已完成**
- 2026-03-11 08:15:20 UTC: `docs/s01_3dgs_workflow.md` 已改写为纯脚本使用说明.

cat <<'EOF' >> WORKLOG.md

## [2026-03-11 08:15:20 UTC] 任务名称: 将 `docs/s01_3dgs_workflow.md` 改写为脚本使用说明

### 任务内容
- 清空旧的手动 COLMAP 流程型文档.
- 将 `docs/s01_3dgs_workflow.md` 改写为纯粹围绕 `scripts/run_s01_fastgs.sh` 的使用手册.

### 完成过程
- 回读 `scripts/run_s01_fastgs.sh` 当前真实行为, 把默认路径、`--phase`、`--camera-model`、`-r/--resolution`、`--frame-step`、`--frame-limit`、`--overwrite` 等参数整理成文档结构.
- 重写了文档正文, 用“最常用命令 -> 关键参数 -> 常见工作流 -> 输出目录 -> 常见问题”的顺序组织内容.
- 去掉了旧文档中大段手动 COLMAP 命令, 避免后续用户在脚本已经稳定可用的情况下继续走手工流程.
- 最后对照 `bash scripts/run_s01_fastgs.sh --help` 做一致性核对, 确认文档里的参数名和脚本当前实现一致.

### 总结感悟
- 当脚本已经稳定可复用时, 最有价值的文档通常不是“完整展开内部细节”, 而是把脚本怎么用、什么时候重跑、哪些参数最关键讲清楚.
- 文档一旦转成“脚本手册”, 后续维护成本会明显低于“手动命令教程”, 因为变化点更集中, 更容易跟着脚本一起更新.


---

# 任务计划: 补充 fastgs 参数文档默认值

## 目标
- 在 `docs/fastgs-train-scripts.md` 中为关键训练参数补充明确的默认值说明.
- 让读者不查代码也能知道“脚本值”和“仓库默认值”的区别.

## 阶段
- [ ] 阶段1: 回读上下文与现有文档
- [ ] 阶段2: 核对代码中的真实默认值
- [ ] 阶段3: 更新文档并自检
- [ ] 阶段4: 回填上下文并交付

## 关键问题
1. 当前文档里哪些参数还没有写默认值?
2. 这些默认值在当前代码里是否有变化?
3. 需要如何表述才能避免把“脚本推荐值”误写成“默认值”?

## 状态
**目前在阶段1**
- 2026-03-11 08:19:55 UTC: 收到补充默认值的要求,准备先回读文档与代码定义,再做定点更新.


## 进度更新

**目前在阶段4**
- 2026-03-11 08:21:47 UTC: 已在 `docs/fastgs-train-scripts.md` 新增“当前代码默认值速查”总表,并在各参数小节补齐默认值说明; 同时修正了插入新章节后失效的章节编号引用.

## 当前待办
- [x] 阶段1: 回读上下文与现有文档
- [x] 阶段2: 核对代码中的真实默认值
- [x] 阶段3: 更新文档并自检
- [x] 阶段4: 回填上下文并交付

## 状态
**目前已完成**
- 2026-03-11 08:21:47 UTC: `docs/fastgs-train-scripts.md` 已明确区分“代码默认值”和“脚本覆写值”.

---

# 任务计划: 为 `run_s01_fastgs.sh` 暴露 FastGS 常用训练参数

## 目标
- 将 `docs/fastgs-train-scripts.md` 中当前最常用、最有调参价值的一组训练参数接入 `scripts/run_s01_fastgs.sh`.
- 参数名尽量与 `train.py` 保持一致, 减少用户在脚本和训练代码之间切换时的心智负担.
- 同步更新 `docs/s01_3dgs_workflow.md`, 让脚本文档能看见这些新参数入口.

## 候选参数
- `--densification_interval`
- `--loss_thresh`
- `--grad_thresh`
- `--grad_abs_thresh`
- `--highfeature_lr`
- `--lowfeature_lr`
- `--dense`
- `--mult`
- `--optimizer_type`

## 状态
**目前在阶段2**
- 2026-03-11 08:18:10 UTC: 已对照 `docs/fastgs-train-scripts.md`、`train_base.sh`、`train_big.sh` 与 `arguments/__init__.py`, 准备把这组高频训练参数接入脚本并同步文档.

## 进度更新
- 2026-03-11 08:37:20 UTC: 已将以下 FastGS 常用训练参数接入 `scripts/run_s01_fastgs.sh`:
  - `--densification_interval`
  - `--loss_thresh`
  - `--grad_thresh`
  - `--grad_abs_thresh`
  - `--highfeature_lr`
  - `--lowfeature_lr`
  - `--dense`
  - `--mult`
  - `--optimizer_type`
  - `--test_iterations`
- 2026-03-11 08:37:20 UTC: 这些参数当前直接按原名透传到 `train.py`, 默认值与 `arguments/__init__.py` / `train.py` 保持一致, 未额外改动仓库默认行为.
- 2026-03-11 08:37:20 UTC: 已同步更新文档:
  - `docs/s01_3dgs_workflow.md`
  - `docs/fastgs-train-scripts.md`
- 2026-03-11 08:37:20 UTC: 已完成验证:
  - `bash -n scripts/run_s01_fastgs.sh`
  - `bash scripts/run_s01_fastgs.sh --help`
  - 动态命令:
    - `bash scripts/run_s01_fastgs.sh --phase train --fastgs-root data/s01_fastgs --model-path output/s01_param_smoke_verify --iterations 10 --overwrite -r 4 --densification_interval 500 --loss_thresh 0.06 --grad_thresh 0.0003 --grad_abs_thresh 0.0008 --highfeature_lr 0.02 --lowfeature_lr 0.001 --dense 0.01 --mult 0.7 --optimizer_type default --test_iterations 12345`
  - 关键输出:
    - 脚本日志中已打印完整 `train.py` 启动命令, 包含全部新增参数
    - `Training complete.`

## 当前待办
- [x] 阶段1: 回读上下文与现有文档, 提炼需要保留的真实行为
- [x] 阶段2: 重写文档正文
- [x] 阶段3: 用脚本帮助输出核对文档一致性
- [x] 阶段4: 回填上下文并交付

## 状态
**目前已完成**
- 2026-03-11 08:37:20 UTC: `run_s01_fastgs.sh` 已支持 `docs/fastgs-train-scripts.md` 中常用的 FastGS 高级训练参数配置.

cat <<'EOF' >> notes.md

# 笔记: `run_s01_fastgs.sh` 已暴露 FastGS 高频训练参数

## 目标
- 让 `data/s01` 的一键脚本不只支持 `-r` 和 `--iterations`, 也能直接承接 `train_base.sh` / `train_big.sh` 的常见调参思路.

## 本次接入的参数
- `--densification_interval`
- `--loss_thresh`
- `--grad_thresh`
- `--grad_abs_thresh`
- `--highfeature_lr`
- `--lowfeature_lr`
- `--dense`
- `--mult`
- `--optimizer_type`
- `--test_iterations`

## 设计决定
- 参数名保持与 `train.py` 一致, 不额外发明脚本专用别名.
- 默认值与当前代码默认值一致:
  - `densification_interval=100`
  - `loss_thresh=0.1`
  - `grad_thresh=0.0002`
  - `grad_abs_thresh=0.0012`
  - `highfeature_lr=0.005`
  - `lowfeature_lr=0.0025`
  - `dense=0.001`
  - `mult=0.5`
  - `optimizer_type=default`
  - `test_iterations=30000`
- 这样做的好处是:
  - 脚本默认行为不变
  - 但用户需要调参时, 不必跳出脚本改成手写 `train.py`

## 验证
- 静态验证:
  - `bash -n scripts/run_s01_fastgs.sh`
  - `bash scripts/run_s01_fastgs.sh --help`
- 动态验证:
  - 用 `--phase train` 和已有 `data/s01_fastgs` 跑了一轮 10 iter 小训练
  - 启动日志里能看到完整 `train.py` 命令, 包含全部新增参数
  - 训练最终输出 `Training complete.`

## 文档同步
- `docs/s01_3dgs_workflow.md`
  - 新增脚本高级训练参数的用法示例与说明
- `docs/fastgs-train-scripts.md`
  - 补充说明这些参数已经可通过 `scripts/run_s01_fastgs.sh` 直接配置

---

# 任务计划: 从 `run_s01_fastgs.sh` 撤掉 `--test_iterations`

## 目标
- 将 `--test_iterations` 从 `scripts/run_s01_fastgs.sh` 的脚本接口中移除.
- 同步清理 `docs/s01_3dgs_workflow.md` 中“脚本支持该参数”的描述.
- 在 `docs/fastgs-train-scripts.md` 中保留该参数的原理说明,但明确脚本当前不暴露它.

## 状态
**目前已完成**
- 2026-03-11 08:39:20 UTC: 已从脚本中移除 `TEST_ITERATIONS` 默认值、帮助文本、透传、解析、校验和日志输出.
- 2026-03-11 08:39:20 UTC: 已同步修正文档:
  - `docs/s01_3dgs_workflow.md` 不再把 `--test_iterations` 列为脚本可配置参数
  - `docs/fastgs-train-scripts.md` 改为明确说明: 该参数当前由 `train.py` 支持, 但 `scripts/run_s01_fastgs.sh` 刻意不暴露
- 2026-03-11 08:39:20 UTC: 已完成验证:
  - `bash -n scripts/run_s01_fastgs.sh`
  - `bash scripts/run_s01_fastgs.sh --help | rg -F "test_iterations"` 无输出
  - `rg -F "test_iterations" docs/s01_3dgs_workflow.md scripts/run_s01_fastgs.sh` 无输出
