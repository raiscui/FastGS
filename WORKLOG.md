## [2026-03-27 17:55:35] [Session ID: 28616] 任务名称: 支持 `my5` 多镜头视频目录走 `COLMAP -> FastGS`

### 任务内容
- 让现有 `COLMAP -> FastGS` 脚本真正支持 `/root/autodl-fs/my5` 这种多镜头生成视频目录.
- 保持训练口径向 `cmd.md` 中 `my4_mask_guarded_v4` 靠齐, 尤其是 mask 训练入口和正式训练参数链路.

### 完成过程
- 先回读主线六文件, 因为默认上下文文件超过 1000 行, 先执行了续档与持续学习:
  - 归档主线旧 `task_plan.md`、`notes.md`、`WORKLOG.md`
  - 新增 `EXPERIENCE.md`
  - 在 `AGENTS.md` 补长期知识索引
- 然后定位 `my5` 与旧 `rgb/*.mp4` 布局的真实差异:
  - `generated_videos/generated_video_0.mp4`
  - `rendering_4D_maps/merged_mask.mp4`
  - 以及一批不该喂给 COLMAP 的辅助视频
- 接着完成代码改造:
  - `convert.py`
    - 优先发现 `generated_videos`
    - 自动把 `merged_mask.mp4` 配成同名 mask 帧
    - 为 COLMAP 3.x / 4.x 动态选择 GPU 选项名
  - `scripts/run_lyra_colmap_fastgs.sh`
    - 自动优先读取 `<fastgs-root>/masks`
    - 默认 CUDA COLMAP 路径失效时回退到 PATH `colmap`
  - `tests/test_convert.py`
    - 新增 3 条回归测试
- 最后用真实 `my5` 数据启动 `prepare`, 已确认:
  - 抽出了 `972` 张训练图
  - 抽出了 `972` 张 mask
  - 已进入 COLMAP `feature_extractor` 与 `exhaustive_matcher`

### 总结感悟
- 对这类多镜头生成视频目录, 真正危险的不是“视频太多”, 而是“辅助视频和 RGB 视频混在一起, 但文件扩展名都一样”.
- 最稳的修法不是再造一条新 pipeline, 而是把现有 `convert.py` 的发现规则和抽帧规则补到足够懂业务语义.

### 当前运行态
- COLMAP prepare 正在后台继续跑:
  - 已完成 `feature_extractor`
  - 当前在 `exhaustive_matcher`
- 训练接力也已启动:
  - 一旦 `sparse/0` 产出
  - 自动开始 `output/my5_mask_guarded_v1` 的正式 FastGS 训练

## [2026-03-27 10:27:38] [Session ID: 80800] 任务名称: 回滚 `merged_mask.mp4` 的错误训练 mask 语义并接上 `my5` 首轮无 mask 训练

### 任务内容
- 修正 `my5` 场景里 `rendering_4D_maps/merged_mask.mp4` 的使用口径.
- 保留已经在跑的 COLMAP prepare, 同时避免后续 FastGS 训练误吃深度辅助 mask.

### 完成过程
- 回读了当前主线记录、`cmd.md`、相关代码与真实后台状态.
- 确认 `prepare` 仍在 `exhaustive_matcher`, 因此错误尚未污染训练结果.
- 修改代码:
  - `convert.py`
    - 撤掉 `merged_mask.mp4 -> masks/` 的默认接线
  - `scene/dataset_readers.py`
    - 自动 mask 探测改为“目录存在且非空”才启用
  - `scripts/run_lyra_colmap_fastgs.sh`
    - 同步收紧自动 mask 识别条件, 并修正文案
  - `tests/test_convert.py`
    - 改成验证 `merged_mask.mp4` 不再介入训练抽帧计划
  - `tests/test_mask_loading.py`
    - 新增空 `masks/` 不自动启用的回归测试
