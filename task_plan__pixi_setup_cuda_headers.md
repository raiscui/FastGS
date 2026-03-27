# 任务计划: 修复 `pixi run setup` 缺少 CUDA 开发头文件导致的扩展编译失败

## 目标
- 解释清楚为什么 `pixi run setup` 在构建 `diff_gaussian_rasterization_fastgs` 时报 `cuda_runtime.h: No such file or directory`.
- 修复项目环境定义, 让本仓库在当前机器上能稳定完成本地 CUDA 扩展安装.
- 给出可复现的验证证据, 而不是只给“应该可以”的猜测.

## 两种方向
- 方案A(不惜代价,最佳):
  - 直接把缺失的 CUDA 开发依赖补进 `pixi.toml`, 同步刷新锁文件.
  - 顺手补 `ninja`, 避免再次退回慢速 `distutils` 构建.
  - 重新执行 `pixi install` 与 `pixi run setup`, 用真实结果收敛结论.
- 方案B(先能用,后面再优雅):
  - 不改仓库配置.
  - 只在当前 shell 临时补装或导出环境变量, 先让这一台机器能编译通过.
  - 代价是别的机器仍可能继续踩同一个坑.

## 阶段
- [x] 阶段1: 回读上下文并建立支线计划
- [x] 阶段2: 收集静态与动态证据
- [x] 阶段3: 实施单点修复
- [x] 阶段4: 重跑 setup 验证并交付

## 关键问题
1. 失败路径里, `nvcc` 是否真的可用?
2. `cuda_runtime.h` 在当前 `pixi` 环境里到底是“没装”, 还是“装了但没被找到”?
3. 仓库当前 `pixi.toml` 缺的是哪个依赖?
4. 修完后是否还会遇到第二层阻塞, 比如 `ninja` 缺失或编译器问题?

## 现象 -> 假设 -> 验证计划
- 现象:
  - 用户提供的真实构建日志显示:
    - `nvcc` 已经启动.
    - 第一份 `.cu` 编译时直接报 `<command-line>: fatal error: cuda_runtime.h: No such file or directory`.
    - 同时 PyTorch 提示 `we could not find ninja`, 已回退到慢速后端.
- 当前主假设:
  - `pixi` 环境里缺少 `cuda-cudart-dev` 这类 CUDA 开发头文件包.
- 备选解释:
  - 头文件已经存在, 但 conda-forge CUDA 的布局没有被当前 PyTorch `cpp_extension` 正确纳入 include 路径.
- 推翻主假设的证据:
  - 如果在当前环境中能找到 `cuda_runtime.h`, 那主假设就不成立, 需要转向 include 路径布局问题.

## 当前证据摘要
- 本地动态验证:
  - `pixi run nvcc --version` 成功, 当前编译器为 CUDA 12.9.86.
  - `pixi run python` 显示 `torch 2.9.1`, `torch.version.cuda == 12.9`.
  - 当前 GPU 为 `NVIDIA RTX PRO 6000 Blackwell Server Edition`, capability `(12, 0)`, 因此日志中的 `sm_120` 不是异常项.
- 本地静态验证:
  - `find .pixi/envs/default -name cuda_runtime.h` 无结果.
  - `pixi list` 仅见到 `cuda-cudart` / `cuda-cudart_linux-64` / `cuda-nvcc-tools`, 未见 `cuda-cudart-dev`.
  - `pixi.toml` 当前只声明 `cuda-version` 与 `pytorch-gpu`, 没有显式声明 CUDA 开发头文件依赖, 也没有 `ninja`.
- 外部参考:
  - PyTorch `BuildExtension` 默认 `use_ninja=True`, 缺少 `ninja` 时会回退.
  - PyTorch 社区已有关于“新的 conda CUDA 布局与 `cpp_extension` 兼容性”的公开 issue, 并提到 `CUDA_INC_PATH` / 开发头文件包是现实工作绕法.

## 进度更新
- 2026-03-26 18:08:29 UTC:
  - 已补 `cuda-cudart-dev`、`cuda-nvcc`、`conda-gcc-specs` 到 `pixi.toml`, 并同步刷新 `pixi.lock`.
  - 已确认 `cuda_runtime.h` 与 `crt/host_config.h` 进入 `.pixi/envs/default/targets/x86_64-linux/include`.
  - 已确认 `conda.specs` 进入 `.pixi/envs/default/lib/gcc/x86_64-conda-linux-gnu/14.3.0/`.
