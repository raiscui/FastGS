## [2026-03-26 17:50:56 UTC] [Session ID: 019d2b25-0539-7d51-8399-cffaae34ae9f] 笔记: `pixi run setup` 缺少 CUDA 头文件排障证据

## 来源

### 来源1: 本地 `pixi` 环境动态检查

- 命令:
  - `pixi run nvcc --version`
  - `pixi run python - <<'PY' ... torch.cuda.get_device_capability(0) ... PY`
- 要点:
  - `nvcc` 可执行, 版本为 `12.9.86`.
  - `torch` 版本为 `2.9.1`, `torch.version.cuda == 12.9`.
  - 当前 GPU 为 `NVIDIA RTX PRO 6000 Blackwell Server Edition`, capability `(12, 0)`.
  - `torch.cuda.get_arch_list()` 含 `sm_120`, 因此日志中的 `-gencode=arch=compute_120,code=sm_120` 符合当前硬件.

### 来源2: 本地文件系统与已装包检查

- 命令:
  - `find .pixi/envs/default -name cuda_runtime.h`
  - `pixi list | rg -i 'cuda|cudart|nvcc|ninja|pytorch'`
- 要点:
  - 当前环境内找不到 `cuda_runtime.h`.
  - 已安装:
    - `cuda-cudart`
    - `cuda-cudart_linux-64`
    - `cuda-nvcc-tools`
  - 未安装:
    - `cuda-cudart-dev`
    - `ninja`

### 来源3: 仓库配置

- 文件:
  - `pixi.toml`
- 要点:
  - 当前 `feature.cuda.dependencies` 只声明:
    - `cuda-version = "12.9.*"`
    - `pytorch-gpu = "2.9.1.*"`
    - `torchvision = "0.24.1.*"`
    - `torchaudio = "2.9.1.*"`
  - 未显式声明 CUDA 开发头文件包.
  - `setup` 任务会直接跑 `pip install -e` 编译 3 个 CUDA 扩展.

### 来源4: PyTorch / 社区参考

- PyTorch 本地源码位置:
  - `.pixi/envs/default/lib/python3.13/site-packages/torch/utils/cpp_extension.py`
- 要点:
  - `BuildExtension` 默认 `use_ninja=True`.
  - 文档注释明确写到 Ninja 默认会使用 `#CPUS + 2 workers`.
- 额外参考:
  - PyTorch issue `Support new CUDA conda package layout natively in cpp_extension.CUDAExtension`:
    - 提到 conda CUDA 新布局下, include 不一定直接放在 `${PREFIX}/include`.
  - 社区经验:
    - 缺少 `cuda_runtime.h` 时, 常见修复是补 `cuda-cudart-dev`.

## 综合发现

### 现象

- 当前失败不是:
  - `nvcc` 缺失
  - GPU 架构参数不匹配
- 当前失败发生在:
  - 第一份 `.cu` 编译时
  - `nvcc` 找不到 `cuda_runtime.h`

### 当前最强假设

- `pixi` 环境缺少 `cuda-cudart-dev`, 导致根本没有 `cuda_runtime.h`.

### 最强备选解释

- conda-forge CUDA 的布局和 PyTorch `cpp_extension` 的 include 注入方式存在兼容缝隙.
- 即使后面补上开发包, 仍要留意是否需要额外 `CUDA_INC_PATH`.

### 当前建议

- 先做单点修复:
  - 补 `cuda-cudart-dev`
  - 补 `ninja`
- 再用真实 `pixi install` + `pixi run setup` 验证.

## [2026-03-26 18:08:29 UTC] [Session ID: 019d2b25-0539-7d51-8399-cffaae34ae9f] 笔记: 修复后续证据

## 来源

### 来源1: 二次环境修复验证

- 命令:
  - `pixi lock`
  - `pixi install`
  - `find .pixi/envs/default -path '*crt/host_config.h'`
  - `find .pixi/envs/default -name 'conda.specs'`
- 要点:
  - `cuda-cudart-dev` 只解决了第一层 `cuda_runtime.h`.
  - 继续补 `cuda-nvcc` 后, `crt/host_config.h` 才进入环境.
  - 继续补 `conda-gcc-specs` 后, `x86_64-conda-linux-gnu-g++ -v` 才不再报 `could not find specs file conda.specs`.

### 来源2: 工具链权限检查

- 命令:
  - `find .pixi/envs/default/bin -maxdepth 1 -type f ... ! -perm -111`
  - `find .pixi/envs/default/libexec/gcc -type f ! -perm -111`
  - 直接执行 `cc1plus --help`
- 要点:
  - 当前机器上的 `.pixi` 工具链文件初始存在大面积 `0644`.
  - 这会导致:
    - `ninja` 不可执行
    - `x86_64-conda-linux-gnu-cc/c++` 不可执行
    - `cc1plus` 不可执行
  - 因此仅补依赖还不够, `setup` 任务还需要幂等修复执行位.

### 来源3: 源码级最终错误