- 完成验证:
  - `python3 -m py_compile convert.py scene/dataset_readers.py`
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`
  - `pixi run python -m unittest tests.test_convert tests.test_mask_loading`
- 完成运行态处理:
  - 把 `data/my5_colmap_fastgs/masks` 挪到 `depth_masks_from_merged_mask_20260327_102621`
  - 保留 `972` 张深度辅助 mask 帧供后续深度链路参考
  - 新启动无 mask 训练等待器 `96836`, 等 `prepare` 完成后自动起 `output/my5_nomask_v1`

### 总结感悟
- 这次真正该修的不是“mask 缺不缺”, 而是“输入语义有没有被误分类”.
- 对自动发现类入口, 宁可少接一条语义不确定的默认行为, 也不要把不同任务的中间产物共用到同一个 `masks/` 约定里.

## [2026-03-27 12:16:04] [Session ID: 80800] 任务名称: 将 `my5` 图量降到 1/3 并重启 `COLMAP -> FastGS`

### 任务内容
- 按用户要求把 `my5` 从 `972` 张图降到约 `324` 张.
- 在不改变其余训练参数口径的前提下, 重启 prepare 与后续训练接力.

### 完成过程
- 先根据当前输入统计换算出新的抽帧率:
  - `16 / 3 = 5.333333333333 fps`
- 然后用真实单视角视频做了最小验证:
  - `count=27`
- 接着停掉了旧的 prepare 与训练等待器.
- 在重启时额外暴露了一个真实脚本问题:
  - `--overwrite` 在符号链接工作目录下会把受控目录误判成非受控路径
  - 根因是脚本顶部使用 `pwd` 而不是 `pwd -P`
- 修完后已重新启动:
  - 新 prepare 会话 `23869`
  - 新训练等待器 `53980`
- 当前新 prepare 已经推进到:
  - `feature_extractor` 完成 `324/324`
  - `feature matching` 开始, 当前见到 `Processing block [1/7, 1/7]`

### 总结感悟
- 对“图量缩放”这种需求, 最稳的做法不是拍脑袋改整数间隔, 而是先用一条真实视频验证目标抽帧率对应的最终帧数.
- 这次顺手修掉的 `pwd` / `pwd -P` 差异, 属于很典型的“符号链接路径与真实路径口径不一致”问题, 后面继续用 `--overwrite` 时也会更稳.

## [2026-03-27 21:59:20] [Session ID: 245310] 任务名称: 修复 `my5` resume 的 `tmp_radii` 崩溃并续训到 `30000`

### 任务内容
- 定位 `my5` 从 `ckpt_20000.pth` 续训时在 `21000` 收尾阶段崩溃的问题.
- 修复 resume 路径, 并把 `output/my5_nomask_v1` 从 `21000` 推到 `30000`.

### 完成过程
- 先回读主线上下文和真实训练日志, 确认 `ckpt_21000.pth` 已成功生成.
- 再把错误从“随机 CUDA”收敛到稳定的 Python 层异常:
  - `AttributeError: 'GaussianModel' object has no attribute 'tmp_radii'`
- 静态阅读后确认:
  - `tmp_radii` 只在 densify/prune 内部临时使用
  - `capture()` 不保存它
  - `prune_points()` 却默认它存在
- 代码修复:
  - 在 `scene/gaussian_model.py` 中为 `tmp_radii` 增加默认初始化
  - 在 `training_setup()` 中显式重置为 `None`
  - 新增 `tests/test_gaussian_model_resume.py` 回归测试
- 完成验证:
  - `python3 -m py_compile scene/gaussian_model.py tests/test_gaussian_model_resume.py`
  - `pixi run python -m unittest tests.test_convert tests.test_mask_loading tests.test_gaussian_model_resume`
  - 真实动态复验 `20000 -> 21000`
  - guarded 续训 `21000 -> 30000`

### 总结感悟
- 这次真正的问题不是 checkpoint 少存了多少权重, 而是“瞬时运行态字段没有明确生命周期”.
- 对 resume 敏感的代码, 如果某个字段不进 checkpoint, 那它就必须有稳定的默认值和重置时机.

## [2026-03-27 14:37:06 UTC] [Session ID: 277426] 任务名称: 使用 `GITHUB_TOKEN` 推送 `main`

### 任务内容
- 将本地 `main` 上已经存在的提交 `122ba55` 推送到 `origin/main`.
- 明确区分“已提交内容”和“工作区未提交改动”, 避免误判哪些内容会进入远端.

### 完成过程
- 先确认了仓库状态:
  - `main` 比 `origin/main` 超前 `1` 个提交
  - 当前仓库没有子模块指针需要一并同步
- 首轮直接 push 失败后, 没有把“无效 token”当成已确认结论, 而是继续做最小证伪:
  - 先排除了远端公开连通性问题
  - 再用 Python 直接构造 GitHub API 请求, 避免 shell 引号继续污染认证头
- 关键动态证据是:
  - `GITHUB_TOKEN` 末尾带有隐藏的 `\\r`
  - 去掉 `\\r\\n` 后, GitHub API 返回:
    - `LOGIN=raiscui`
    - `PERMISSIONS={"admin": true, "maintain": true, "pull": true, "push": true, "triage": true}`
- 随后使用 clean token 在无代理、禁用 helper 的模式下执行 push:
  - `git push origin HEAD:main`
  - 返回 `ebe06ac..122ba55  HEAD -> main`
- 最后再次校验远端:
  - `refs/heads/main = 122ba55e3ebec97f70ab27c098a88e3441c26ac8`

### 总结感悟
- 这次最值钱的不是“把 push 按出来”, 而是把失败从“凭感觉像权限问题”收敛成了真实可验证的环境变量格式问题.
- 以后只要看到 token 明明像真的, 但 GitHub 又报 `Invalid username or token`, 应优先检查是否混入了 `\\r` / `\\n`, 不要急着重置权限或换 token.

## [2026-03-27 22:36:10] [Session ID: 245310] 任务名称: 导出 `my5_nomask_v1` 的 `30000` 轮渲染视频

### 任务内容
- 为 `output/my5_nomask_v1` 导出可直接查看的 train/test mp4 视频.

### 完成过程
- 复用 `scripts/run_lyra_colmap_fastgs.sh` 现有的 `render.py + ffmpeg` 链路.
- 执行 `--phase render --video-iterations 30000 --video-sets both`.
- 成功生成:
  - `videos/train_iter30000.mp4`
  - `videos/test_iter30000.mp4`

### 总结感悟
- 现有 wrapper 已经覆盖了“渲染帧 + 合成 mp4”的完整链路.
- 后续同类导视频需求, 直接复用这条入口即可, 不需要额外手写 ffmpeg 命令.

## [2026-03-27 22:39:20] [Session ID: 245310] 任务名称: 评估 `my5_nomask_v1` 的 `30000` 轮 test 指标

### 任务内容
- 对 `output/my5_nomask_v1` 当前 `30000` 轮渲染结果做正式 test 评估.

### 完成过程
- 复用 `scripts/run_lyra_colmap_fastgs.sh --phase metrics`.
- 成功跑完 `41` 张 test 图的 `SSIM / PSNR / LPIPS` 计算.
- 结果文件已落盘:
  - `results.json`
  - `per_view.json`

### 总结感悟
- 现在 `my5_nomask_v1` 已经同时具备:
  - 训练完成状态
  - 可视化视频
  - 正式 test 指标
- 后续调优可以直接围绕这组结果做增量对比, 不需要再回到“先补齐评估链路”的阶段.

## [2026-03-27 22:46:48] [Session ID: 019d2ea0-a35d-7a12-b8e9-9ebec510ea80] 任务名称: 将 `my5_nomask_v1` 扩到 `35000` 并完成正式评估

### 任务内容
- 按用户给定的 `35000` 轮调参口径, 在 `my5_nomask_v1` 现有 `30000` checkpoint 基础上继续训练.
- 对 `35000` 轮执行正式 render + metrics, 并与 `30000` 基线做对比.

### 完成过程
- 先核对 guarded 续训日志和输出目录, 确认以下产物都已经落盘:
  - `checkpoints/ckpt_35000.pth`
  - `point_cloud/iteration_35000/point_cloud.ply`
- 再执行正式评估命令:
  - `bash scripts/run_lyra_colmap_fastgs.sh --phase evaluate --model-path /root/autodl-tmp/home/rais/FastGS/output/my5_nomask_v1 --iteration 35000 --overwrite`
- 评估链路完整跑通:
  - train render `283` 张
  - test render `41` 张
  - metrics 成功写回 `results.json` 与 `per_view.json`
- 最终平均指标:
  - `PSNR 27.2039413`
  - `SSIM 0.8910136`
  - `LPIPS 0.2026276`
- 相比 `30000` 基线:
  - `PSNR +0.0402832`
  - `SSIM +0.0004694`
  - `LPIPS -0.0006576`

### 总结感悟
- 这轮从 `30000` 拉到 `35000` 是有效的, 但收益已经明显进入“小幅增益区”.
- 如果后面继续调优, 更值得把注意力放到固定的 worst-view 上, 看它们更像位姿问题、素材问题, 还是训练超参数问题.

## [2026-03-28 02:24:00 UTC] [Session ID: 79642ac4-ccdf-404a-967b-1342f85cc2bd] 任务名称: 补做 `my5` 的朝向连续性与邻机位相对位姿复核

### 任务内容
- 在上一轮 `my5` pose 回查的基础上, 再补一层“相机朝向有没有抖”的硬证据.
- 继续判断 `view 7 / 5 / 8` 里, 哪些更像真实 pose 连续性问题, 哪些更像材质 / 反射难点.

### 完成过程
- 先回读主线 `task_plan.md`、`notes.md`、`WORKLOG.md` 和上一轮位姿报告.
- 然后新增了可复用分析脚本:
  - `scripts/analyze_colmap_pose_continuity.py`
- 脚本会直接读取:
  - `data/my5_colmap_fastgs/sparse/0/images.bin`
  - 计算 `camera-to-world` 朝向
  - 输出:
    - 邻帧 `rotation_step`
    - 邻帧 `forward_step`
    - 邻帧 `up_step`
    - 相邻机位 `relative pose delta`
- 动态验证里顺手修掉了 2 个真实入口问题:
  - `scripts/` 目录直接运行时的 repo root 导入路径
  - `import scene.colmap_loader` 会被 `scene/__init__.py` 连带拖入训练依赖的问题
  - 最终改成按文件路径直接加载 `scene/colmap_loader.py`
- 正式跑完分析后, 已生成:
  - `specs/my5_pose_continuity_report_assets/pose_continuity_data.json`
  - `specs/my5_pose_continuity_report_assets/orientation_global_scatter.png`
  - `specs/my5_pose_continuity_report_assets/focus_view_orientation_diagnostics.png`
  - `specs/my5_pose_continuity_report_assets/neighbor_relative_pose_diagnostics.png`
  - `specs/my5_pose_continuity_report_assets/focus_view_forward_quiver.png`
- 最后写出正式报告:
  - `specs/my5_pose_continuity_report_20260328.md`
  - 并用 `beautiful-mermaid-rs --ascii` 验证了报告中的 2 个 mermaid 图语法

### 总结感悟
- 这轮最值钱的新增, 不是再多看一张图, 而是把“相机中心跳不跳”扩成了“相机到底往哪看, 相对邻机位怎么变”.
- 当前 `view 7` 的问题已经不只靠主观观感或单一指标支撑, 而是形成了:
  - worst-view
  - 点支持
  - 平移轨迹
  - 朝向连续性
  - 邻机位相对位姿
  这 5 层证据链.

## [2026-03-28 02:49:00 UTC] [Session ID: 7f1d2edd-4a39-4aee-b0fd-79f9701c57e7] 任务名称: 对 `view 6 / 7 / 8 + frame 1~8` 做局部 COLMAP 对照实验

### 任务内容
- 验证 `view 7` 前段不稳定, 是否主要是全局重建上下文带来的副作用.
- 用最小局部子集和全局同批帧做直接对照.

### 完成过程
- 先回读了:
  - `task_plan.md`
  - `notes.md`
  - `WORKLOG.md`
  - `LATER_PLANS.md`
  - `EPIPHANY_LOG.md`
- 然后确认全局重建口径:
  - 单相机
  - `SIMPLE_PINHOLE`
  - 全局 focal `592.1701`
- 接着准备了 `24` 张局部图像子集:
  - `view 6 / 7 / 8`
  - `frame 1 ~ 8`
- 实际跑了 2 版局部 COLMAP:
  - `local_fix`
    - 固定全局内参
  - `local_refine`
    - 允许 focal refine
- 两版都真实跑完了:
  - `feature_extractor`
  - `exhaustive_matcher`
  - `mapper`
- 然后又复用:
  - `scripts/analyze_colmap_pose_continuity.py`
  对两版局部模型做同口径轨迹和朝向分析
- 最后额外生成了聚合对照资产:
  - `specs/my5_local_colmap_compare_assets/comparison_summary.json`
  - `specs/my5_local_colmap_compare_assets/view7_global_vs_local_compare.png`
  - `specs/my5_local_colmap_compare_assets/pair_global_vs_local_compare.png`
- 正式报告落盘:
  - `specs/my5_local_colmap_compare_20260328.md`
  - 并用 `beautiful-mermaid-rs` 校验了文内 mermaid 图

### 总结感悟
- 这轮最关键的不是“局部能不能建起来”, 而是“建起来以后有没有把问题真正修顺”.
- 当前答案是:
  - 没有.
- 这让我们可以更稳地收窄方向:
  - 不是继续盲缩局部 COLMAP 窗口
  - 而是更应该去做筛帧对照, 或者扩大上下文而不是继续缩小

## [2026-03-27 22:57:30] [Session ID: 019d2ea0-a35d-7a12-b8e9-9ebec510ea80] 任务名称: 产出 `my5_nomask_v1` 的 worst-view 定位报告

### 任务内容
- 围绕 `ours_35000` 的最差 test 视角做定位.
- 给出图像证据, 再判断更像材质难点还是位姿问题.

### 完成过程
- 先从 `per_view.json` 抽取 worst 5:
  - `00031 / 00033 / 00037 / 00024 / 00026`
- 再映射到 `cameras.json`, 找到原始图名与机位:
  - 问题主要集中在 `view 7 / 5 / 8`
- 然后核查同机位时间邻帧覆盖:
  - worst 5 都能找到前后 `1` 帧的 train 邻帧
- 再生成 GT / Render / AbsDiff 三联图和总览图:
  - `specs/my5_worst_view_report_assets/*.png`
- 最后整理成正式报告:
  - `specs/my5_worst_view_report_20260327.md`
  - 并用 `beautiful-mermaid-rs` 校验了文内 mermaid 图表语法

### 总结感悟
- 当前 worst views 的模式已经足够集中, 值得从“机位级问题”往下查, 不该再只盯平均 PSNR.
- 更稳的下一步不是继续堆迭代数, 而是先核对 `view 7 / 5 / 8` 的 COLMAP 位姿与相邻 train 渲染表现.

## [2026-03-28 01:48:27 UTC] [Session ID: 019d2fcd-edfd-7032-be9f-42f8bc79198c] 任务名称: 导出 `my5_nomask_v1` 的 `35000` 轮视频

### 任务内容
- 为 `output/my5_nomask_v1` 导出 `35000` 轮的 train/test mp4 视频.
- 沿用仓库已有 wrapper 的导出链路, 保持与之前 `30000` 视频一致的目录和参数口径.

### 完成过程
- 先核对现状:
  - `ckpt_35000.pth` 已存在
  - `train/ours_35000/renders` 已存在
  - `test/ours_35000/renders` 已存在
  - 但 `videos/train_iter35000.mp4` 与 `videos/test_iter35000.mp4` 还不存在
- 随后执行:
  - `timeout 20m bash scripts/run_lyra_colmap_fastgs.sh --phase render --model-path output/my5_nomask_v1 --video-iterations 35000 --video-sets both`
- 脚本成功完成:
  - 重渲染 `35000` 的 train/test 结果
  - 调用 `ffmpeg` 合成两个 mp4
- 最后用 `ffprobe` 做动态验证:
  - 两个视频均为 `h264`
  - 分辨率都是 `1280x720`
  - 帧率都是 `24 fps`

### 总结感悟
- 这条 wrapper 已经覆盖“重渲染 + 合成视频 + 命名规范”的完整流程.
- 后续同类需求, 直接替换 `--video-iterations` 就可以继续复用, 不需要临时拼命令.

## [2026-03-28 00:10:40] [Session ID: 019d2ea0-a35d-7a12-b8e9-9ebec510ea80] 任务名称: 回查 `my5` 的 COLMAP 位姿轨迹并产出报告

### 任务内容
- 沿着 worst-view 结果继续往下查, 判断 `view 7 / 5 / 8` 是否存在 COLMAP 位姿异常证据.

### 完成过程
- 复用了 `scene/colmap_loader.py` 的二进制读取逻辑, 直接读取:
  - `data/my5_colmap_fastgs/sparse/0/images.bin`
- 统计了每个机位的:
  - 相机中心轨迹
  - 连续帧位移
  - 每图 observed 3D points
  - observed ratio
- 关键发现:
  - `view 7` 是最强异常点:
    - `obs_mean` 最低
    - `ratio_mean` 最低
    - `step_mean` 最高
    - `step_max` 最高
  - `view 5` 是次级可疑点
  - `view 8` 虽然出现在 worst-view, 但轨迹证据更偏正常
- 产出了正式报告与图像资产:
  - `specs/my5_colmap_pose_report_20260328.md`
  - `specs/my5_colmap_pose_report_assets/`
- 报告里的 mermaid 图已用 `beautiful-mermaid-rs` 校验通过.

### 总结感悟
- 这轮最大的收获, 是把“画面上看起来像位姿问题”推进成了“COLMAP 统计上确实有强可疑机位”.
- 当前最值得优先盯住的是 `view 7`, 它不是模糊地可疑, 而是多项指标同时异常.

## [2026-03-27 18:55:48 UTC] [Session ID: ebb3c562-1702-4ea2-8e98-ed18d0a9bada] 任务名称: 核查 `my5` 的 `v3_widecontext` 结果并更新局部对照结论

### 任务内容
- 续接上轮未收尾的 `view 5 / 6 / 7 / 8 + frame 1~12` 局部 COLMAP 对照.
- 判断它到底是“失败后残留”, 还是“成功但没有改善”.

### 完成过程
- 先重新核查运行态:
  - 相关 `timeout` / `colmap mapper` 进程已经结束
  - `distorted/sparse/0` 已落盘
- 再直接从模型本体取证:
  - `images.bin` 里有 `48` 张图
  - `cameras.bin` 里有 `1` 个 `SIMPLE_PINHOLE`
  - `points3D.bin` 复查后有 `4710` 个稀疏点
- 然后复用 `scripts/analyze_colmap_pose_continuity.py`:
  - 产出 `specs/my5_local_pose_compare_v3_widecontext_assets/*`
  - 把 `widecontext` 和 `global / local_fix / local_refine` 放到同一口径比较
- 更新已有正式报告与汇总资产:
  - `specs/my5_local_colmap_compare_20260328.md`
  - `specs/my5_local_colmap_compare_assets/comparison_summary.json`
- 额外完成 mermaid 校验:
  - 用 `beautiful-mermaid-rs` 复核该报告中的 2 个 mermaid block, 均通过

### 总结感悟
- 这轮最重要的不是“又多跑了一版 COLMAP”, 而是把“窗口大小”这条路基本走透了:
  - 更小窗口没有明显改善
  - 更大窗口也没有明显改善
- 之后如果继续追 `my5`, 更应该把注意力转到:
  - 带 frame-gap 保护的筛帧对照
  - 或更保守的 mapper 参数

## [2026-03-27 18:58:52 UTC] [Session ID: ebb3c562-1702-4ea2-8e98-ed18d0a9bada] 任务名称: 为 `my5` 后续筛帧实验补齐 `frame_gap` 感知分析脚本

### 任务内容
- 把 `scripts/analyze_colmap_pose_continuity.py` 从“默认相邻 surviving frame 口径”升级成“可区分真实邻帧和跨 gap 跳跃”.

### 完成过程
- 修改脚本:
  - 新增 `--transition-summary-mode all|contiguous`
  - 给 `frame_details` / `pair_details` 补 `frame_gap` 与 `is_contiguous_transition`
  - 给 summary 补 transition count 字段
- 新增回归测试:
  - `tests/test_analyze_colmap_pose_continuity.py`
- 完成验证:
  - `python3 -m py_compile scripts/analyze_colmap_pose_continuity.py tests/test_analyze_colmap_pose_continuity.py`
  - `pixi run python -m unittest tests.test_analyze_colmap_pose_continuity tests.test_convert`
  - 用真实 `my5` 数据跑了一次 `--transition-summary-mode contiguous` 冒烟
- 为了保持资产口径一致, 又重刷了:
  - `specs/my5_pose_continuity_report_assets/`
  - `specs/my5_local_pose_compare_v1_assets/`
  - `specs/my5_local_pose_compare_v2_refinefocal_assets/`
  - `specs/my5_local_pose_compare_v3_widecontext_assets/`

### 总结感悟
- 这次补的不是“新功能炫技”, 而是后续删帧实验的量尺.
- 先把统计口径修到可信, 后面的筛帧结论才值得信.

## [2026-03-28 12:23:00 UTC] [Session ID: 019d3478-98b2-7fa1-a395-f4ccc3012bf0] 任务名称: 分析 FastGS 离线渲染与 Unity 插件画质差异

### 任务内容
- 核对 FastGS 仓库实际离线渲染链路.
- 判断仓库是否存在额外后处理.
- 结合导出格式与公开 Unity 实现资料, 解释为什么 Unity 插件常见会比离线 render 差.

### 完成过程
- 回读了主线 `task_plan.md`、`WORKLOG.md`、`LATER_PLANS.md`、`EPIPHANY_LOG.md` 与 `EXPERIENCE.md`.
- 阅读了 `render.py`、`gaussian_renderer/__init__.py`、`train.py`、`scene/gaussian_model.py`、`utils/camera_utils.py`、`arguments/__init__.py`、`README.md`、`docs/fastgs-train-scripts.md`.
- 用真实输出文件头确认 `point_cloud.ply` 包含 `f_dc_*`、`f_rest_*`、`opacity`、`scale_*`、`rot_*` 等完整 3DGS 字段.
- 额外交叉参考了 `aras-p/UnityGaussianSplatting` 的 README, 用来补充 Unity 侧常见“实时查看优先而非离线一致性优先”的背景.

### 总结感悟
- 这类问题最容易误判成“FastGS 自带了某种秘密美化后处理”, 但当前仓库证据更支持“离线 render 与 Unity 实时插件不是同一口径”的解释.
- 真正该优先核对的是: 资产文件是否正确、Unity 插件是否完整支持 SH/opacity/scale/rotation、以及相机与分辨率是否在做同口径比较.
