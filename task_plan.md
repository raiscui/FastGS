# 任务计划: 判断指定目录能否直接生成 3DGS

## 目标
- 判断用户给出的目录 `/workspace/lyra/assets/demo/static/diffusion_output_generated_my` 是否已经满足当前 FastGS / 3DGS 流程的输入要求.
- 明确回答: 现在是否可以直接拿这个路径跑, 还是需要先整理目录 / 补前处理 / 修改脚本.
- 如果需要修改, 给出最正确的改法, 而不是先堆额外脚本.

## 两种方向
- 方案A(不惜代价,最佳): 让仓库脚本直接识别这类目录并一键走通 `COLMAP -> FastGS train`, 尽量减少用户手工整理数据.
- 方案B(先能用,后面再优雅): 不先改代码, 先判断这个目录能否通过现有 `convert.py` 或现有训练入口直接使用; 如果不能, 明确最小整理步骤和缺口.

## 阶段
- [ ] 阶段1: 回读上下文并续档 task_plan
- [ ] 阶段2: 检查用户目录结构
- [ ] 阶段3: 核对现有脚本输入约束
- [ ] 阶段4: 给出结论与是否需要改脚本

## 关键问题
1. 这个目录里装的是图片, 视频, 还是已经做过 COLMAP 的场景?
2. `train.py` / `scene` 读取数据时, 对目录结构的硬性要求是什么?
3. `convert.py` 当前支持哪些输入形态, 是否已经覆盖这条路径?
4. 如果不能直接跑, 缺的是“数据结构”还是“脚本能力”?

## 六文件摘要
- 任务目标(task_plan / WORKLOG):
  - 近期主要围绕 `convert.py`、COLMAP 预处理、`scripts/run_s01_fastgs.sh` 与 FastGS 训练入口做了多轮增强和验证.
- 关键决定(task_plan / EPIPHANY_LOG):
  - 对单机位视频或单套图片, 优先复用 `convert.py` 统一规范化到 `images/` + `sparse/0/`.
  - 对多机位目录, 现阶段更稳的是显式 COLMAP CLI 或专用脚本, 不应硬套 `convert.py` 的默认单相机假设.
- 关键发现(notes / EPIPHANY_LOG):
  - `convert.py` 已支持视频目录和递归 `rgb` 视频发现.
  - `convert.py` 默认仍偏向单相机输入.
  - FastGS 训练前真正需要的是 `images/` 和 `sparse/0/` 这类 COLMAP 产物, 不是任意图片目录.
- 实际变更(WORKLOG):
  - 已经为视频输入、`s01` 多机位流程、相机模型选择、脚本帮助和文档做过真实验证.
- 暂缓事项(LATER_PLANS):
  - 后续可考虑给 `convert.py` 增加更明确的多机位目录模式.
- 错误与根因(ERRORFIX):
  - 近期高频坑主要集中在 shell 引号、COLMAP 输入组织方式、以及把现象误判成训练问题.
- 重大风险(EPIPHANY_LOG):
  - 不同输入组织方式会直接改变 COLMAP 行为.
  - 不能把“像是可用的目录”直接等同于“训练入口一定能吃”.
- 可复用点候选:
  - 先验上, 新输入最好先核对目录真实结构, 再判断是改脚本还是整理数据.
  - 训练能不能直接跑, 关键不是文件名像不像, 而是是否已有 COLMAP 稀疏重建结果.
- 最适合写到哪里:
  - 当前暂无新的长期规则需要额外同步到 `AGENTS.md` / `docs/`.

## 状态
**目前在阶段2**
- 2026-03-14 08:30:52 UTC: 已完成六文件回读与旧 `task_plan.md` 续档.
- 2026-03-14 08:30:52 UTC: 接下来检查用户给定目录的真实结构, 再和 `convert.py` / `train.py` 的输入约束对照.

## 进度更新
- 2026-03-14 08:34:09 UTC: 已确认目标目录实际结构为 `0..5/{rgb,pose,intrinsics,latent}`.
- 2026-03-14 08:34:09 UTC: 动态验证显示 `convert.py` 会把这条路径识别为 `rgb_recursive` 视频目录,可发现 6 个 `rgb/*.mp4`.
- 2026-03-14 08:34:09 UTC: 同时确认该目录当前不存在 `sparse/`、`input/`、`transforms_train.json`, 因此 `train.py` 不能直接把这条原始路径当训练输入.
- 2026-03-14 08:34:09 UTC: 已核对源码:
  - `scene/__init__.py` 只接受 `sparse/`(COLMAP) 或 `transforms_train.json`(Blender)
  - `convert.py` 虽然能识别这类 `rgb` 视频目录, 但仍按 `--ImageReader.single_camera 1` 走 COLMAP,不会读取现有 `.npz` pose / intrinsics
- 2026-03-14 08:34:09 UTC: 当前结论已收敛:
  - 如果目标只是“从这个路径出发走现有两步流程”, 不一定要改脚本
  - 如果目标是“只给这条路径就一键直出 3DGS,并利用已有 pose/intrinsics”, 则需要补脚本或数据导入逻辑

## 当前待办
- [x] 阶段1: 回读上下文并续档 task_plan
- [x] 阶段2: 检查用户目录结构
- [x] 阶段3: 核对现有脚本输入约束
- [x] 阶段4: 给出结论与是否需要改脚本

## 状态
**目前已完成**
- 2026-03-14 08:34:09 UTC: 已完成“是否需要改脚本”的证据收集与结论整理, 下一步可按用户选择继续实现一键脚本或 direct importer.

---

# 任务计划: 为 `diffusion_output_generated_my` 落地 direct importer 最佳方案

## 目标
- 先读懂 `/workspace/lyra` 中这批 `rgb/mp4 + pose/npz + intrinsics/npz` 数据是如何生成的.
- 基于真实生成逻辑, 正确解释 `pose/intrinsics` 的语义, 再决定 FastGS 侧最稳妥的 direct importer 方案.
- 最终让用户可以只给这类路径, 直接生成可训练的 3DGS 数据, 并优先复用已有位姿/内参, 避免重复 COLMAP.

## 两种方向
- 方案A(不惜代价,最佳): 直接新增 importer, 把这类目录转换为 FastGS 可读的 synthetic 数据格式, 并补通用一键入口.
- 方案B(先能用,后面再优雅): 先做 wrapper, 自动执行 `convert.py -> train.py`, 暂时继续依赖 COLMAP, 后续再补 direct importer.

## 阶段
- [ ] 阶段1: 回读 lyra 数据生成链路
- [ ] 阶段2: 验证 `pose/intrinsics` 语义与坐标系
- [ ] 阶段3: 设计并实现 direct importer
- [ ] 阶段4: 用真实目录做最小动态验证并交付

## 关键问题
1. `/workspace/lyra` 里是哪段代码产出了 `pose/*.npz` 和 `intrinsics/*.npz`?
2. `pose` 是 camera-to-world 还是 world-to-camera? 坐标轴口径是否和当前 `readCamerasFromTransforms` 兼容?
3. `intrinsics` 的四元组是否稳定等于 `[fx, fy, cx, cy]`? 是否逐帧变化?
4. 这类目录是“多机位同步视频”, 还是“多条独立轨迹”? train/test 切分该怎么定?
5. direct importer 最适合直接生成 `transforms_train.json` / `transforms_test.json`, 还是应该生成 COLMAP 等价目录?

## 状态
**目前在阶段1**
- 2026-03-14 08:34:09 UTC: 用户明确选择“最佳方案”, 并要求先阅读 `/workspace/lyra` 里的数据生成逻辑, 再做正确导入实现.
- 2026-03-14 08:48:10 UTC: 已完成 Lyra 生成链路回读与 direct loader 第一版实现, 当前卡点不再是目录识别, 而是 Lyra 场景初始化点云位置.
- 2026-03-14 08:48:10 UTC: 当前主假设是“围绕原点的随机点云”不适合 object-centric 已知轨迹, 会让部分 zoom 视角首轮看不到任何点; 备选解释是局部坐标系方向仍有口径问题.
- 2026-03-14 08:48:10 UTC: 下一步先做最小验证, 用真实相机轨迹估计共同注视点, 检查失败相机对该注视点是否位于前方, 再决定初始化算法.
- 2026-03-14 08:55:39 UTC: 最小验证已完成, 当前主假设获得动态证据支持:
  - 失败相机 `dj-style_v4_f00071` 对原点的前向点积为负, 对共同注视点的前向点积为正.
  - 原点随机点云在该相机中 `front=0`, 共同注视点随机点云则有大量可见点.
