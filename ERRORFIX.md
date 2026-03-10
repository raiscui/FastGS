# ERRORFIX


## [2026-03-10 04:10:59 UTC] 错误名称: 追加 Markdown 时反引号触发 shell 命令替换

### 问题现象
- 在向 `task_plan.md` / `notes.md` 追加 Markdown 时,外层用了双引号包裹 shell 命令.
- 正文中的反引号片段如 `convert.py`、`input/` 被 shell 提前执行,导致终端出现 `command not found` 与路径不存在错误.
- 文件虽然被追加了内容,但反引号包裹的关键字被吃掉了.

### 原因
- 虽然内部 heredoc 用了单引号 `<<'EOF'`,但外层 `bash -lc "..."` 仍会先处理反引号命令替换.
- 这属于 shell 层命令构造错误,不是仓库代码逻辑错误.

### 修复
- 后续文件追加统一改为 `python3` 脚本写入,避免 shell 对正文做命令替换.
- 对已受影响的上下文信息,采用“追加纠正记录”的方式修复,不在原位置中途改写.

### 验证
- 使用 `python3` 追加上下文后,未再出现反引号触发的误执行.
- 后续 `task_plan.md` / `notes.md` / `WORKLOG.md` / `ERRORFIX.md` 均已成功追加.


## [2026-03-10 06:02:57 UTC] 错误名称: shell 变量在核查命令中被提前展开成空路径

### 问题现象
- 我在核查产物目录时写了 `bash -lc "root=...; ls -ld $root/input ..."`.
- 由于外层 shell 先展开了 `$root`,命令实际查成了 `/input`、`/images` 这类错误路径,终端出现 `No such file or directory`.

### 原因
- 变量定义和变量使用都放在双引号命令字符串里,被外层 shell 提前展开了.
- 这属于命令构造错误,不是数据转换失败.

### 修复
- 改用 `python3` 直接读取和统计真实目录,绕开 shell 变量展开风险.

### 验证
- 重查后确认真实目录 `/workspace/lyra/outputs/flashvsr_reference/full_scale2x/input`、`images`、`sparse/0` 均存在且内容完整.

## [2026-03-10 06:20:00 UTC] 错误名称: 在双引号 `python3 -c` 命令里再次写入反引号文本, 仍会触发 shell 替换

### 问题现象
- 我尝试用 `python3 -c "...` 的方式向 `task_plan.md` 追加内容.
- 追加正文里包含 `` `output/` `` 这类反引号片段时, 外层 shell 仍然会先执行命令替换.
- 终端报错: `/bin/bash: line 1: output/: Is a directory`.

### 原因
- 即使主体逻辑已经切到 Python, 只要最外层命令还是双引号, 反引号就会在进入 Python 前先被 shell 处理.
- 根因仍然是 shell 引号层级不安全, 不是 Python 文件写入逻辑有问题.

### 修复
- 改成 `bash -lc 'python3 <<'"'"'PY'"'"' ... PY'` 这种单引号 heredoc 方案.
- 后续凡是要把 Markdown 原样追加到六文件, 都避免再用双引号包 `python3 -c`.

### 验证
- 改用单引号 heredoc 后, `task_plan.md` 成功追加包含反引号的正文, 未再触发 shell 误执行.

## [2026-03-10 06:41:00 UTC] 错误名称: 用 `pgrep -af <完整命令串>` 监控训练进程时, 误匹配到了监控命令自身

### 问题现象
- 我写了一个 `while pgrep -af "train.py -s ... -m ..." >/dev/null; do sleep 30; done` 的等待命令.
- 结果它一直不退出, 即使训练其实已经结束了.

### 原因
- `pgrep -af` 会匹配完整命令行.
- 监控命令自己的 shell 进程里就包含了同一段模式字符串, 所以等价于把自己也匹配进去了.

### 修复
- 放弃用这条 `pgrep` 循环做结束判定.
- 改为直接读取 `train.log` 和训练输出目录来确认最终状态, 这是更直接也更可靠的证据.

### 验证
- 重新通过 `train.log` 中的 `Training complete.`、`[ITER 30000] Saving Gaussians` 以及最终点云文件存在性完成核查后, 已确认训练真实结束.

## [2026-03-10 07:08:00 UTC] 错误名称: 为了回答 PSNR 误触发了 `LPIPS(vgg)` 大模型下载

### 问题现象
- 我最开始复用了 `metrics.py` 的完整指标口径, 连同 `LPIPS(vgg)` 一起跑.
- 终端随即开始下载 `vgg16-397923af.pth` 大约 528MB 权重, 明显超出了“只回答 PSNR”所需范围.

### 原因
- `metrics.py` 默认同时计算 `SSIM`、`PSNR`、`LPIPS`.
- `LPIPS(vgg)` 首次运行需要额外下载 VGG 权重, 这是隐藏的运行时成本.

### 修复
- 中止了这条无关的大下载流程.
- 改为仅调用仓库现有 `psnr` / `ssim` 实现计算用户当前真正需要的指标.

### 验证
- 改用精简脚本后, 已成功输出 `count=60`, `PSNR=26.6863`, `SSIM=0.8609`.