- 失败日志核心片段:
  - `namespace "std" has no member "uintptr_t"`
  - `identifier "uint32_t" is undefined`
  - `identifier "uint64_t" is undefined`
- 对应文件:
  - `submodules/diff-gaussian-rasterization_fastgs/cuda_rasterizer/rasterizer_impl.h`
- 结论:
  - 这是严格编译器下暴露出的真实源码缺头文件问题.
  - 补 `#include <cstddef>` 与 `#include <cstdint>` 后, 单独 `pip install -e` 已通过.

### 来源4: 最终验证

- 命令:
  - `MAX_JOBS=4 pixi run setup`
  - `pixi run python - <<'PY' import diff_gaussian_rasterization_fastgs; import simple_knn._C; import fused_ssim_cuda; print("imports_ok") PY`
- 要点:
  - 3 个本地 CUDA 扩展均完成 editable 安装.
  - 最终 import 验证输出 `imports_ok`.

## [2026-03-26 18:18:23 UTC] [Session ID: 019d2b25-0539-7d51-8399-cffaae34ae9f] 笔记: 用户再次贴旧层级报错后的复核

## 来源

### 来源1: 当前环境静态复核

- 命令:
  - `pixi list | rg -i 'cuda-(cudart-dev|nvcc|driver-dev)|conda-gcc-specs|ninja'`
  - `find .pixi/envs/default \\( -name cuda_runtime.h -o -path '*crt/host_config.h' -o -name conda.specs \\)`
  - 权限检查:
    - `.pixi/envs/default/bin`
    - `.pixi/envs/default/libexec/gcc`
- 要点:
  - 当前环境中:
    - `cuda-cudart-dev`
    - `cuda-nvcc`
    - `conda-gcc-specs`
    - `ninja`
    - 全都在.
  - 当前文件中:
    - `cuda_runtime.h`
    - `crt/host_config.h`
    - `conda.specs`
    - 全都在.
  - 当前工具链执行位正常,未观察到回退.

### 来源2: 当前环境动态复核

- 命令:
  - `MAX_JOBS=4 pixi run setup`
  - `pixi run python - <<'PY' ... imports_ok ... PY`
- 要点:
  - `pixi run setup` 再次完整通过.
  - 3 个扩展再次成功导入.

## 综合发现

### 结论

- 用户本轮贴出的 `cuda_runtime.h` 报错, 与当前工作区此刻的真实状态不一致.
- 更合理的解释是:
  - 这是一段修复前的旧日志
  - 或者是某次环境未刷新前执行留下的日志
  - 而不是“当前仓库又回退到最初问题”.

## [2026-03-26 18:27:46 UTC] [Session ID: 224652] 笔记: 当前会话对旧层级日志的独立复核

## 来源

### 来源1: 当前环境静态证据

- 命令:
  - `pixi list | rg -i 'cuda-(cudart-dev|nvcc)|conda-gcc-specs|ninja'`
  - `find .pixi/envs/default \\( -name cuda_runtime.h -o -path '*crt/host_config.h' -o -name conda.specs \\) | sort`
  - `find .pixi/envs/default/bin -maxdepth 1 -type f \\( -name 'ninja' -o -name 'x86_64-conda-linux-gnu-*' \\) ! -perm -111`
  - `find .pixi/envs/default/libexec/gcc -type f ! -perm -111`
- 要点:
  - 当前环境仍然安装了:
    - `cuda-cudart-dev`
    - `cuda-nvcc`
    - `conda-gcc-specs`
    - `ninja`
  - 当前文件系统仍然存在:
    - `.pixi/envs/default/targets/x86_64-linux/include/cuda_runtime.h`
    - `.pixi/envs/default/targets/x86_64-linux/include/crt/host_config.h`
    - `.pixi/envs/default/lib/gcc/x86_64-conda-linux-gnu/14.3.0/conda.specs`
  - 两处权限检查都没有返回结果, 说明本轮没有观察到工具链执行位缺失.

### 来源2: 当前环境动态证据

- 命令:
  - `MAX_JOBS=4 pixi run setup`
  - `pixi run python - <<'PY' ... imports_ok ... PY`
- 要点:
  - `pixi run setup` 在当前会话下完整成功.
  - `diff_gaussian_rasterization_fastgs`
  - `simple_knn._C`
  - `fused_ssim_cuda`
  - 当前都能成功导入.

## 综合发现

### 现象

- 用户刚贴出的日志仍然是:
  - `fatal error: cuda_runtime.h: No such file or directory`

### 当前假设

- 这段日志不是当前工作区此刻重新跑出来的失败.
- 更像是修复前, 或者环境尚未刷新到最新依赖时产生的旧日志.

### 推翻该假设的证据

- 如果当前会话重跑 `pixi run setup` 再次出现同样的 `cuda_runtime.h` 缺失, 那么“旧日志假设”就不成立.

### 本轮结论

- 当前会话已亲自复跑并确认:
  - 假设没有被推翻.
  - 当前工作区不再处于 `cuda_runtime.h` 缺失状态.