- 2026-03-14 08:55:39 UTC: 当前将进入阶段3, 修改 Lyra 点云初始化逻辑, 并补缓存版本检查, 自动淘汰旧的错误 `points3d.ply`.

## 当前待办
- [x] 阶段1: 回读 lyra 数据生成链路
- [x] 阶段2: 验证 `pose/intrinsics` 语义与坐标系
- [ ] 阶段3: 设计并实现 direct importer
- [ ] 阶段4: 用真实目录做最小动态验证并交付
- 2026-03-14 09:05:22 UTC: 阶段3 已完成:
  - `scene/dataset_readers.py` 已改为为 Lyra 场景估计共同注视点.
  - 初始化点云不再围绕原点生成,而是围绕共享 focus 中心生成.
  - 新增 `points3d_metadata.json` 做缓存版本检查,旧错误缓存会自动重建.
- 2026-03-14 09:05:22 UTC: 阶段4 已完成:
  - `pixi run python -m py_compile scene/dataset_readers.py scene/__init__.py tests/test_lyra_generated_loader.py`
  - `pixi run python -m unittest discover -s tests -p 'test_lyra_generated_loader.py'`
  - `pixi run python train.py -s /workspace/lyra/assets/demo/static/diffusion_output_generated_my -m output/dj_style_direct_smoke_focus --iterations 10 --eval -r 8`
  - 真实 smoke train 已完整通过, 首轮 `cudaErrorInvalidConfiguration` 未再出现.

## 当前待办
- [x] 阶段1: 回读 lyra 数据生成链路
- [x] 阶段2: 验证 `pose/intrinsics` 语义与坐标系
- [x] 阶段3: 设计并实现 direct importer
- [x] 阶段4: 用真实目录做最小动态验证并交付

## 状态
**目前已完成**
- 2026-03-14 09:05:22 UTC: `diffusion_output_generated_my` 已能被 `train.py` 直接读取并进入 FastGS 训练.
- 2026-03-14 09:05:22 UTC: 当前 direct loader 会自动:
  - 识别 `view_id/{rgb,pose,intrinsics}` 根目录
  - 用 `ffmpeg` 缓存抽帧
  - 读取 Lyra 的 `c2w` pose 与 `[fx, fy, cx, cy]` intrinsics
  - 生成基于共同注视点的初始化点云

---

# 任务计划: 排查 `scripts/run_lyra_fastgs.sh` 训练结束后的 `unexpected EOF`

## 目标
- 确认 `scripts/run_lyra_fastgs.sh: line 473: unexpected EOF while looking for matching '"'` 的真实原因.
- 区分清楚: FastGS 训练本身是否已经成功, 以及失败是否只发生在 shell 脚本收尾阶段.
- 如果证据足够, 给出最小且正确的修复方案, 避免再出现同类引号错误.

## 两种方向
- 方案A(不惜代价,最佳): 找到具体未闭合引号的位置, 修正脚本, 再用静态语法检查和最小动态命令验证收尾路径.
- 方案B(先能用,后面再优雅): 先只给用户明确结论, 说明训练已完成, 报错来自脚本语法问题, 暂不改代码.

## 阶段
- [ ] 阶段1: 回读上下文并记录本次排查目标
- [ ] 阶段2: 复现并定位 shell 语法错误
- [ ] 阶段3: 分析错误是否影响训练产物
- [ ] 阶段4: 输出结论, 必要时修复并验证

## 关键问题
1. `unexpected EOF while looking for matching '"'` 是否就是未闭合双引号?
2. 真正出错的位置是不是正好在 line 473, 还是更早某一行的引号把解析拖到了文件尾?
3. 从日志看训练已经 `Training complete.`, 那这次失败是不是只发生在脚本后处理?
4. 如果修复, 最小验证应该走 `bash -n` 还是一段真实参数的 smoke run?

## 状态
**目前在阶段2**
- 2026-03-14 10:04:00 UTC: 已完成六文件回读.
- 2026-03-14 10:04:00 UTC: 下一步用 `bash -n` 与带行号源码一起定位未闭合双引号, 再判断是否需要改脚本.

## 进度更新
- 2026-03-14 10:08:00 UTC: 已完成最小静态验证:
  - `bash -n scripts/run_lyra_fastgs.sh` 当前返回成功, 没有复现语法错误.
  - 当前工作区中的 `scripts/run_lyra_fastgs.sh` 只有 451 行, 与用户报错里的 `line 473` 不一致.
  - 当前文件结尾已检查, 未发现额外隐藏片段或损坏的行尾.
- 2026-03-14 10:08:00 UTC: 已形成候选结论:
  - 训练日志里已经出现 `Training complete.`, 因此 FastGS 训练本体已经完成.
  - `unexpected EOF while looking for matching '"'` 属于 shell 未闭合双引号错误.
  - 结合“当前文件可过语法检查 + 行号对不上”, 更可能是用户当时执行的是旧版本或另一份更长的 `run_lyra_fastgs.sh`.

## 当前待办
- [x] 阶段1: 回读上下文并记录本次排查目标
- [x] 阶段2: 复现并定位 shell 语法错误
- [x] 阶段3: 分析错误是否影响训练产物
- [x] 阶段4: 输出结论, 必要时修复并验证

## 状态
**目前已完成**
- 2026-03-14 10:08:00 UTC: 已确认这次报错的性质是 shell 脚本语法问题, 不是 FastGS 训练失败.
- 2026-03-14 10:08:00 UTC: 当前工作区脚本未复现该错误, 因此若要继续修, 需要拿到用户当时实际执行的那份脚本内容或命令记录.
  - 自动淘汰旧版错误缓存

---

# 任务计划: VerseCrafter 双卡超分 + CUDA COLMAP + FastGS 专用脚本

## 目标
- 为 `/workspace/VerseCrafter/demo_data/my4` 这类 VerseCrafter 输出目录提供一条稳定的一键链路.
- 流程固定为 `FlashVSR 超分 -> CUDA COLMAP 解相机 -> FastGS 训练/评估`.
- 明确不复用 VerseCrafter 自带相机参数.
- 尽量利用双显卡, 重点放在超分分片并发与 COLMAP GPU index 透传.

## 两种方向
- 方案A(不惜代价,最佳): 修好并验证新的 VerseCrafter wrapper, 让用户直接用一个脚本覆盖 superres / prepare / train / evaluate / all.
- 方案B(先能用,后面再优雅): 只给拼装命令, 暂不保证新脚本全链路可复用.

## 阶段
- [ ] 阶段1: 回读上下文并确认 direct 路线当前不作为推荐方案
- [ ] 阶段2: 审核新 wrapper 与相关脚本的静态逻辑
- [ ] 阶段3: 修复脚本问题并补齐 GPU 透传细节
- [ ] 阶段4: 做 shell / Python 静态校验与最小 dry-run
- [ ] 阶段5: 给出最终命令和使用说明

## 关键问题
1. 新脚本是否真的完全绕开了 VerseCrafter 自带相机参数?
2. 双卡是否被合理利用在最耗时的超分与 COLMAP 阶段?
3. 新脚本的阶段切分是否和现有 `run_lyra_*` wrapper 兼容?
4. 当前仓库现实边界下, 哪些阶段仍然只能单卡执行?

## 状态
**目前在阶段2**
- 2026-03-23 14:53:58 UTC: 已根据历史验证结论确认, `my4` 当前不再推荐 direct 路线.
- 2026-03-23 14:53:58 UTC: 已回读 `task_plan.md`、`EPIPHANY_LOG.md`、`WORKLOG.md`、`LATER_PLANS.md`, 并重新阅读新加的 VerseCrafter wrapper 与 COLMAP 脚本入口.
- 2026-03-23 14:53:58 UTC: 下一步先完整检查 `scripts/run_versecrafter_flashvsr_fastgs.sh` 的剩余逻辑, 再做语法验证和必要修复.

---

# 任务计划: 为 Lyra direct loader 补一键训练脚本

## 目标
- 新增一个可直接启动 Lyra generated root 训练的脚本入口.
- 让用户不必手写 `pixi run python train.py ...` 长命令.
- 保持脚本风格与 `scripts/run_s01_fastgs.sh` 一致, 避免项目里出现两套完全不同的 CLI 习惯.

## 两种方向
- 方案A(不惜代价,最佳): 新增一个通用 `scripts/run_lyra_fastgs.sh`, 提供常用训练参数、路径规范化、覆盖保护和帮助文档.
- 方案B(先能用,后面再优雅): 只加一个最薄的固定命令脚本, 直接写死当前示例路径和几个默认参数.

