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
