#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Lyra generated root -> FastGS 一键训练脚本
#
# 这份脚本面向已经包含:
#   view_id/{rgb,pose,intrinsics}/scene_stem.*
# 的 Lyra generated root.
#
# 它不会再跑 COLMAP.
# 它只是把常用 train.py 参数包装成一个更短、更稳的入口.
# ============================================================

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

SOURCE_PATH="$REPO_ROOT/../lyra/assets/demo/static/diffusion_output_generated_my"
MODEL_PATH=""
PIXI_BIN="pixi"
PHASE="train"

RESOLUTION=2
ITERATIONS=30000
EVAL=1
OVERWRITE=0
ITERATION=-1
MULT_WAS_SET=0

# 这组参数与 train.py 当前默认值保持一致.
# 这样脚本既能作为“一键入口", 也不会暗中篡改底层默认行为.
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
  bash scripts/run_lyra_fastgs.sh [选项]

默认行为:
  - 直接读取 Lyra generated root
  - 使用 `--eval -r 2`
  - 将输出写到 `output/<source_dir>_fastgs`
  - 默认 `--phase train`, 只训练

常用示例:
  1) 直接启动当前示例路径:
     bash scripts/run_lyra_fastgs.sh

  2) 指定别的 Lyra 根目录:
     bash scripts/run_lyra_fastgs.sh \
       --source-path /workspace/lyra/assets/demo/static/diffusion_output_generated_my

  3) 做 10 iter smoke test:
     bash scripts/run_lyra_fastgs.sh \
       --iterations 10 \
       --model-path output/lyra_script_smoke \
       --overwrite

  4) 对已有模型做一键评估(render + metrics):
     bash scripts/run_lyra_fastgs.sh \
       --phase evaluate \
       --model-path output/lyra_script_smoke \
       --overwrite

  5) 从训练一路跑到评估:
     bash scripts/run_lyra_fastgs.sh \
       --phase all \
       --model-path output/dj_style_full_eval \
       --overwrite

  6) 不做 eval 切分:
     bash scripts/run_lyra_fastgs.sh --no-eval

  7) 覆盖 FastGS 高频训练参数:
     bash scripts/run_lyra_fastgs.sh \
       -r 1 \
       --densification_interval 500 \
       --grad_abs_thresh 0.0008 \
       --dense 0.01 \
       --mult 0.7

选项:
  --phase <train|render|metrics|evaluate|all>
                                执行阶段, 默认 train
  --source-path <path>            Lyra generated root
  --model-path <path>             训练输出目录, 默认 output/<source_dir>_fastgs
  --pixi-bin <path>               pixi 可执行文件, 默认 pixi
  -r, --resolution <1|2|4|8|宽度> 训练分辨率, 默认 2
  --iterations <n>                训练迭代数, 默认 30000
  --iteration <n>                 render.py 读取的迭代号, 默认 -1(最新)
  --densification_interval <n>    FastGS 增点间隔, 默认 100
  --loss_thresh <x>               FastGS 高误差像素阈值, 默认 0.1
  --grad_thresh <x>               clone 梯度阈值, 默认 0.0002
  --grad_abs_thresh <x>           split 梯度阈值, 默认 0.0012
  --highfeature_lr <x>            高阶 SH 学习率入口值, 默认 0.005
  --lowfeature_lr <x>             低阶 SH 学习率, 默认 0.0025
  --dense <x>                     clone / split 尺寸分界, 默认 0.001
  --mult <x>                      compact box 系数, 默认 0.5
  --optimizer_type <name>         优化器类型, 默认 default
  --eval                          显式开启 eval 切分
  --no-eval                       关闭 eval 切分
  --overwrite                     按阶段覆盖已有训练/评估产物
  -h, --help                      显示帮助

说明:
  - `--phase evaluate` 会执行 `render.py -> metrics.py`.
  - `--phase all` 会执行 `train.py -> render.py -> metrics.py`.
  - `metrics.py` 依赖 test 渲染结果, 因此 `--phase all` 必须保留 `--eval`.
  - `metrics.py` 首次运行时, 可能会下载 LPIPS 的 VGG 权重.
EOF
}

log() {
  printf '[lyra-fastgs] %s\n' "$*"
}

fail() {
  printf '[lyra-fastgs] ERROR: %s\n' "$*" >&2
  exit 1
}

normalize_path() {
  python3 - "$REPO_ROOT" "$1" <<'PY'
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
raw_path = Path(sys.argv[2]).expanduser()

if not raw_path.is_absolute():
    raw_path = repo_root / raw_path

print(raw_path.resolve(strict=False))
PY
}

default_model_path() {
  python3 - "$REPO_ROOT" "$1" <<'PY'
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
source_path = Path(sys.argv[2])
source_name = source_path.name or "lyra_generated"
print((repo_root / "output" / f"{source_name}_fastgs").resolve(strict=False))
PY
}

read_saved_mult() {
  python3 - "$1" "$MULT" <<'PY'
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

require_dir() {
  local path="$1"
  [[ -d "$path" ]] || fail "目录不存在: $path"
}

safe_remove() {
  local target="$1"

  [[ -e "$target" ]] || return 0

  case "$target" in
    "$REPO_ROOT"/output/*)
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

require_model_dir() {
  require_dir "$MODEL_PATH"
  require_dir "$MODEL_PATH/point_cloud"
}

train_model() {
  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧训练输出"
    safe_remove "$MODEL_PATH"
  elif [[ -e "$MODEL_PATH" ]]; then
    fail "训练输出目录已存在: $MODEL_PATH, 如需覆盖请加 --overwrite"
  fi

  log "Lyra source path: $SOURCE_PATH"
  log "Model path: $MODEL_PATH"
  log "Eval split: $EVAL"
  log "Resolution: $RESOLUTION"
  log "Iterations: $ITERATIONS"

  train_cmd=(
    "$PIXI_BIN" run python train.py
    -s "$SOURCE_PATH"
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

  render_cmd=(
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
    --model-path)
      MODEL_PATH="$2"
      shift 2
      ;;
    --pixi-bin)
      PIXI_BIN="$2"
      shift 2
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
  train|render|metrics|evaluate|all)
    ;;
  *)
    fail "--phase 只支持 train / render / metrics / evaluate / all"
    ;;
esac

require_cmd python3
require_cmd "$PIXI_BIN"

[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || fail "--iterations 必须是 >= 1 的整数"
[[ "$ITERATION" =~ ^-?[0-9]+$ ]] || fail "--iteration 必须是整数"
[[ "$DENSIFICATION_INTERVAL" =~ ^[1-9][0-9]*$ ]] || fail "--densification_interval 必须是 >= 1 的整数"

SOURCE_PATH=$(normalize_path "$SOURCE_PATH")

if [[ -z "$MODEL_PATH" ]]; then
  MODEL_PATH=$(default_model_path "$SOURCE_PATH")
else
  MODEL_PATH=$(normalize_path "$MODEL_PATH")
fi

if [[ "$PHASE" == "train" || "$PHASE" == "all" ]]; then
  require_dir "$SOURCE_PATH"
fi

if [[ "$PHASE" == "render" || "$PHASE" == "evaluate" || "$PHASE" == "all" ]]; then
  require_cmd ffmpeg
fi

if [[ "$PHASE" == "all" && "$EVAL" -eq 0 ]]; then
  fail "--phase all 需要保留 --eval, 否则 metrics.py 没有 test 集可评估"
fi

case "$PHASE" in
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
    train_model
    render_model
    metrics_model
    ;;
esac
