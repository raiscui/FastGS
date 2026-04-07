## [2026-03-28 16:44:25 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my9` 路径核查的当前阻塞点

## 来源

### 来源1: 直接路径核查

- 当前机器结果:
  - `/root/autodl-fs/my9` 不存在
  - `/root/autodl-fs/my9/0/generated_videos/generated_video_0.mp4` 不存在
- 因此:
  - 还无法进行 `ffprobe`
  - 也无法做最小抽帧验证

### 来源2: 同级目录列表

- `/root/autodl-fs` 当前只看到:
  - `denoise_opt`
  - `my5`
  - `my6`
  - `my7`
  - `my8`
- `/autodl-fs/data` 当前只看到:
  - `denoise_opt`
  - `my5`
  - `my6`
  - `my7`
  - `my8`

### 来源3: 全局搜索

- 在 `/root` 与 `/autodl-fs` 下搜索:
  - `-name 'my9'`
  - `-name '*my9*'`
- 当前都没有命中目录

## 综合发现

### 现象
- 这次的首要问题不是训练脚本失败.
- 而是用户给出的 `my9` 路径当前在机器上不存在.

### 当前主假设
- 更像数据还没同步到这台机器, 或者真实路径写法与用户输入不同.

### 最强备选解释
- 也可能 `my9` 被放在当前未检索到的其他挂载点.

### 当前结论
- 在拿到真实存在的 `my9` 路径前, 不能负责任地启动后续 `prepare` 和训练.

## [2026-03-28 16:44:25 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: 用户再次确认同一路径后, 已验证到真实目标目录仍无 `my9`

## 来源

### 来源1: 符号链接核查

- `/root/autodl-fs` 当前不是实体目录, 而是:
  - `/root/autodl-fs -> /autodl-fs/data`
- 因此用户给出的:
  - `/root/autodl-fs/my9`
- 实际等价于:
  - `/autodl-fs/data/my9`

### 来源2: 真实目标目录列表

- `/autodl-fs/data` 当前实际只有:
  - `denoise_opt`
  - `my5`
  - `my6`
  - `my7`
  - `my8`
- `ls -ld /autodl-fs/data/my9` 直接报:
  - `No such file or directory`

## 综合发现

### 现象
- 这次不是因为我没跟对符号链接.
- 而是在符号链接展开之后, 真实目标目录里也确实没有 `my9`.

### 当前结论
- 当前机器上, 用户给出的这条绝对路径还不足以继续执行任务.
- 必须先拿到真实存在的 `my9` 数据目录, 或等数据同步完成.

## [2026-03-28 17:14:04 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my9` 已具备与 `my5` 到 `my8` 相同的输入结构

## 来源

### 来源1: 顶层目录核查

- `/root/autodl-fs/my9` 当前包含:
  - `0..11` 共 `12` 个视角目录
  - 顶层额外存在 `shared/`

### 来源2: 视角目录内容核查

- 对 `my9/0` 与 `my9/1` 的真实文件核查显示:
  - 都有 `generated_videos/generated_video_0.mp4`
  - 都有 `rendering_4D_maps/merged_mask.mp4`
  - 也存在若干不该送进训练 RGB 入口的辅助视频
- 这与 `my5` 到 `my8` 的整体模式一致

### 来源3: 视频元信息与抽帧验证

- `my9/0/generated_videos/generated_video_0.mp4`:
  - `width=1280`
  - `height=720`
  - `avg_frame_rate=16/1`
  - `nb_frames=81`
  - `duration=5.063000`
- 最小动态抽帧结果:
  - `5.333333333333 fps -> 27` 帧

### 来源4: 当前中间产物状态

- 当前仍未启动 `my9`:
  - `data/my9_colmap_fastgs/input = 0`
  - `data/my9_colmap_fastgs/images = 0`
  - `data/my9_colmap_fastgs/sparse/0 = 0`
  - `output/my9_nomask_v1/checkpoints = 0`
  - `output/my9_nomask_v1/videos = 0`

## 综合发现

### 现象
- `my9` 现在已经从“路径不存在”切换成“可按既有流程真实执行”.

### 当前结论
- `my9` 可以直接复用 `my5` 到 `my8` 的稳定口径:
  - `nomask`
  - `--video-fps 5.333333333333`
  - guarded `35000`

## [2026-03-28 17:15:23 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my9` 已进入真实执行态, 自动接力链已挂起

## 来源

### 来源1: `my9 prepare` 启动输出

- 已拿到真实 `prepare_pid=817574`
- 活跃会话:
  - `94739`
- 启动输出已确认:
  - 自动回退到 `/home/rais/.local/opt/colmap-env/bin/colmap`
  - `convert.py` 已开始对 `my9` 的 `12` 路视频做抽帧

### 来源2: `my9` 自动接力脚本

- 新建脚本:
  - `/tmp/fastgs_logs/my9_pipeline_20260328_1714.sh`
- 活跃会话:
  - `11201`
- 当前行为:
  - 轮询等待 `prepare_pid=817574` 结束
  - 结束后自动核验 `images` / `sparse/0`
  - 再沿用既有 guarded 训练与渲染策略

## 综合发现

### 现象
- `my9` 现在已经从“可验证”切到“真实开跑”.
- 自动接力链也已经预先挂好, 不需要等 `prepare` 结束后手工接下一段.

### 当前结论
- 当前最重要的是继续观察 `my9 prepare` 的阶段推进.
- 现阶段没有必要改参数或额外分叉流程.

## [2026-03-28 17:16:23 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 笔记: `my9 prepare` 已推进到 matcher 早段

## 来源

### 来源1: `my9 prepare` 会话 `94739`

- 已确认阶段推进:
  - 抽帧完成, `input = 324`
  - `feature_extractor` 完成到 `324/324`
  - 当前进入 `exhaustive_matcher`
- 最近动态输出依次出现:
  - `Processing block [1/7, 1/7]`
  - `Processing block [1/7, 2/7]`
  - `Processing block [1/7, 3/7]`

### 来源2: `my9` 自动接力会话 `11201`

- 会话仍在健康等待:
  - 每 `30s` 输出一次 `prepare still running`
- 这说明自动接力链没有丢

### 来源3: 当前目录状态

- `data/my9_colmap_fastgs/input = 324`
- `data/my9_colmap_fastgs/images = 0`
- `data/my9_colmap_fastgs/sparse/0 = 0`

## 综合发现

### 现象
- `my9` 当前还没有进入 `mapper`.
- 但 `matcher` 已经正常推进 block.

### 当前结论
- 当前最合理的动作仍然是继续等待 `my9 prepare`.