## 阶段
- [ ] 阶段1: 回读已有脚本风格并确定接口
- [ ] 阶段2: 实现 Lyra 一键脚本
- [ ] 阶段3: 更新 README / specs
- [ ] 阶段4: 做脚本级静态与真实 smoke 验证

## 关键问题
1. 脚本是做“完全固定示例入口”, 还是做“可复用的 Lyra wrapper”?
2. 哪些训练参数值得暴露, 才不会把简单入口重新做复杂?
3. 是否需要脚本层做 `--overwrite` 保护和路径规范化?

## 状态
**目前在阶段1**
- 2026-03-14 09:13:18 UTC: 用户要求“补一个一键脚本”.
- 2026-03-14 09:13:18 UTC: 已回读 `scripts/run_s01_fastgs.sh` 与 README 当前入口说明, 下一步按现有脚本风格新增 Lyra wrapper.
- 2026-03-14 09:18:47 UTC: 阶段2 已完成:
  - 新增 `scripts/run_lyra_fastgs.sh`
  - 默认指向当前 Lyra 示例目录, 同时支持 `--source-path` 覆盖
  - 暴露常用训练参数, 并提供 `--overwrite` / `--no-eval`
- 2026-03-14 09:18:47 UTC: 阶段3 已完成:
  - README 已补充脚本入口
  - `specs/lyra_direct_loader.md` 已同步说明一键脚本

## 当前待办
- [x] 阶段1: 回读已有脚本风格并确定接口
- [x] 阶段2: 实现 Lyra 一键脚本
- [x] 阶段3: 更新 README / specs
- [ ] 阶段4: 做脚本级静态与真实 smoke 验证
- 2026-03-14 09:22:24 UTC: 阶段4 已完成:
  - `bash -n scripts/run_lyra_fastgs.sh`
  - `bash scripts/run_lyra_fastgs.sh --help`
  - `bash scripts/run_lyra_fastgs.sh --iterations 10 --model-path output/lyra_script_smoke --overwrite`
  - 真实 smoke 结果为 `Training complete.`

## 当前待办
- [x] 阶段1: 回读已有脚本风格并确定接口
- [x] 阶段2: 实现 Lyra 一键脚本
- [x] 阶段3: 更新 README / specs
- [x] 阶段4: 做脚本级静态与真实 smoke 验证

## 状态
**目前已完成**
- 2026-03-14 09:22:24 UTC: `scripts/run_lyra_fastgs.sh` 已落地并通过真实 Lyra 路径 smoke 验证.
- 2026-03-14 09:22:24 UTC: 当前用户可以直接运行:
  - `bash scripts/run_lyra_fastgs.sh`
  - 或用 `--source-path` / `--model-path` 覆盖路径与输出目录.

---

# 任务计划: 为 Lyra 一键脚本补评估阶段

## 目标
- 让现有 `scripts/run_lyra_fastgs.sh` 不只会训练, 还能一键执行渲染与指标计算.
- 优先改良现有脚本, 不再新增一份平行“评估专用”脚本.
- 保持 `train.py -> render.py -> metrics.py` 的口径一致, 尤其避免 render 阶段和训练阶段的 `mult` 不一致.

## 两种方向
- 方案A(不惜代价,最佳): 直接扩展 `scripts/run_lyra_fastgs.sh`, 支持 `train/render/metrics/evaluate/all` 五种阶段.
- 方案B(先能用,后面再优雅): 单独新增一个 `scripts/eval_lyra_fastgs.sh`, 仅包装 `render.py -> metrics.py`.

## 阶段
- [ ] 阶段1: 回读评估入口与现有脚本约束
- [ ] 阶段2: 扩展 Lyra 一键脚本的 phase 机制
- [ ] 阶段3: 更新 README / specs
- [ ] 阶段4: 用真实模型跑完整 evaluate 验证

## 关键问题
1. 是补新脚本, 还是改良 `run_lyra_fastgs.sh`?
2. `metrics.py` 依赖 test 集, 那么脚本需要怎样约束 `--eval`?
3. `render.py` 的 `--mult` 默认值会不会覆盖训练时保存的配置?

## 状态
**目前在阶段1**
- 2026-03-14 09:46:50 UTC: 用户要求继续补“评估一键脚本”.
- 2026-03-14 09:46:50 UTC: 已回读 `render.py`、`metrics.py`、`docs/fastgs-train-scripts.md` 与现有 Lyra wrapper.
- 2026-03-14 09:46:50 UTC: 当前决定采用方案A, 直接改良 `scripts/run_lyra_fastgs.sh`, 避免入口分裂.
- 2026-03-14 09:46:50 UTC: 额外发现:
  - `metrics.py` 只消费 `test/` 渲染结果.
  - `render.py` 的 CLI 默认 `--mult=0.5` 会覆盖 `cfg_args` 保存值, 评估脚本需要主动回读训练配置.
- 2026-03-14 09:54:08 UTC: 阶段2 已完成:
  - `scripts/run_lyra_fastgs.sh` 已支持 `--phase train|render|metrics|evaluate|all`
  - 新增 `--iteration`
  - render 阶段会在用户未显式传 `--mult` 时, 自动从 `cfg_args` 回读训练时的 `mult`
  - 新增按阶段生效的 `--overwrite`
- 2026-03-14 09:54:08 UTC: 阶段3 已完成:
  - `README.md` 已补充 `--phase evaluate` 用法
  - `specs/lyra_direct_loader.md` 已补脚本阶段说明
- 2026-03-14 09:54:08 UTC: 阶段4 已完成:
  - `bash -n scripts/run_lyra_fastgs.sh`
  - `bash scripts/run_lyra_fastgs.sh --help`
  - `bash scripts/run_lyra_fastgs.sh --phase evaluate --model-path output/lyra_script_smoke --overwrite`
  - 真实 evaluate 已完成并输出 SSIM / PSNR / LPIPS

## 当前待办
- [x] 阶段1: 回读评估入口与现有脚本约束
- [x] 阶段2: 扩展 Lyra 一键脚本的 phase 机制
- [x] 阶段3: 更新 README / specs
- [x] 阶段4: 用真实模型跑完整 evaluate 验证

## 状态
**目前已完成**
- 2026-03-14 09:54:08 UTC: `scripts/run_lyra_fastgs.sh` 已同时支持训练与评估阶段.
- 2026-03-14 09:54:08 UTC: 当前用户可直接运行:
  - `bash scripts/run_lyra_fastgs.sh --phase evaluate --model-path output/<run>`
  - `bash scripts/run_lyra_fastgs.sh --phase all --model-path output/<run> --overwrite`

---

# 任务计划: Lyra direct 与 COLMAP 传统流程对比评估

## 目标
- 新增一条“不使用 Lyra 自带 pose/intrinsics, 改走 COLMAP 传统流程”的脚本.
- 实际跑出两套可对比结果:
  - Lyra direct loader
  - COLMAP 传统流程
- 在相同 `-r 1`、完整训练与评估口径下, 给出谁更好的证据化结论.

## 两种方向
- 方案A(不惜代价,最佳): 新增 `run_lyra_colmap_fastgs.sh`, 负责 `convert.py -> train.py -> render.py -> metrics.py` 全链路.
- 方案B(先能用,后面再优雅): 临时手工命令跑 COLMAP 流程, 不先补专用脚本.

## 阶段
- [ ] 阶段1: 回读传统流程代码与现有约束
- [ ] 阶段2: 实现 COLMAP 传统流程脚本
- [ ] 阶段3: 跑 Lyra direct 与 COLMAP 两套完整训练评估
- [ ] 阶段4: 汇总结果并得出对比结论

## 关键问题
1. 传统流程是直接复用 `convert.py`, 还是手写一套 COLMAP 命令更稳?
2. COLMAP 相机模型默认该用 `OPENCV`, 还是沿用 synthetic 数据更稳的 `SIMPLE_PINHOLE`?
3. 两套方案怎样保证比较口径尽量一致?

## 状态
**目前在阶段1**
- 2026-03-14 10:07:20 UTC: 用户要求新增一条“不使用 Lyra 自带 pose/intrinsics”的 COLMAP 传统流程脚本, 并对比 direct 与 COLMAP 两套方案.
- 2026-03-14 10:07:20 UTC: 已回读 `convert.py`, 当前确认:
  - 它能直接识别 `0..5/rgb/*.mp4`
  - 可通过 `--video_path` 显式把 Lyra 根目录当视频源
  - 默认会把抽帧产物整理到 `source_path/input`, 再跑 COLMAP
- 2026-03-14 10:07:20 UTC: 下一步将先启动 Lyra direct 的长跑训练, 同时实现 COLMAP 传统流程脚本, 以缩短总等待时间.

