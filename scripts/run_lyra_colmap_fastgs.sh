#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Lyra generated root -> COLMAP 传统流程 -> FastGS
#
# 这份脚本刻意不使用 Lyra 自带的 pose / intrinsics.
# 它会:
# 1. 从 rgb 视频抽帧
# 2. 用 COLMAP 恢复相机与稀疏点云
# 3. 启动 FastGS 训练
# 4. 可选执行 render / metrics
# ============================================================

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

SOURCE_PATH="$REPO_ROOT/../lyra/assets/demo/static/diffusion_output_generated_my"
FASTGS_ROOT=""
MODEL_PATH=""

PHASE="prepare"
PIXI_BIN="pixi"
PYTHON_BIN="python3"
COLMAP_BIN="/workspace/colmap-cuda-install-3.12.6/bin/colmap"
FFMPEG_BIN="ffmpeg"

CAMERA_MODEL="SIMPLE_PINHOLE"
VIDEO_FPS=24
USE_GPU=1
COLMAP_GPU_INDEX=""

RESOLUTION=1
ITERATIONS=30000
EVAL=1
OVERWRITE=0
ITERATION=-1
MULT_WAS_SET=0

# 这组参数与 train.py 当前默认值保持一致.
DENSIFICATION_INTERVAL=100
LOSS_THRESH=0.1
GRAD_THRESH=0.0002
GRAD_ABS_THRESH=0.0012
HIGHFEATURE_LR=0.005
LOWFEATURE_LR=0.0025
DENSE=0.001
MULT=0.5
OPTIMIZER_TYPE="default"

usage() {
  cat <<'EOF'
用法:
  bash scripts/run_lyra_colmap_fastgs.sh [选项]

默认行为:
  - 不读取 Lyra 自带 pose/intrinsics
  - 用 `convert.py` 从 rgb 视频抽帧并跑 COLMAP
  - 默认 `--phase prepare`
  - 默认训练分辨率 `-r 1`
  - 默认把数据写到 `data/<source_dir>_colmap_fastgs`
  - 默认把模型写到 `output/<source_dir>_colmap_fastgs`

常用示例:
  1) 只做 COLMAP 数据准备:
     bash scripts/run_lyra_colmap_fastgs.sh --phase prepare --overwrite

  2) 从准备一路跑到评估:
     bash scripts/run_lyra_colmap_fastgs.sh --phase all --overwrite

  3) 对已有 COLMAP 数据只做训练:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --phase train \
       --fastgs-root data/diffusion_output_generated_my_colmap_fastgs \
       --model-path output/lyra_colmap_r1_30000 \
       --overwrite

  4) 对已有模型做评估:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --phase evaluate \
       --model-path output/lyra_colmap_r1_30000 \
       --overwrite

  5) 显式改抽帧率或相机模型:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --video-fps 24 \
       --camera-model SIMPLE_PINHOLE

  6) 显式指定 CUDA COLMAP 使用哪几张卡:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --phase prepare \
       --colmap-gpu-index 0,1

选项:
  --phase <prepare|train|render|metrics|evaluate|all>
                                执行阶段, 默认 prepare
  --source-path <path>          Lyra 原始根目录, 只读取 rgb 视频
  --fastgs-root <path>          COLMAP / FastGS 数据目录
  --model-path <path>           训练输出目录
  --python-bin <path>           Python 可执行文件, 默认 python3
  --pixi-bin <path>             pixi 可执行文件, 默认 pixi
  --colmap-bin <path>           COLMAP 可执行文件
  --ffmpeg-bin <path>           ffmpeg 可执行文件
  --camera-model <name>         COLMAP 相机模型, 默认 SIMPLE_PINHOLE
  --video-fps <x>               抽帧帧率, 默认 24
  --colmap-gpu-index <csv>      透传给 COLMAP 的 GPU index, 例如 0 或 0,1
  --no-gpu                      让 convert.py / COLMAP 走 CPU
  -r, --resolution <1|2|4|8|宽度> 训练分辨率, 默认 1
  --iterations <n>              训练迭代数, 默认 30000
  --iteration <n>               render.py 读取的迭代号, 默认 -1(最新)
  --densification_interval <n>  FastGS 增点间隔, 默认 100
  --loss_thresh <x>             FastGS 高误差像素阈值, 默认 0.1
  --grad_thresh <x>             clone 梯度阈值, 默认 0.0002
  --grad_abs_thresh <x>         split 梯度阈值, 默认 0.0012
  --highfeature_lr <x>          高阶 SH 学习率入口值, 默认 0.005
  --lowfeature_lr <x>           低阶 SH 学习率, 默认 0.0025
  --dense <x>                   clone / split 尺寸分界, 默认 0.001
  --mult <x>                    compact box 系数, 默认 0.5
  --optimizer_type <name>       优化器类型, 默认 default
  --eval                        显式开启 eval 切分
  --no-eval                     关闭 eval 切分
  --overwrite                   按阶段覆盖已有产物
  -h, --help                    显示帮助

