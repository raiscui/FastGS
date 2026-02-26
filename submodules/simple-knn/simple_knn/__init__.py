# =============================================================================
# simple_knn Python 包入口
#
# 背景:
# - 本仓库通过 `torch.utils.cpp_extension` 编译 CUDA 扩展为 `simple_knn._C`.
# - 该目录原本没有 `__init__.py`,在 pip 的 PEP 660 editable 安装模式下,
#   会导致 `import simple_knn` / `import simple_knn._C` 解析失败.
#
# 处理:
# - 提供一个轻量的包入口,让 editable/非 editable 安装都能稳定 import.
# =============================================================================

from ._C import *  # noqa: F401,F403

