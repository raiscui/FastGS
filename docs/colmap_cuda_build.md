# 在 `/workspace` 编译支持 CUDA 的 COLMAP

这份文档不是泛泛的安装说明。

它记录的是这台机器上已经真实跑通的一条路径:
- 保留系统已有的 CPU 版 `/usr/bin/colmap`
- 在 `/workspace` 并行安装一份支持 CUDA 的 `colmap`
- 最终通过 `convert.py --colmap_executable` 接入

如果你后面又换了驱动、CUDA 版本或 GPU 架构, 这份文档里的少数参数可能要跟着调整。
但当前这份内容, 是已经过静态验证和动态验证的。

---

## 1. 本次已验证的结果

- 新二进制路径: `/workspace/colmap-cuda-install-3.12.6/bin/colmap`
- 源码目录: `/workspace/colmap-cuda-src-3.12.6`
- 构建目录: `/workspace/colmap-cuda-build-3.12.6`
- 安装目录: `/workspace/colmap-cuda-install-3.12.6`
- `colmap -h` 输出: `COLMAP 3.12.6 ... with CUDA`
- 动态验证日志包含: `Creating SIFT GPU feature extractor`

本机当时的关键环境:
- GPU: `NVIDIA A800-SXM4-80GB`
- 驱动: `580.105.08`
- `nvcc`: `12.6`
- 编译器: `gcc-10` / `g++-10`
- `CMAKE_CUDA_ARCHITECTURES`: `80`

---

## 2. 为什么不直接替换系统的 `colmap`

系统自带的 `/usr/bin/colmap` 当前是 CPU 版。

直接覆盖它, 风险很高:
- 一旦 CUDA 版编译失败, 原本能用的 CPU 路径也会一起坏掉
- 后续排障时, 很难区分到底是“仓库问题”还是“系统环境问题”

更稳的做法是并行保留两份:
- CPU 回退路径: `/usr/bin/colmap`
- CUDA 版路径: `/workspace/colmap-cuda-install-3.12.6/bin/colmap`

然后在仓库里显式指定:

```bash
python3 convert.py \
  -s data/jm-sd2 \
  --video_fps 24 \
  --colmap_executable /workspace/colmap-cuda-install-3.12.6/bin/colmap
```

注意:
- 这里不要再带 `--no_gpu`
- `convert.py` 默认就会请求 COLMAP 使用 GPU

---

## 3. 安装系统依赖

这次真实构建时使用的是下面这一组依赖。

```bash
apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git \
  cmake \
  ninja-build \
  build-essential \
  libboost-program-options-dev \
  libboost-graph-dev \
  libboost-system-dev \
  libeigen3-dev \
  libfreeimage-dev \
  libmetis-dev \
  libgoogle-glog-dev \
  libgtest-dev \
  libgmock-dev \
  libsqlite3-dev \
  libglew-dev \
  qt6-base-dev \
  libqt6opengl6-dev \
  libqt6openglwidgets6 \
  libcgal-dev \
  libceres-dev \
  libsuitesparse-dev \
  libcurl4-openssl-dev \
  libssl-dev \
  libflann-dev \
  gcc-10 \
  g++-10
```

说明:
- 这里额外安装了 `gcc-10` / `g++-10`
- 原因不是“必须永远只能用 10”, 而是这次真实跑通的组合就是它
- 既然已经有动态证据, 后续优先复用这个组合, 不要先去冒险换编译器

---

## 4. 获取源码

本次固定到官方 `3.12.6` 版本。

```bash
git clone --branch 3.12.6 --depth 1 \
  https://github.com/colmap/colmap.git \
  /workspace/colmap-cuda-src-3.12.6
```

---

## 5. 配置 CMake

先准备构建目录和安装目录:

```bash
mkdir -p /workspace/colmap-cuda-build-3.12.6
mkdir -p /workspace/colmap-cuda-install-3.12.6
```

然后执行配置:

```bash
CC=/usr/bin/gcc-10 \
CXX=/usr/bin/g++-10 \
CUDAHOSTCXX=/usr/bin/g++-10 \
cmake \
  -S /workspace/colmap-cuda-src-3.12.6 \
  -B /workspace/colmap-cuda-build-3.12.6 \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/workspace/colmap-cuda-install-3.12.6 \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.6/bin/nvcc \
  -DCUDA_ENABLED=ON \
  -DCMAKE_CUDA_ARCHITECTURES=80 \
  -DTESTS_ENABLED=OFF
```

这一步的关键输出应该能看到类似:

```text
The CUDA compiler identification is NVIDIA 12.6.20
Enabling CUDA support (version: 12.6.20, archs: 80)
Enabling GPU support (OpenGL: ON, CUDA: ON)
```