说明:
  - 这条流程只会使用 `rgb/*.mp4`, 不会读取 Lyra 自带 pose/intrinsics.
  - 默认 `--video-fps 24`, 是为了尽量接近 Lyra 原视频的 121 帧长度.
  - 对 synthetic / generated 数据, 当前默认 `SIMPLE_PINHOLE` 更稳.
EOF
}

log() {
  printf '[lyra-colmap-fastgs] %s\n' "$*"
}

fail() {
  printf '[lyra-colmap-fastgs] ERROR: %s\n' "$*" >&2
  exit 1
}

normalize_path() {
  "$PYTHON_BIN" - "$REPO_ROOT" "$1" <<'PY'
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
raw_path = Path(sys.argv[2]).expanduser()

if not raw_path.is_absolute():
    raw_path = repo_root / raw_path

print(raw_path.resolve(strict=False))
PY
}

default_fastgs_root() {
  "$PYTHON_BIN" - "$REPO_ROOT" "$1" <<'PY'
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
source_path = Path(sys.argv[2])
source_name = source_path.name or "lyra_generated"
print((repo_root / "data" / f"{source_name}_colmap_fastgs").resolve(strict=False))
PY
}

default_model_path() {
  "$PYTHON_BIN" - "$REPO_ROOT" "$1" <<'PY'
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
source_path = Path(sys.argv[2])
source_name = source_path.name or "lyra_generated"
print((repo_root / "output" / f"{source_name}_colmap_fastgs").resolve(strict=False))
PY
}

read_saved_mult() {
  "$PYTHON_BIN" - "$1" "$MULT" <<'PY'
from argparse import Namespace
from pathlib import Path
import sys

cfg_path = Path(sys.argv[1]) / "cfg_args"
fallback = sys.argv[2]

if not cfg_path.is_file():
    print(fallback)
    raise SystemExit(0)

text = cfg_path.read_text(encoding="utf-8")
namespace = eval(text, {"Namespace": Namespace})
value = getattr(namespace, "mult", fallback)
print(value)
PY
}

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "缺少命令: $name"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "文件不存在: $path"
}

require_dir() {
  local path="$1"
  [[ -d "$path" ]] || fail "目录不存在: $path"
}

