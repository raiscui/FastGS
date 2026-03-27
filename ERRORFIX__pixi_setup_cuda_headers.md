## [2026-03-26 18:08:29 UTC] [Session ID: 019d2b25-0539-7d51-8399-cffaae34ae9f] 问题: `pixi run setup` 构建本地 CUDA 扩展失败

### 现象
- 用户最初看到的报错是:
  - `fatal error: cuda_runtime.h: No such file or directory`
- 继续验证后又依次暴露:
  - `crt/host_config.h: No such file or directory`
  - `could not find specs file conda.specs`
  - `Permission denied` / `cannot execute 'cc1plus'`
  - `std::uintptr_t` / `uint32_t` / `uint64_t` 未定义

### 原因
- 这是一个分层叠加的问题, 不是单点故障:
  - 第1层:
    - `pixi.toml` 只声明了 PyTorch GPU 运行时, 缺少本地 CUDA 扩展编译所需的开发包.
  - 第2层:
    - 当前机器上的 `.pixi` 工具链文件被链接成了不可执行状态, 包括:
      - `ninja`
      - `x86_64-conda-linux-gnu-*`
      - `libexec/gcc/*`
  - 第3层:
    - conda GCC 缺少 `conda.specs`, 需要 `conda-gcc-specs`.
  - 第4层:
    - `diff-gaussian-rasterization_fastgs` 自身在 `rasterizer_impl.h` 中使用了固定宽度整数类型与 `std::uintptr_t`, 却没有包含对应标准头.

### 修复
- 环境定义修复:
  - `pixi.toml` 新增:
    - `ninja`
    - `cuda-cudart-dev`
    - `cuda-nvcc`
    - `conda-gcc-specs`
  - `pixi.lock` 已同步刷新.
- 任务防回归修复:
  - `pixi.toml` 的 `setup` 任务改为先幂等修复 `.pixi` 工具链执行位, 再执行 `pip install -e`.
- 源码修复:
  - `submodules/diff-gaussian-rasterization_fastgs/cuda_rasterizer/rasterizer_impl.h`
  - 新增:
    - `#include <cstddef>`
    - `#include <cstdint>`

### 验证
- 环境侧验证:
  - `find .pixi/envs/default -path '*crt/host_config.h'`
  - `find .pixi/envs/default -name 'conda.specs'`
- 构建侧验证:
  - `MAX_JOBS=4 pixi run python -m pip install --no-build-isolation -e submodules/diff-gaussian-rasterization_fastgs`
  - `MAX_JOBS=4 pixi run setup`
- 运行时验证:
  - `pixi run python - <<'PY'`
  - `import diff_gaussian_rasterization_fastgs`
  - `import simple_knn._C`
  - `import fused_ssim_cuda`
  - `print("imports_ok")`
  - `PY`

### 结果
- `pixi run setup` 已成功完成.
- 3 个本地扩展已能在 `pixi` Python 中成功导入.