- 2026-03-26 18:08:29 UTC:
  - 已观察到当前机器上的 `.pixi` 工具链存在额外环境缺陷:
    - `ninja`
    - `x86_64-conda-linux-gnu-*`
    - `libexec/gcc/*`
    - 初始都缺失执行位.
  - 已把“幂等修正执行位”收进 `pixi.toml` 的 `setup` 任务, 避免后续重建环境时重复手工补权限.
- 2026-03-26 18:08:29 UTC:
  - 在环境问题排开后, `diff_gaussian_rasterization_fastgs` 暴露出真正的源码兼容性问题:
    - `cuda_rasterizer/rasterizer_impl.h` 使用了 `std::uintptr_t`、`uint32_t`、`uint64_t`, 但没包含对应标准头.
  - 已补 `#include <cstddef>` 与 `#include <cstdint>`, 真实编译通过.
- 2026-03-26 18:08:29 UTC:
  - 最终验证通过:
    - `MAX_JOBS=4 pixi run setup`
    - `pixi run python - <<'PY' ... import diff_gaussian_rasterization_fastgs; import simple_knn._C; import fused_ssim_cuda ... PY`
- 2026-03-26 18:18:23 UTC:
  - 用户再次贴出 `cuda_runtime.h: No such file or directory` 日志.
  - 当前待确认点不再是“理论修法”, 而是:
    - 这是不是旧日志
    - 还是当前 `.pixi` 环境状态已经回退/损坏
  - 下一步直接核对当前环境中的关键包与头文件, 并复跑 `pixi run setup`.
- 2026-03-26 18:18:23 UTC:
  - 复核结果已收敛:
    - 当前环境里 `cuda_runtime.h`、`crt/host_config.h`、`conda.specs` 都存在.
    - 当前环境里 `cuda-cudart-dev`、`cuda-nvcc`、`conda-gcc-specs`、`ninja` 都存在.
    - 当前 `.pixi` 工具链执行位正常.
  - 在当前工作区真实执行:
    - `MAX_JOBS=4 pixi run setup`
    - `pixi run python` 导入 3 个扩展
  - 均已成功.
  - 因此用户贴出的这段 `cuda_runtime.h` 日志, 和“当前工作区此刻的环境状态”不一致, 更像是旧失败日志, 或者是环境刷新前跑出来的结果.

## 状态
**目前已完成复核**
- 2026-03-26 17:50:56 UTC: 已完成最小证据收集.
- 2026-03-26 18:08:29 UTC: 已完成环境依赖修复、任务自修复包装、源码头文件修复与完整验证.
- 2026-03-26 18:18:23 UTC: 已确认当前环境没有回退, 复核验证继续通过.

## [2026-03-26 18:23:34 UTC] [Session ID: 224652] [记录类型]: 当前会话复核用户再次贴出的旧层级日志

### 本轮目标
- 不直接复用上一会话的验证结论.
- 用当前会话重新确认:
  - 当前 `.pixi` 环境里关键 CUDA 开发文件是否还在.
  - `pixi run setup` 现在是否仍会失败.
  - 用户贴出的这段 `cuda_runtime.h` 日志, 是否对应当前真实状态.

### 本轮计划
- [x] 回读支线 `task_plan`、`notes`、`WORKLOG`、`ERRORFIX`.
- [x] 复核当前环境里的关键依赖与头文件.
- [x] 在当前会话下再次执行 `MAX_JOBS=4 pixi run setup`.
- [x] 结合静态证据与动态结果, 给出“现象 -> 假设 -> 验证 -> 结论”的答复.

### 当前状态
- 当前会话复核已完成.

### 本轮结论
- 当前环境中:
  - `cuda-cudart-dev`
  - `cuda-nvcc`
  - `conda-gcc-specs`
  - `ninja`
  - 以及 `cuda_runtime.h` / `crt/host_config.h` / `conda.specs`
  - 都存在.
- 当前会话真实执行:
  - `MAX_JOBS=4 pixi run setup`
  - `pixi run python` 导入 3 个扩展
  - 均成功.
- 因此用户刚贴出的 `cuda_runtime.h` 缺失日志, 不对应当前工作区此刻状态, 更像是修复前或环境未刷新前的旧失败记录.