- 2026-03-14 10:25:41 UTC: 阶段2 已完成:
  - `scripts/run_lyra_colmap_fastgs.sh` 已创建
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `bash scripts/run_lyra_colmap_fastgs.sh --help`
  - 已确认脚本默认只消费 `rgb/*.mp4`, 不读取 Lyra 自带 `pose/intrinsics`
- 2026-03-14 10:25:41 UTC: 阶段3 进行中:
  - `direct` 长任务会话 `26440` 已训练完成, 当前正在 render 635 个 test 视角
  - 目标命令:
    - `bash scripts/run_lyra_fastgs.sh --phase all -r 1 --model-path output/lyra_direct_r1_30000 --overwrite`
  - 下一步:
    - 回收 `output/lyra_direct_r1_30000/results.json`
    - 再执行 `bash scripts/run_lyra_colmap_fastgs.sh --phase all --model-path output/lyra_colmap_r1_30000 --overwrite`

## 当前待办
- [x] 阶段1: 回读传统流程代码与现有约束
- [x] 阶段2: 实现 COLMAP 传统流程脚本
- [x] 阶段3: 跑 Lyra direct 与 COLMAP 两套完整训练评估
- [x] 阶段4: 汇总结果并得出对比结论

- 2026-03-14 10:29:20 UTC: `direct` 侧结果已回收:
  - `output/lyra_direct_r1_30000/results.json`
  - `SSIM=0.9080439209938049`
  - `PSNR=28.884437561035156`
  - `LPIPS=0.16255009174346924`
  - `point_cloud/iteration_30000/point_cloud.ply` 顶点数 `75825`
- 2026-03-14 10:29:20 UTC: 当前阶段3 仍未完成, 因为还缺少 COLMAP 传统流程同口径结果.
- 2026-03-14 10:29:20 UTC: 下一步将启动:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase all -r 1 --model-path output/lyra_colmap_r1_30000 --overwrite`

- 2026-03-14 11:50:33 UTC: 用户要求停止当前过重的全量 `24 fps` COLMAP 传统流程, 改用“与 `scripts/run_lyra_colmap_fastgs.sh` 类似的方式”尽快拿到可评估结果.
- 2026-03-14 11:50:33 UTC: 已执行停止:
  - `kill 47119`
  - 被停止的旧任务是:
    - `bash scripts/run_lyra_colmap_fastgs.sh --phase all -r 1 --camera-model SIMPLE_PINHOLE --video-fps 24 --model-path output/lyra_colmap_r1_30000 --overwrite`
- 2026-03-14 11:50:33 UTC: 当前计划变更为:
  - 保留 `scripts/run_lyra_colmap_fastgs.sh` 这一套 wrapper 风格
  - 但改用更轻的抽帧口径重新做完整评估
  - 目标优先级从“最公平的全量对比”切换为“尽快得到一版传统 COLMAP 基线指标”
- 2026-03-14 11:52:00 UTC: 已启动新的快速 COLMAP 评估任务:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase all -r 1 --camera-model SIMPLE_PINHOLE --video-fps 4 --fastgs-root data/diffusion_output_generated_my_colmap_fastgs_quick --model-path output/lyra_colmap_r1_quick_eval --overwrite`
- 2026-03-14 11:55:18 UTC: 快速 COLMAP 路线前处理已成功跑通:
  - 抽帧后总图像数 `120`
  - `feature matching` 耗时约 `0.106` 分钟
  - `mapper` 成功保留重建
  - `image_undistorter` 读取到 `Reconstruction with 120 images and 19577 points`
  - `sparse/0/points3D.ply` 已生成
- 2026-03-14 11:55:18 UTC: 当前阶段3 仍在进行中, 但状态已从“COLMAP 前处理”切到“FastGS 训练”.
- 2026-03-14 11:58:30 UTC: 快速 COLMAP 路线已完成完整评估:
  - `output/lyra_colmap_r1_quick_eval/results.json`
  - `SSIM=0.9319607615470886`
  - `PSNR=30.28389549255371`
  - `LPIPS=0.13405002653598785`
  - `point_cloud/iteration_30000/point_cloud.ply` 顶点数 `67968`
- 2026-03-14 11:58:30 UTC: 对比结论已形成, 但要附带口径限制:
  - direct:
    - `train=635`, `test=91`
  - quick COLMAP:
    - `train=105`, `test=15`
  - 因此当前可交付的是“快速 COLMAP 基线结果”, 不是“严格同 test 集的最终胜负结论”.

## 状态
**目前已完成**
- 2026-03-14 11:58:30 UTC: 已完成一版 direct vs COLMAP 快速基线评估.
- 2026-03-14 11:58:30 UTC: 若后续还要做严格公平对比, 需要统一抽帧集合与 train/test 切分后再复跑.

---

# 任务计划: 回查 `/workspace/FlashVSR-Pro` 中的超分命令

## 目标
- 确认之前是否确实通过 `/workspace/FlashVSR-Pro` 做过视频超分.
- 找到当时实际使用的命令、脚本入口或可直接复现的调用方式.
- 区分清楚: 这是仓库里静态存在的推荐命令, 还是本机历史任务中真实执行过的命令.

## 两种方向
- 方案A(不惜代价,最佳): 同时回查 `FlashVSR-Pro` 的脚本、文档、git 记录与本仓库工作日志, 尽量还原出最接近“当时实际跑过”的命令.
- 方案B(先能用,后面再优雅): 先给出 `FlashVSR-Pro` 当前仓库中最明确的超分启动命令, 暂不继续追溯更深的运行历史.

## 阶段
- [ ] 阶段1: 回读上下文并记录新的排查目标
- [ ] 阶段2: 检查 `/workspace/FlashVSR-Pro` 的脚本和文档入口
- [ ] 阶段3: 回查 git / 日志 / 跨仓库引用中的真实命令证据
- [ ] 阶段4: 输出“现象 -> 假设 -> 验证 -> 结论”

## 关键问题
1. `FlashVSR-Pro` 仓库里有没有明确的视频超分入口脚本或 README 命令?
2. FastGS 这边之前的工作记录里, 有没有直接引用 `FlashVSR-Pro` 的输出目录或命令?
3. 能否找到“真实执行过”的命令, 还是只能找到“仓库当前推荐”的命令?

## 状态
**目前在阶段1**
- 2026-03-14 12:10:00 UTC: 用户明确指出“之前的超分是通过 `/workspace/FlashVSR-Pro` 做的”, 当前要先核对该仓库中的脚本/文档/历史记录, 再回答具体命令.
- 2026-03-14 12:16:00 UTC: 阶段2 已完成:
  - 已确认 `/workspace/FlashVSR-Pro` 的统一入口是 `infer.py`
  - README 示例命令为 `python infer.py -i ... -o ... --mode ...`
  - `lyra` 侧另有 `scripts/run_flashvsr_reference.py` 作为批处理 wrapper
- 2026-03-14 12:16:00 UTC: 阶段3 已完成:
  - 已从 `/workspace/lyra/outputs/flashvsr_reference/flashvsr_reference_summary.json` 与 `flashvsr_full.log` 取到真实执行过的命令
  - 已确认当时至少一条真实命令为:
    - `/workspace/lyra/.pixi/envs/default/bin/python3 infer.py -i /workspace/lyra/assets/demo/static/diffusion_output_generated/1/rgb/00172.mp4 -o /workspace/lyra/outputs/flashvsr_reference/full_scale2x/1/rgb/00172.mp4 --mode full --scale 2.0 --dtype bf16 --quality 10`

## 当前待办
- [x] 阶段1: 回读上下文并记录新的排查目标
- [x] 阶段2: 检查 `/workspace/FlashVSR-Pro` 的脚本和文档入口
- [x] 阶段3: 回查 git / 日志 / 跨仓库引用中的真实命令证据
- [x] 阶段4: 输出“现象 -> 假设 -> 验证 -> 结论”

## 状态
**目前已完成**
- 2026-03-14 12:16:00 UTC: 已拿到 `/workspace/FlashVSR-Pro` 相关超分命令的静态与动态证据.
- 2026-03-14 12:16:00 UTC: 当前可以同时回答:
  - 底层真实跑过的 `infer.py` 命令
  - 更上层的 `run_flashvsr_reference.py` 包装命令
- 2026-03-14 12:20:00 UTC: 已补做当前机器环境验证:
  - `/workspace/lyra/.pixi/envs/default/bin/python3` 仍存在
  - `/usr/local/miniconda3/envs/flashvsr/bin/python3` 当前不存在
  - `FlashVSR-Pro` 所需模型文件仍存在
  - 在显式 `LD_LIBRARY_PATH` 与 `PYTHONPATH` 下, `infer.py --help` 与 `scripts/run_flashvsr_reference.py --help` 当前都返回成功

