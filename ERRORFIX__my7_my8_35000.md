## [2026-03-28 11:48:07 UTC] [Session ID: codex-20260328-1148] 错误名称: `run_lyra_colmap_fastgs.sh` 默认 `COLMAP` 路径失效导致 `prepare` 无法启动

### 问题现象
- 第一次启动 `my7 prepare` 时, 命令在真正抽帧前就立即退出.
- 真实报错为:
  - `[lyra-colmap-fastgs] ERROR: 文件不存在: /workspace/colmap-cuda-install-3.12.6/bin/colmap`

### 原因分析
- 当前脚本默认把 `COLMAP_BIN` 设为:
  - `/workspace/colmap-cuda-install-3.12.6/bin/colmap`
- 但这台机器上该路径已经不存在.
- 原有回退逻辑只会尝试 `PATH` 中的 `colmap`.
- 而当前环境里:
  - `PATH` 没有 `colmap`
  - 真正可用的是 `$HOME/.local/opt/colmap-env/bin/colmap`

### 修复动作
- 修改了 `scripts/run_lyra_colmap_fastgs.sh` 的 `resolve_default_colmap_bin()`:
  - 默认 `/workspace/.../colmap` 不存在时
  - 先尝试 `$HOME/.local/opt/colmap-env/bin/colmap`
  - 再回退到 `PATH` 中的 `colmap`
- 同时执行:
  - `bash -n scripts/run_lyra_colmap_fastgs.sh`

### 验证结果
- `bash -n` 通过.
- 修复后同一条 `my7 prepare` 命令已真实启动成功.
- 动态证据:
  - 日志出现 `自动回退到用户级 colmap-env`
  - `feature_extractor` 推进到 `324/324`
  - 后续继续进入 `exhaustive_matcher`

### 防再犯结论
- 这类环境依赖入口不能只记住一条作者机器路径.
- 对本机这类长期运行的 wrapper, 默认解析逻辑必须同时覆盖:
  - 历史安装前缀
  - 当前已验证可用的用户级安装前缀
  - `PATH` 命令回退