safe_remove() {
  local target="$1"

  [[ -e "$target" ]] || return 0

  case "$target" in
    "$REPO_ROOT"/data/*|"$REPO_ROOT"/output/*)
      rm -rf -- "$target"
      ;;
    *)
      fail "拒绝删除非受控路径: $target"
      ;;
  esac
}

run_cmd() {
  log "执行: $*"
  "$@"
}

clear_render_outputs() {
  safe_remove "$MODEL_PATH/train"
  safe_remove "$MODEL_PATH/test"
  safe_remove "$MODEL_PATH/results.json"
  safe_remove "$MODEL_PATH/per_view.json"
}

clear_metric_outputs() {
  safe_remove "$MODEL_PATH/results.json"
  safe_remove "$MODEL_PATH/per_view.json"
}

require_prepared_dataset() {
  require_dir "$FASTGS_ROOT"
  require_dir "$FASTGS_ROOT/images"
  require_dir "$FASTGS_ROOT/sparse/0"
}

require_model_dir() {
  require_dir "$MODEL_PATH"
  require_dir "$MODEL_PATH/point_cloud"
}

prepare_dataset() {
  local convert_cmd=(
    "$PYTHON_BIN" convert.py
    --source_path "$FASTGS_ROOT"
    --video_path "$SOURCE_PATH"
    --video_fps "$VIDEO_FPS"
    --camera "$CAMERA_MODEL"
    --colmap_executable "$COLMAP_BIN"
    --ffmpeg_executable "$FFMPEG_BIN"
  )

  if (( USE_GPU == 0 )); then
    convert_cmd+=(--no_gpu)
  elif [[ -n "$COLMAP_GPU_INDEX" ]]; then
    convert_cmd+=(--colmap_gpu_index "$COLMAP_GPU_INDEX")
  fi

  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧 COLMAP / FastGS 数据目录"
    safe_remove "$FASTGS_ROOT"
    convert_cmd+=(--overwrite)
  elif [[ -e "$FASTGS_ROOT" ]]; then
    fail "数据目录已存在: $FASTGS_ROOT, 如需重建请加 --overwrite"
  fi

  log "Lyra rgb source path: $SOURCE_PATH"
  log "COLMAP / FastGS data root: $FASTGS_ROOT"
  log "COLMAP camera model: $CAMERA_MODEL"
  log "Video fps: $VIDEO_FPS"
  log "Use GPU in convert.py: $USE_GPU"
  if [[ -n "$COLMAP_GPU_INDEX" ]]; then
    log "COLMAP GPU index: $COLMAP_GPU_INDEX"
  fi

  run_cmd "${convert_cmd[@]}"
  require_prepared_dataset
}

train_model() {
  require_prepared_dataset

  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧训练输出"
    safe_remove "$MODEL_PATH"
  elif [[ -e "$MODEL_PATH" ]]; then
    fail "训练输出目录已存在: $MODEL_PATH, 如需覆盖请加 --overwrite"
  fi

  log "Training data root: $FASTGS_ROOT"
  log "Model path: $MODEL_PATH"
  log "Eval split: $EVAL"
  log "Resolution: $RESOLUTION"
  log "Iterations: $ITERATIONS"

  local train_cmd=(
    "$PIXI_BIN" run python train.py
    -s "$FASTGS_ROOT"
    -i images
    -m "$MODEL_PATH"
    --iterations "$ITERATIONS"
    -r "$RESOLUTION"
    --densification_interval "$DENSIFICATION_INTERVAL"
    --loss_thresh "$LOSS_THRESH"
    --grad_thresh "$GRAD_THRESH"
    --grad_abs_thresh "$GRAD_ABS_THRESH"
    --highfeature_lr "$HIGHFEATURE_LR"
    --lowfeature_lr "$LOWFEATURE_LR"
    --dense "$DENSE"
    --mult "$MULT"
    --optimizer_type "$OPTIMIZER_TYPE"
  )

  if (( EVAL )); then
    train_cmd+=(--eval)
  fi

  run_cmd "${train_cmd[@]}"
}

render_model() {
  local render_mult="$MULT"
  require_model_dir

  if (( ! MULT_WAS_SET )); then
    render_mult=$(read_saved_mult "$MODEL_PATH")
  fi

  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧渲染与指标产物"
    clear_render_outputs
  fi

  log "Render model path: $MODEL_PATH"
  log "Render iteration: $ITERATION"
  log "Render mult: $render_mult"

  local render_cmd=(
    "$PIXI_BIN" run python render.py
    -m "$MODEL_PATH"
    --iteration "$ITERATION"
    --mult "$render_mult"
  )

  run_cmd "${render_cmd[@]}"
}

metrics_model() {
  require_model_dir

  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧指标结果"
    clear_metric_outputs
  fi

  [[ -d "$MODEL_PATH/test" ]] || fail "缺少 $MODEL_PATH/test. 请先执行 `--phase render` 或 `--phase evaluate`."

  if ! find "$MODEL_PATH/test" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
    fail "当前模型没有可评估的 test 渲染结果. 请确认训练时开启了 --eval, 并先执行 render 阶段."
  fi

  run_cmd "$PIXI_BIN" run python metrics.py -m "$MODEL_PATH"
}

while (( $# > 0 )); do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --source-path)
      SOURCE_PATH="$2"
      shift 2
      ;;
    --fastgs-root)
      FASTGS_ROOT="$2"
      shift 2
      ;;
    --model-path)
      MODEL_PATH="$2"
      shift 2
      ;;
    --python-bin)
      PYTHON_BIN="$2"
      shift 2
      ;;
    --pixi-bin)
      PIXI_BIN="$2"
      shift 2
      ;;
    --colmap-bin)
      COLMAP_BIN="$2"
      shift 2
      ;;
    --ffmpeg-bin)
      FFMPEG_BIN="$2"
      shift 2
      ;;
    --camera-model)
      CAMERA_MODEL="$2"
      shift 2
      ;;
    --video-fps)
      VIDEO_FPS="$2"
      shift 2
      ;;
    --colmap-gpu-index)
      COLMAP_GPU_INDEX="$2"
      shift 2
      ;;
    --no-gpu)
      USE_GPU=0
      shift
      ;;
    -r|--resolution)
      RESOLUTION="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --iteration)
      ITERATION="$2"
      shift 2
      ;;
    --densification_interval)
      DENSIFICATION_INTERVAL="$2"
      shift 2
      ;;
    --loss_thresh)
      LOSS_THRESH="$2"
      shift 2
      ;;
    --grad_thresh)
      GRAD_THRESH="$2"
      shift 2
      ;;
    --grad_abs_thresh)
      GRAD_ABS_THRESH="$2"
      shift 2
      ;;
    --highfeature_lr)
      HIGHFEATURE_LR="$2"
      shift 2
      ;;
    --lowfeature_lr)
      LOWFEATURE_LR="$2"
      shift 2
      ;;
    --dense)
      DENSE="$2"
      shift 2
      ;;
    --mult)
      MULT="$2"
      MULT_WAS_SET=1
      shift 2
      ;;
    --optimizer_type)
      OPTIMIZER_TYPE="$2"
      shift 2
      ;;
    --eval)
      EVAL=1
      shift
      ;;
    --no-eval)
      EVAL=0
      shift
      ;;
    --overwrite)
      OVERWRITE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "未知参数: $1"
      ;;
  esac
done

case "$PHASE" in
  prepare|train|render|metrics|evaluate|all)
    ;;
  *)
    fail "--phase 只支持 prepare / train / render / metrics / evaluate / all"
    ;;
esac

require_cmd "$PYTHON_BIN"
require_cmd "$PIXI_BIN"

"$PYTHON_BIN" - <<'PY' "$VIDEO_FPS"
import sys

value = float(sys.argv[1])
if value <= 0:
    raise SystemExit(1)
PY

[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || fail "--iterations 必须是 >= 1 的整数"
[[ "$ITERATION" =~ ^-?[0-9]+$ ]] || fail "--iteration 必须是整数"
[[ "$DENSIFICATION_INTERVAL" =~ ^[1-9][0-9]*$ ]] || fail "--densification_interval 必须是 >= 1 的整数"

case "$CAMERA_MODEL" in
  SIMPLE_PINHOLE|PINHOLE|OPENCV)
    ;;
  *)
    fail "--camera-model 只支持 SIMPLE_PINHOLE / PINHOLE / OPENCV"
    ;;
esac

SOURCE_PATH=$(normalize_path "$SOURCE_PATH")

if [[ -z "$FASTGS_ROOT" ]]; then
  FASTGS_ROOT=$(default_fastgs_root "$SOURCE_PATH")
else
  FASTGS_ROOT=$(normalize_path "$FASTGS_ROOT")
fi

if [[ -z "$MODEL_PATH" ]]; then
  MODEL_PATH=$(default_model_path "$SOURCE_PATH")
else
  MODEL_PATH=$(normalize_path "$MODEL_PATH")
fi

if [[ "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  require_dir "$SOURCE_PATH"
  if [[ "$FFMPEG_BIN" == */* ]]; then
    require_file "$FFMPEG_BIN"
  else
    require_cmd "$FFMPEG_BIN"
  fi

  if [[ "$COLMAP_BIN" == */* ]]; then
    require_file "$COLMAP_BIN"
  else
    require_cmd "$COLMAP_BIN"
  fi
fi

case "$PHASE" in
  prepare)
    prepare_dataset
    ;;
  train)
    train_model
    ;;
  render)
    render_model
    ;;
  metrics)
    metrics_model
    ;;
  evaluate)
    render_model
    metrics_model
    ;;
  all)
    if (( EVAL == 0 )); then
      fail "--phase all 需要保留 --eval, 否则 metrics.py 没有 test 集可评估"
    fi
    prepare_dataset
    train_model
    render_model
    metrics_model
    ;;
esac