---

# 任务计划: 在 FastGS 侧固化 FlashVSR 一键脚本

## 目标
- 在 `FastGS/scripts` 下新增一个可直接触发 `FlashVSR-Pro` 超分参考生成的一键脚本.
- 默认参数对齐当前机器真实可用环境, 避免再依赖已经失效的旧 `miniconda` 路径.
- 保持脚本风格与现有 `run_lyra_fastgs.sh` / `run_lyra_colmap_fastgs.sh` 一致.

## 两种方向
- 方案A(不惜代价,最佳): 新增通用 wrapper, 同时支持 local / docker runner, 并把常用 `FlashVSR` 参数都暴露出来.
- 方案B(先能用,后面再优雅): 只做当前机器可用的 local runner 脚本, 先把整批 `full_scale2x` 参考生成跑通.

## 阶段
- [ ] 阶段1: 回读现有脚本风格并确定 CLI
- [ ] 阶段2: 实现 FastGS 侧 wrapper
- [ ] 阶段3: 做静态与最小动态验证
- [ ] 阶段4: 同步必要文档与六文件记录

## 关键问题
1. 脚本名应该落成什么, 才不会和现有 direct / colmap 路线混淆?
2. 默认值应该偏向“历史真实参考生成口径”, 还是偏向当前用户最近使用的 `_my` 数据路径?
3. 是否需要同时兼容 `local` 与 `docker` 两种 runner?

## 状态
**目前在阶段1**
- 2026-03-14 12:24:00 UTC: 已回读 `scripts/run_lyra_fastgs.sh`、`scripts/run_lyra_colmap_fastgs.sh` 与 `lyra/scripts/run_flashvsr_reference.py`.
- 2026-03-14 12:24:00 UTC: 当前决定采用方案A:
  - 新增 FastGS 侧 bash wrapper
  - 默认走当前机器可用的 `local` runner
  - 但保留 `--runner docker` 等透传能力, 避免后续又需要重做一版脚本

## 进度更新
- 2026-03-14 12:28:00 UTC: 阶段2 已完成:
  - 已新增 `scripts/run_lyra_flashvsr_reference.sh`
  - 已封装 `lyra` / `FlashVSR-Pro` 路径、`PYTHONPATH`、`LD_LIBRARY_PATH` 与常用 `FlashVSR` 参数
- 2026-03-14 12:28:00 UTC: 阶段3 已完成:
  - `bash -n scripts/run_lyra_flashvsr_reference.sh`
  - `bash scripts/run_lyra_flashvsr_reference.sh --help`
  - `bash scripts/run_lyra_flashvsr_reference.sh --view-ids 5 --scene-stem 00172 --dry-run --output-root /tmp/flashvsr_reference_dryrun_fastgs_verify`
  - dry-run 已成功落盘 manifest 与 summary
- 2026-03-14 12:36:00 UTC: 追加真实动态验证:
  - `bash scripts/run_lyra_flashvsr_reference.sh --view-ids 5 --scene-stem 00172 --output-root /tmp/flashvsr_reference_actual_fastgs_verify --overwrite`
  - 已真实生成:
    - `/tmp/flashvsr_reference_actual_fastgs_verify/full_scale2x/5/rgb/00172.mp4`
    - `/tmp/flashvsr_reference_actual_fastgs_verify/full_scale2x/5/manifests/00172.json`
    - `/tmp/flashvsr_reference_actual_fastgs_verify/flashvsr_reference_summary.json`
- 2026-03-14 12:28:00 UTC: 阶段4 已完成:
  - 已将实现与验证过程追加写入 `notes.md` 与 `WORKLOG.md`
  - 当前无需额外修改 `ERRORFIX.md`, 因为这次属于功能脚本新增, 不是生产 bug 修复

## 当前待办
- [x] 阶段1: 回读现有脚本风格并确定 CLI
- [x] 阶段2: 实现 FastGS 侧 wrapper
- [x] 阶段3: 做静态与最小动态验证
- [x] 阶段4: 同步必要文档与六文件记录

## 状态
**目前已完成**
- 2026-03-14 12:28:00 UTC: FastGS 侧的一键 `FlashVSR` wrapper 已落地并通过 dry-run 验证.
- 2026-03-14 12:28:00 UTC: 下一步如果用户需要, 可以直接用这个脚本发起真实整批 SR 生成, 或再继续补一个“SR -> COLMAP/FastGS” 串联入口.

---

# 任务计划: 串联 `FlashVSR -> FastGS` 并支持长中文文件名

## 目标
- 新增一个真正的一键入口, 能把 `FlashVSR-Pro` 超分结果继续送入 FastGS.
- 同时支持:
  - `direct` 路线: 复用 Lyra 自带 `pose/intrinsics`
  - `colmap` 路线: 完全不读 `pose/intrinsics`
- 支持直接传单个 `.mp4` 文件路径, 包括带空格、中文、逗号的长文件名.

## 两种方向
- 方案A(不惜代价,最佳): 让 wrapper 支持 `--source-video`, 自动反推 `input-root + scene-stem + view-ids`, 再串联 `FlashVSR -> prepare SR root -> direct/COLMAP`.
- 方案B(先能用,后面再优雅): 只支持 `--input-root + --scene-stem`, 通过正确引用来兼容长文件名, 暂不做自动推导.

## 阶段
- [ ] 阶段1: 核对 `xhc` 目录真实结构与自动推导可行性
- [ ] 阶段2: 扩展 `run_lyra_flashvsr_reference.sh` 支持 `--source-video`
- [ ] 阶段3: 新增串联脚本并打通 direct / colmap 两条路径
- [ ] 阶段4: 用含中文长文件名的真实路径做验证
- [ ] 阶段5: 同步 README / specs / 六文件

## 关键问题
1. 单个 `.mp4` 路径能否稳定反推出 Lyra root、scene stem 和全部相关 view ids?
2. SR 之后的训练输入应不应该复制整套数据, 还是构造一个 symlink root 更稳?
3. direct 与 colmap 两条后续路线, 哪些参数可以统一暴露, 哪些需要分支处理?

## 状态
**目前在阶段1**
- 2026-03-14 12:40:00 UTC: 已确认 `/workspace/lyra/assets/demo/static/diffusion_output_generated_xhc` 下 6 个视角都共享同一个长中文 `scene_stem`.
- 2026-03-14 12:40:00 UTC: 当前决定采用方案A:
  - 直接支持 `--source-video`
  - 自动推导 root / scene_stem / view_ids
  - SR 后构造一个可被 direct / colmap 两侧共同消费的 symlink root

## 进度更新
- 2026-03-14 12:44:00 UTC: 已重新回读 `run_lyra_flashvsr_reference.sh`、`run_lyra_flashvsr_fastgs.sh`、`run_lyra_fastgs.sh`、`run_lyra_colmap_fastgs.sh` 与六文件尾部.
- 2026-03-14 12:44:00 UTC: 当前观察到的现象是:
  - 串联脚本主体已经写完
  - `phase prepare` 的 direct / colmap 语义已初步分开
  - 但还缺完整静态与动态验证, 暂时不能把它当成已完成交付
- 2026-03-14 12:44:00 UTC: 下一步先做两个最小验证:
  - `bash -n` 与 `--help`
  - 长文件名场景下的 `--phase superres` / `--phase prepare`
- 2026-03-14 12:47:00 UTC: 最小动态验证新增证据:
  - `bash -n` 与 `--help` 已通过
  - 长文件名 `--phase superres --dry-run` 已通过
  - 真实 `--phase prepare --view-ids 0` 首次失败于 shell 自身:
    - `scripts/run_lyra_flashvsr_fastgs.sh: line 761: DRY_RUN: unbound variable`
  - 当前结论:
    - 失败点发生在参数校验阶段
    - 还没进入超分和 SR root 准备
    - 这是脚本变量初始化缺失, 不是长文件名兼容性问题

## 当前待办
- [x] 阶段1: 核对 `xhc` 目录真实结构与自动推导可行性
- [x] 阶段2: 扩展 `run_lyra_flashvsr_reference.sh` 支持 `--source-video`
- [x] 阶段3: 新增串联脚本并打通 direct / colmap 两条路径
- [x] 阶段4: 用含中文长文件名的真实路径做验证
- [x] 阶段5: 同步 README / specs / 六文件