如果这里没有看到 `Enabling CUDA support`, 就不要继续编译。
先停下来排查 CUDA 检测。

---

## 6. 编译并安装

```bash
cmake --build /workspace/colmap-cuda-build-3.12.6 --parallel 16
cmake --install /workspace/colmap-cuda-build-3.12.6
```

编译产物安装后, 可执行文件应位于:

```bash
/workspace/colmap-cuda-install-3.12.6/bin/colmap
```

---

## 7. 静态验证

### 7.1 看版本口径

```bash
/workspace/colmap-cuda-install-3.12.6/bin/colmap -h | head -n 4
```

期望结果里要出现:

```text
COLMAP 3.12.6 ... with CUDA
```

如果仍然是 `without CUDA`, 说明这次构建没真正启用 CUDA。

### 7.2 看运行时链接

```bash
ldd /workspace/colmap-cuda-install-3.12.6/bin/colmap | \
  rg "cudart|curand|cuda|nvidia-ml|GLEW|OpenGL"
```

本次真实结果里, 至少能看到:

```text
libcudart.so.12 => /usr/local/cuda/lib64/libcudart.so.12
```

---

## 8. 动态验证

只看 `-h` 还不够。

真正关键的是让它跑一次 GPU SIFT。
本次使用 2 张真实图片做 smoke test:

```bash
smoke_dir=$(mktemp -d /workspace/colmap-cuda-smoke-XXXXXX)
mkdir -p "$smoke_dir/images"

cp data/jm-sd2/input/frame_000001.jpg "$smoke_dir/images/"
cp data/jm-sd2/input/frame_000002.jpg "$smoke_dir/images/"

/workspace/colmap-cuda-install-3.12.6/bin/colmap feature_extractor \
  --database_path "$smoke_dir/database.db" \
  --image_path "$smoke_dir/images" \
  --ImageReader.single_camera 1 \
  --SiftExtraction.use_gpu 1 \
  --SiftExtraction.max_num_features 512 \
  --SiftExtraction.max_image_size 1600 \
  --SiftExtraction.num_threads 1
```

本次真实日志里的关键证据:

```text
Creating SIFT GPU feature extractor
Processed file [1/2]
Processed file [2/2]
```

你还可以继续检查数据库:

```bash
sqlite3 "$smoke_dir/database.db" \
  "select count(*) as images from images; select count(*) as keypoints from keypoints;"
```

本次真实结果是:

```text
2
2
```

这说明:
- 图片已经入库
- GPU 特征提取链路确实跑通了

---

## 9. 与 `convert.py` 集成

本仓库不需要为了 GPU 版 COLMAP 再改代码。

因为 `convert.py` 已经支持外部 `colmap` 路径:
- `--colmap_executable`
- 不传 `--no_gpu` 时, 会默认请求 GPU SIFT

实际使用示例:

```bash
python3 convert.py \
  -s data/jm-sd2 \
  --video_fps 24 \
  --colmap_executable /workspace/colmap-cuda-install-3.12.6/bin/colmap
```

如果你想重新抽帧和重建, 再补:

```bash
--overwrite
```

如果你故意想回退到 CPU 版, 才使用:

```bash
--no_gpu
```

---

## 10. 这台机器上目前已知的注意事项

### 10.1 系统 CPU 版 `colmap` 仍然存在

当前系统 `/usr/bin/colmap` 仍然是 CPU 版。

这不是问题。
反而是有意保留的回退路径。

### 10.2 `apt` 后出现过旧版 NVIDIA 空文件告警

安装依赖后, `ldconfig` 打印过几条类似:

```text
File /lib/x86_64-linux-gnu/libcuda.so.570.153.02 is empty
```

当前判断:
- 这是历史残留告警
- 当前动态链接器实际解析到的是 `580.105.08` 那套真实库
- 这次构建和 GPU 特征提取并没有被它阻塞

也就是说:
- 现在不用为了这条告警中断使用
- 但如果后面系统驱动再次变化, 值得回头清理这些残留空文件

### 10.3 `CMAKE_CUDA_ARCHITECTURES=80` 是针对当前 GPU 的

这次用的是 A800, 所以这里固定成了 `80`。

如果以后换到别的 GPU:
- 不要盲复用这个值
- 需要按目标 GPU 架构重新设置

---

## 11. 最短复用路径

如果只是想最快复用本次结果, 直接记住下面两条就够了:

```bash
/workspace/colmap-cuda-install-3.12.6/bin/colmap -h | head -n 4
```

```bash
python3 convert.py \
  -s data/jm-sd2 \
  --video_fps 24 \
  --colmap_executable /workspace/colmap-cuda-install-3.12.6/bin/colmap
```

第一条确认你正在使用 CUDA 版。
第二条直接把它接进当前仓库流程。
