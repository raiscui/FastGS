## [2026-03-28 08:53:30 UTC] [Session ID: 5957] 错误名称: 追加支线 Markdown 时误用未加引号 heredoc

### 问题现象
- 向 `task_plan__my6_35000.md` 和 `notes__my6_35000.md` 追加记录时, 终端突然出现大量:
  - `command not found`
  - `No such file or directory`
  - `ffmpeg` / `ffprobe` 被意外触发
- 同时, 两个 Markdown 文件尾部新增了一段被吞字后的损坏记录.

### 原因分析
- 这次追加正文里包含大量反引号代码片段.
- 但写入时用了未加引号的 heredoc, 让 shell 把反引号当成命令替换执行了.
- 这不是仓库没有提醒, 而是执行时没有遵守已有规则:
  - 应使用 `<<'EOF'`
  - 或直接用 `apply_patch`

### 修复动作
- 用 `apply_patch` 直接修复了两个文件尾部被污染的记录段落.
- 新增本条 `ERRORFIX__my6_35000.md`, 记录这次过程性错误.
- 后续这条支线里凡是再写带反引号的 Markdown, 一律优先使用:
  - `apply_patch`
  - 或安全的单引号 heredoc 方案

### 验证结果
- 已重新检查:
  - `task_plan__my6_35000.md`
  - `notes__my6_35000.md`
- 当前两份文件的尾部内容已恢复为可读、完整、可继续追踪的状态.

### 防再犯结论
- 这类错误不是“偶尔会出”, 而是 shell 的确定性行为.
- 以后只要正文里含反引号, 就默认把未加引号 heredoc 视为危险操作.

## [2026-03-28 17:53:30 UTC] [Session ID: 5957] 错误名称: 在 PTY 会话里跑 `prepare` 时 `ffmpeg` 被挂起

### 问题现象
- 第一次启动 `my6 prepare` 时, 日志停在第一条:
  - `ffmpeg -y -i ... -vf fps=5.333333333333 ...`
- 旁路检查发现:
  - `input/` 里 `0` 张图
  - `ffmpeg` 进程状态是 `T`
  - `convert.py` 还活着, 但没有继续前进

### 原因分析
- 当前最强解释是:
  - PTY 交互终端让 `ffmpeg` 维持了 stdin 交互语义
  - 进程被 job control 挂起
- 这条判断有动态佐证:
  - 同一条 `prepare` 命令改为非 PTY 方式后, 立刻正常抽出 `27` 帧并继续跑完整个 `prepare`

### 修复动作
- 终止了第一次卡住的 `prepare` 进程组.
- 清理未完成的 `data/my6_colmap_fastgs`.
- 改用非 PTY 的普通管道方式重跑同一条 `prepare` 命令.

### 验证结果
- 第二次 `prepare` 已完整完成:
  - `images = 324`
  - `sparse/0` 已落盘
  - 日志末尾出现 `Done.`

### 防再犯结论
- 含 `ffmpeg` 这类默认会碰 stdin 的长任务, 优先不要放在 PTY 交互会话里跑.
- 如果必须在 PTY 里跑, 需要额外处理 stdin 行为, 否则就优先使用普通 pipe 模式.

## [2026-03-28 17:54:10 UTC] [Session ID: 5957] 错误名称: `my6` 全量直跑训练在首个保存点前触发 `CUDA illegal memory access`

### 问题现象
- 使用 `my5` 同口径直接训练 `0 -> 35000` 时:
  - 日志在约 `7940` 左右报错退出
  - 真实异常为:
    - `torch.AcceleratorError: CUDA error: an illegal memory access was encountered`
- 因为当前只计划在 `35000` 保存, 所以没有任何 checkpoint 可供续训

### 原因分析
- 当前还没有确认扩展层里的深层根因.
- 但已有静态和动态证据表明:
  - 这类错误在本仓库历史里不是首次出现
  - 它更像随机运行时稳定性问题, 而不是参数解析或数据目录错误

### 修复动作
- 暂不贸然改 CUDA / Python 代码.
- 先切换到项目内已经被验证过的 guarded 交付方案:
  - `1000` 步一段
  - 每段保存 checkpoint / point cloud
  - 失败就从最近稳定锚点重试
  - 重试时更换 seed

### 验证计划
- 先看 guarded 分段训练能否稳定跨过:
  - `1000`
  - `2000`
  - ...
  - `8000`
- 如果能跨过之前的崩溃区间, 就说明当前最有效的是守护式推进, 而不是继续赌一口气长跑.