## 进度更新
- 2026-03-14 16:26:00 UTC: 已修复 `run_lyra_flashvsr_fastgs.sh` 中 `DRY_RUN` 未初始化导致的 `set -u` 失败.
- 2026-03-14 16:26:00 UTC: 已补齐 `--fallback-tile-size` 与 `--fallback-overlap` 的下游透传.
- 2026-03-14 16:31:00 UTC: 长文件名真实 `phase prepare` 已通过:
  - 成功生成 `/tmp/flashvsr_xhc_prepare_actual/full_scale2x/0/rgb/<长文件名>.mp4`
  - 成功生成 `/workspace/FastGS/data/flashvsr_xhc_prepare_actual_root/0/{rgb,pose,intrinsics}`
- 2026-03-14 16:32:00 UTC: 长文件名 direct 最小训练已通过:
  - `--phase train --iterations 1 -r 8 --no-eval`
  - 训练日志出现 `Found Lyra generated multi-view root` 与 `Training complete.`
- 2026-03-14 16:34:00 UTC: 已同步 `specs/lyra_direct_loader.md`:
  - 补充 `run_lyra_flashvsr_reference.sh`
  - 补充 `run_lyra_flashvsr_fastgs.sh`
  - 补充 `FlashVSR -> FastGS` 阶段语义说明

## 状态
**目前已完成**
- 2026-03-14 16:34:00 UTC: 用户要求的“支持 `FlashVSR-Pro` 串联, 且兼容长中文 `.mp4` 文件名”已完成并拿到动态证据.
- 2026-03-14 16:34:00 UTC: 当前仍未做完整动态验证的是 `--pipeline colmap` 全链路训练, 但 direct 路线已经真实跑通到训练阶段.
- 2026-03-14 17:45:00 UTC: `--pipeline colmap` 的失败根因已被确认并修复:
  - 现象:
    - `UnicodeDecodeError` 出现在 `read_extrinsics_binary`
  - 主假设:
    - `images.bin` 中的 UTF-8 中文文件名被按单字节逐个解码
  - 备选解释:
    - 文本回退分支也可能被带空格文件名拆坏
  - 验证:
    - 新增 `tests/test_colmap_loader.py`
    - `pixi run python -m unittest tests.test_colmap_loader` 通过
    - 真实数据 `pixi run python train.py -s /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_flashvsr_colmap_fps12_unicode_smoke --iterations 1 -r 8 --eval` 通过
    - 真实 wrapper `bash scripts/run_lyra_flashvsr_fastgs.sh --source-video "<xhc长路径>" --phase train --pipeline colmap --video-fps 12 --fastgs-root /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 --model-path /workspace/FastGS/output/xhc_flashvsr_colmap_fps12_wrapper_smoke --iterations 1 -r 8 --overwrite` 通过

## 进度更新
- 2026-03-14 17:45:00 UTC: 用户在真实 `--pipeline colmap` 训练阶段提供了新的动态失败证据:
  - `train.py` 已成功进入 `readColmapSceneInfo(...)`
  - 失败发生在 `scene/colmap_loader.py::read_extrinsics_binary`
  - 报错为:
    - `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xe6 in position 0: unexpected end of data`
- 2026-03-14 17:45:00 UTC: 当前主假设是:
  - `images.bin` 中的图像名包含中文 UTF-8 多字节字符
  - 现有解析器按单字节逐个 `decode("utf-8")`, 导致多字节字符被拆坏
- 2026-03-14 17:45:00 UTC: 最强备选解释是:
  - 即便二进制读取修好, 文本回退分支 `read_extrinsics_text(...)` 也仍可能因为 `split()` 无法处理带空格文件名而失败
- 2026-03-14 17:45:00 UTC: 下一步先修复 `scene/colmap_loader.py` 的二进制与文本图像名解析, 再用用户这套 `xhc_flashvsr_colmap_fps12` 真实数据重试最小训练入口.

---

# 任务计划: 修复 `convert.py` 在多 COLMAP 子模型场景下固定选错 `sparse/0`

## 目标
- 确认 `/workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12` 训练首轮 `cudaErrorInvalidConfiguration` 的真实原因.
- 若根因是 `convert.py` 固定选择了错误的 COLMAP 子模型, 则修复为自动选择最佳 sparse model.
- 保证修复后, 同类数据不会再因为 `sparse/0` 只有极少点云而在训练首轮崩溃.

## 两种方向
- 方案A(不惜代价,最佳): 在 `convert.py` 中自动分析 `distorted/sparse/*` 所有子模型,按“注册图像数优先,点数次优先”选择最佳模型再做 undistort.
- 方案B(先能用,后面再优雅): 不改代码,只手动把 `distorted/sparse/2` 复制成 `sparse/0`,并告知用户以后手动挑模型.

## 阶段
- [ ] 阶段1: 回读上下文并记录现象 / 假设 / 验证计划
- [ ] 阶段2: 验证是否存在“更好的 sparse 子模型”
- [ ] 阶段3: 修改 `convert.py` 自动选择最佳子模型
- [ ] 阶段4: 补回归测试与动态验证
- [ ] 阶段5: 回写六文件并交付

## 关键问题
1. 当前失败到底是 CUDA kernel 自身问题, 还是训练输入只剩极小点云?
2. `mapper` 是否产出了多个 sparse 子模型, 而脚本错误地固定选了 `0`?
3. “最佳子模型”应该按什么规则选, 才不会引入新的特殊情况?
4. 修复后, 是否能用真实 `xhc_bai` 数据把 `Number of points at initialisation` 从 `2` 恢复到正常量级?

## 状态
**目前在阶段2**
- 2026-03-15 06:12:00 UTC: 已完成六文件回读, 发现历史上存在另一类 `cudaErrorInvalidConfiguration`, 但那次是 direct loader 初始化点云错误, 与本次 `xhc_bai` 日志不一致.
- 2026-03-15 06:12:00 UTC: 当前观察到的现象是:
  - 失败日志显示 `Reading camera 4/4`
  - `Number of points at initialisation : 2`
  - `output/xhc_bai_flashvsr_colmap_fps12/input.ply` 只有 283 字节
- 2026-03-15 06:12:00 UTC: 当前主假设是:
  - `convert.py` 把 `image_undistorter` 的输入硬编码为 `distorted/sparse/0`
  - 但当前数据的最佳模型不是 `0`, 导致训练吃到只有 4 张注册图、2 个点的劣质模型
- 2026-03-15 06:12:00 UTC: 最强备选解释是:
  - 这批素材本身就无法得到稳定 COLMAP 重建, 即使切到别的子模型也仍会失败
- 2026-03-15 06:12:00 UTC: 下一步先做最小可证伪实验:
  - 统计 `distorted/sparse/*` 各子模型的注册图像数与点数
  - 再手动让 undistorter 走最佳子模型, 用 1 iter 训练验证是否立即恢复

## 进度更新
- 2026-03-15 06:16:00 UTC: 最小验证已经给出动态证据:
  - `distorted/sparse/0`: `Registered images=4`, `Points=2`
  - `distorted/sparse/1`: `Registered images=15`, `Points=2581`
  - `distorted/sparse/2`: `Registered images=360`, `Points=92946`
- 2026-03-15 06:16:00 UTC: 已手动执行:
  - `colmap image_undistorter --input_path .../distorted/sparse/2`
  - 再用该结果执行 `pixi run python train.py ... --iterations 1 -r 8 --eval`
- 2026-03-15 06:16:00 UTC: 动态验证结果:
  - 训练日志恢复为 `Reading camera 360/360`
  - `Number of points at initialisation : 92946`
  - `Training complete.`
- 2026-03-15 06:16:00 UTC: 当前结论:
  - 上一条“素材本身不可训练”的备选解释被推翻
  - 本次首轮 CUDA 崩溃的根因是 `convert.py` 固定选择 `distorted/sparse/0`, 误用了最差子模型

## 当前待办
- [x] 阶段1: 回读上下文并记录现象 / 假设 / 验证计划
- [x] 阶段2: 验证是否存在“更好的 sparse 子模型”
- [ ] 阶段3: 修改 `convert.py` 自动选择最佳子模型
- [ ] 阶段4: 补回归测试与动态验证
- [ ] 阶段5: 回写六文件并交付

## 进度更新
- 2026-03-15 06:20:00 UTC: 阶段3 已完成:
  - `convert.py` 新增多子模型统计与选择逻辑
  - 不再硬编码 `distorted/sparse/0`
  - 当前默认按 `registered_images -> points -> cameras` 排序选择最佳模型
- 2026-03-15 06:20:00 UTC: 阶段4 已完成:
  - `pixi run python -m py_compile convert.py tests/test_convert.py`
  - `pixi run python -m unittest tests.test_convert`
  - `pixi run python convert.py --skip_matching -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12_convert_fix_verify`
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12_convert_fix_verify -i images -m /workspace/FastGS/output/xhc_bai_convert_fix_verify_smoke --iterations 1 -r 8 --eval`
- 2026-03-15 06:20:00 UTC: 关键验证结果:
  - `convert.py` 日志明确选择 `sparse/2`
  - 真实转换后训练日志恢复为 `Reading camera 360/360`
  - `Number of points at initialisation : 92946`
  - `Training complete.`

## 当前待办
- [x] 阶段1: 回读上下文并记录现象 / 假设 / 验证计划
- [x] 阶段2: 验证是否存在“更好的 sparse 子模型”
- [x] 阶段3: 修改 `convert.py` 自动选择最佳子模型
- [x] 阶段4: 补回归测试与动态验证
- [x] 阶段5: 回写六文件并交付

## 状态
**目前已完成**
- 2026-03-15 06:20:00 UTC: `xhc_bai_flashvsr_colmap_fps12` 这类“COLMAP 产出多个 sparse 子模型”的场景, 当前已经不会再默认误选最差的 `sparse/0`.
- 2026-03-15 06:20:00 UTC: 这次问题的已验证结论是:
  - 现象: 首轮训练只读到 `4/4` 相机和 `2` 个点
  - 根因: `convert.py` 固定使用 `distorted/sparse/0`
  - 修复: 自动选择最佳子模型再做 undistort
  - 结果: 真实 `xhc_bai` smoke train 已恢复通过

## 进度更新
- 2026-03-15 06:23:00 UTC: 已把真实故障目录 `/workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12` 就地修复:
  - 旧坏产物已备份为:
    - `images_bad_20260315_0625`
    - `sparse_bad_20260315_0625`
  - 保留原 `distorted/` 结果, 用新 `convert.py --skip_matching` 重新生成了正确的 `images/` 与 `sparse/0/`
- 2026-03-15 06:23:00 UTC: 真实源目录再验证:
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_bai_flashvsr_colmap_fps12_fixed_smoke --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Reading camera 360/360`
    - `Number of points at initialisation : 92946`
    - `Training complete.`
- 2026-03-15 06:24:00 UTC: 原始报错模型输出路径也已复跑通过:
  - `pixi run python train.py -s /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12 -i images -m /workspace/FastGS/output/xhc_bai_flashvsr_colmap_fps12 --iterations 1 -r 8 --eval`
  - 关键输出:
    - `Reading camera 360/360`
    - `Number of points at initialisation : 92946`
    - `Training complete.`

---

# 任务计划: 为 VerseCrafter `my4` 提供“先超分再 FastGS 生成 3DGS”的合适命令

## 目标
- 基于 `/workspace/VerseCrafter/demo_data/my4` 的 12 路视频, 给出一套真实可执行的命令.
- 优先选择“质量最高且与现有仓库最匹配”的路线.
- 明确区分已观察到的事实、当前推断和最终建议.

## 阶段
- [x] 阶段1: 回读六文件与现有脚本, 确认 FastGS 可用入口
- [x] 阶段2: 检查 `my4` 真实目录结构与相机数据形状
- [ ] 阶段3: 判断应走 direct 还是 colmap
- [ ] 阶段4: 做一次最小 dry-run 验证命令拼装
- [ ] 阶段5: 汇总最终命令与注意事项

## 关键问题
1. `my4` 是否已经是 FastGS 可直接消费的 Lyra 风格根目录?
2. VerseCrafter 的 `custom_camera_trajectory.npz` 语义是否与 FastGS direct loader 兼容?
3. “最高质量”在当前仓库里, 应优先理解为复用已知相机轨迹, 还是重跑 COLMAP?

## 状态
**目前在阶段3**
- 2026-03-23 00:00:00 UTC: 已观察到的事实:
  - `/workspace/VerseCrafter/demo_data/my4` 下存在 `0..11` 共 12 个视角目录.
  - 每个视角目录都包含 `generated_videos/generated_video_0.mp4`.
  - 每个视角目录都包含 `custom_camera_trajectory.npz`, 其中 `extrinsics.shape == (81, 4, 4)`.
  - 共享目录存在 `shared/estimated_depth/depth_intrinsics.npz`, 其中 `intrinsic.shape == (3, 3)`.
  - FastGS 现成 direct loader 需要的是 `view_id/{rgb,pose,intrinsics}` 结构, 并要求:
    - `pose/*.npz` 含 `data:[T,4,4]` 与 `inds:[T]`
    - `intrinsics/*.npz` 含 `data:[T,4]` 与 `inds:[T]`
- 2026-03-23 00:00:00 UTC: 当前主假设:
  - VerseCrafter 导出的相机轨迹与共享内参, 经过一次轻量格式转换后, 可以直接走 FastGS direct 路线.
  - 对“最高质量”目标, 复用 VerseCrafter 已知轨迹通常比让 COLMAP 从生成视频里重新估计更稳.
- 2026-03-23 00:00:00 UTC: 最强备选解释:
  - 如果 VerseCrafter 的 `extrinsics` 坐标语义与 FastGS 不一致, 或 direct 路线对这类数据存在隐藏不兼容, 则应退回 `--pipeline colmap`.
- 2026-03-23 00:00:00 UTC: 下一步:
  - 读取 VerseCrafter 导出代码, 确认 `extrinsics` 是否为 `c2w`.
  - 用临时转换根目录做一次 `--phase superres --dry-run` 验证命令拼装是否成立.

## 进度更新
- 2026-03-23 00:00:00 UTC: 阶段3 已完成:
  - 已读取 `/workspace/VerseCrafter/blender_addon/operators.py`
  - 其中导出逻辑明确把 `cam_obj.matrix_world` 作为 `camera-to-world in Blender` 写入 `custom_camera_trajectory.npz`
  - 这与 FastGS direct loader 所需 `c2w` 语义一致
- 2026-03-23 00:00:00 UTC: 阶段4 已完成:
  - 已将真实 `my4` 数据临时转换为 `/tmp/versecrafter_my4_fastgs_input`
  - 执行:
    - `bash /workspace/FastGS/scripts/run_lyra_flashvsr_fastgs.sh --source-path /tmp/versecrafter_my4_fastgs_input --phase superres --pipeline direct --scene-stem generated_video_0 --view-ids 0,1,2,3,4,5,6,7,8,9,10,11 --flashvsr-output-root /tmp/versecrafter_my4_flashvsr --prepared-root /tmp/versecrafter_my4_prepared --model-path /tmp/versecrafter_my4_model --mode full --scale 2.0 --dtype bf16 --quality 10 --dry-run`
  - 动态输出确认:
    - wrapper 识别到 `12` 个视频
    - 每个视角都成功拼出了 `full_scale2x/<view_id>/rgb/generated_video_0.mp4`
    - summary 路径已正常生成

## 当前待办
- [x] 阶段1: 回读六文件与现有脚本, 确认 FastGS 可用入口
- [x] 阶段2: 检查 `my4` 真实目录结构与相机数据形状
- [x] 阶段3: 判断应走 direct 还是 colmap
- [x] 阶段4: 做一次最小 dry-run 验证命令拼装
- [x] 阶段5: 汇总最终命令与注意事项

## 状态
**目前已完成**
- 2026-03-23 00:00:00 UTC: 当前建议的已验证结论是:
  - 现象:
    - `my4` 原始目录不是 FastGS 现成支持的输入结构
    - 但它已经包含 12 路视频、逐帧相机轨迹和共享内参
  - 判断:
    - 先做一次轻量格式转换, 再走 `FlashVSR -> FastGS direct`, 比重跑 COLMAP 更符合“最高质量”目标
  - 动态证据:
    - 转换后的临时根目录已通过 `superres dry-run`
    - wrapper 已确认会处理 12 个视频

## 进度更新
- 2026-03-23 00:00:00 UTC: 上一条“优先推荐 direct 路线”的主假设已被新动态证据推翻.
  - 推翻证据:
    - `CUDA_VISIBLE_DEVICES=0 pixi run python train.py -s /tmp/versecrafter_my4_fastgs_input -m /tmp/versecrafter_my4_direct_smoke --iterations 1 -r 8 --eval`
    - 关键输出先后出现:
      - `Found Lyra generated multi-view root, loading direct pose/intrinsics inputs!`
      - `Generating focus-centered point cloud (100000) for Lyra generated scene`
      - `Loading Training Cameras`
      - `Loading Test Cameras`
      - `Number of points at initialisation :  100000`
    - 但随后首轮 backward 失败:
      - `torch.AcceleratorError: CUDA error: invalid configuration argument`
- 2026-03-23 00:00:00 UTC: 回滚后的当前结论:
  - 已验证成立的部分:
    - VerseCrafter -> Lyra 风格目录转换是通的
    - wrapper 能识别 12 个视频
    - direct loader 能成功读取转换后的 `pose/intrinsics`
  - 尚未验证通过的部分:
    - 这批 VerseCrafter 数据直接走 FastGS direct 训练的稳定性
  - 因此对用户当前“先超分再生成 3DGS”的需求, 最稳妥推荐应改为:
    - 先做同样的轻量目录转换
    - 再走 `scripts/run_lyra_flashvsr_fastgs.sh --pipeline colmap`

---

# 任务计划: 新增 VerseCrafter 一键脚本, 内置转换并强制走 CUDA COLMAP

## 目标
- 新增一个脚本, 直接接受 `/workspace/VerseCrafter/demo_data/my4` 这类 VerseCrafter 输出目录.
- 脚本内部完成“VerseCrafter -> Lyra 风格 bridge root”的转换.
- 后续强制调用 `scripts/run_lyra_flashvsr_fastgs.sh --pipeline colmap`, 不复用 VerseCrafter 自带相机参数做训练.
- 尽量利用双显卡, 至少让超分阶段能明确拿到两张卡的可见性或进行双卡分摊.

## 阶段
- [x] 阶段1: 回读现有 FastGS / VerseCrafter 入口与历史结论
- [ ] 阶段2: 确认 FlashVSR 双卡利用方式
- [ ] 阶段3: 设计新脚本参数与 bridge root 生成策略
- [ ] 阶段4: 实现新脚本
- [ ] 阶段5: 做 dry-run 与最小动态验证
- [ ] 阶段6: 回写文档与六文件

## 关键问题
1. 新脚本是否应彻底禁止 `direct`, 避免用户误用 VerseCrafter 自带相机?
2. FlashVSR 当前能否原生吃满双卡, 还是需要新脚本自己做双卡并发调度?
3. bridge root 里的 `pose/intrinsics` 应该保留真实值、写占位值, 还是完全另起流程避开这套约束?

## 状态
**目前在阶段2**
- 2026-03-23 00:00:00 UTC: 用户新增明确约束:
  - “不要他这里的相机参数”
  - “要 cuda colmap 算出来的”
  - “要利用好双显卡”
- 2026-03-23 00:00:00 UTC: 当前主假设:
  - 新脚本应强制只支持 `colmap` 路线
  - VerseCrafter 自带 `custom_camera_trajectory.npz` 不再作为训练输入语义使用
  - 只在 bridge root 层面满足现有 wrapper 的目录完整性约束
- 2026-03-23 00:00:00 UTC: 最强备选解释:
  - 如果 FlashVSR 本体已经支持在单任务内自动使用多卡, 新脚本只需要正确设置 GPU 可见性
  - 如果它没有, 则需要在脚本层把视频任务拆成两组并行跑

## 进度更新
- 2026-03-23 15:03:08 UTC: 阶段2-4 已完成:
  - `scripts/run_versecrafter_flashvsr_fastgs.sh` 已完成静态检查
  - `scripts/run_lyra_colmap_fastgs.sh` 与 `convert.py` 已完成静态检查
  - `--phase superres --dry-run --overwrite` 已在真实 `my4` 上通过
  - 已确认 12 个视频会按 `gpu=0` / `gpu=1` 分成两组 shard
- 2026-03-23 15:03:08 UTC: 已修复两个真实脚本问题:
  - 默认 `ffmpeg` 命令名被误当成相对路径归一化
  - `train` 阶段在已有 `FASTGS_ROOT` 时, 仍不必要地强依赖 `PREPARED_ROOT`
- 2026-03-23 15:03:08 UTC: 已补充新的运行期保护:
  - local FlashVSR runner 现在会在真正开跑前逐卡预检 `torch.cuda.is_available()`
  - 如果某张卡当前不可用, 脚本会在分片前直接失败并报明是哪张卡
- 2026-03-23 15:03:08 UTC: 最小真实验证给出了新的环境结论:
  - `gpu=0` 在 Lyra / FastGS 的 torch 环境下可用
  - `gpu=1` 在 Lyra / FastGS 的 torch 环境下不可用
  - `COLMAP --SiftExtraction.gpu_index 1` 也会报 `Cannot set device to 1`, 并回退到 device 0

## 当前待办
- [x] 阶段1: 回读现有 FastGS / VerseCrafter 入口与历史结论
- [x] 阶段2: 确认 FlashVSR 双卡利用方式
- [x] 阶段3: 设计新脚本参数与 bridge root 生成策略
- [x] 阶段4: 实现新脚本
- [x] 阶段5: 做 dry-run 与最小动态验证
- [x] 阶段6: 回写文档与六文件

## 状态
**目前已完成**
- 2026-03-23 15:03:08 UTC: VerseCrafter 专用 wrapper 已可用, 并且固定走:
  - `FlashVSR -> CUDA COLMAP -> FastGS`
  - 不复用 VerseCrafter 自带相机参数
- 2026-03-23 15:03:08 UTC: 当前“不能马上吃满双卡”的限制已经被动态证据收敛为环境问题, 不是 wrapper 接线问题:
  - `gpu0` 可用
  - `gpu1` 对 torch / COLMAP 当前不可用

## 进度更新
- 2026-03-23 15:10:00 UTC: 用户继续追问“为什么只能用 0, 明明有两张卡”.
- 2026-03-23 15:10:00 UTC: 当前进入新的最小环境排障子任务:
  - 不再停留在“脚本预检失败”表面
  - 继续确认到底是:
    - 驱动 / CUDA 初始化问题
    - `/dev/nvidia*` 设备权限或 cgroup 放行问题
    - 还是 GPU1 本身处于异常状态
- 2026-03-23 15:10:00 UTC: 下一步会先采集:
  - `torch.cuda.init()` 的具体异常
  - `/dev/nvidia*` 设备节点与主次设备号
  - `nvidia-smi -q` 中与 GPU1 相关的状态字段
- 2026-03-23 15:36:50 UTC: 环境排障第一轮已完成:
  - `nvidia-smi -L` 确认物理上确实有 2 张 A800
  - `/dev/nvidia0` 和 `/dev/nvidia1` 设备节点都存在, 且权限不是主要矛盾
  - `CUDA_VISIBLE_DEVICES=1` 下, `torch.cuda.init()` 明确报:
    - `RuntimeError: No CUDA GPUs are available`
  - `COLMAP --SiftExtraction.gpu_index 1` 也不能真正选中 GPU1
  - `nvidia-smi -q` 还显示:
    - GPU0 `MIG Mode: Enabled`
    - GPU1 `MIG Mode: Disabled`
- 2026-03-23 15:36:50 UTC: 当前已确认的结论是“CUDA 运行时当前无法初始化 GPU1”.
  - 但“为什么不能初始化”的最终根因仍在候选阶段.
  - 当前最可疑候选是:
    - GPU0/GPU1 的 MIG 配置不一致
  - 最强备选解释是:
    - 容器 / cgroup / 驱动层的设备可见性异常

---

# 任务计划: 收编 `run_versecrafter_flashvsr_fastgs.sh` 依赖的 lyra 子脚本

## 目标
- 把 VerseCrafter wrapper 现在依赖的 lyra 子脚本迁回 FastGS 仓库内, 为后续删除 `../lyra` 做准备.

## 阶段
- [ ] 阶段1: 识别当前 lyra 子脚本与调用契约
- [ ] 阶段2: 把必要脚本迁入 FastGS 并改本地引用
- [ ] 阶段3: 做 shell 静态校验与最小运行验证

## 状态
**目前在阶段1**
- 2026-03-23 16:15:49 UTC: 已完成六文件回读, 接下来先精确定位 `scripts/run_versecrafter_flashvsr_fastgs.sh` 依赖的 lyra 子脚本与参数接口.
## 进度更新
- 2026-03-23 16:31:22 UTC: 阶段1-3 已完成:
  - 已把 `run_flashvsr_reference.py` 与实现库收编到 FastGS 本仓库.
  - `run_lyra_flashvsr_reference.sh` 与 `run_versecrafter_flashvsr_fastgs.sh` 已改为调用本地 Python 入口, 不再依赖 `../lyra/scripts/run_flashvsr_reference.py`.
  - `pixi.toml` / `environment.yml` 已补 `imageio` 与 `pillow`, 并新增 `test_flashvsr_reference.py` 回归测试.
## 状态
**目前已完成**
- 2026-03-23 16:31:22 UTC: 已通过 `bash -n`, `pixi run python -m unittest discover -s tests -p 'test_flashvsr_reference.py'`, 以及 VerseCrafter `--phase superres --dry-run` 烟雾验证.
