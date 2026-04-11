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

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd -P)

SOURCE_PATH="$REPO_ROOT/../lyra/assets/demo/static/diffusion_output_generated_my"
FASTGS_ROOT=""
MODEL_PATH=""
MASK_DIR=""
PREPARED_SOURCE_MODE=0
START_CHECKPOINT=""
VIDEO_ITERATIONS=""
VIDEO_OUTPUT_FPS=24
VIDEO_SETS="both"

PHASE="prepare"
PIXI_BIN="pixi"
PYTHON_BIN="python3"
COLMAP_BIN="/workspace/colmap-cuda-install-3.12.6/bin/colmap"
FFMPEG_BIN="ffmpeg"

CAMERA_MODEL="SIMPLE_PINHOLE"
VIDEO_FPS=24
VIDEO_FRAME_STEP=0
VIDEO_NAMING="grouped"
FINAL_IMAGE_NAMING="numeric"
USE_GPU=1
COLMAP_GPU_INDEX=""
MATCHER="exhaustive"

RESOLUTION=1
ITERATIONS=30000
EVAL=1
OVERWRITE=0
ITERATION=-1
MULT_WAS_SET=0

# 这组参数与 train.py 当前默认值保持一致.
DENSIFICATION_INTERVAL=100
OPACITY_RESET_INTERVAL=3000
DENSIFY_UNTIL_ITER=15000
POSITION_LR_MAX_STEPS=30000
LOSS_THRESH=0.1
GRAD_THRESH=0.0002
GRAD_ABS_THRESH=0.0012
HIGHFEATURE_LR=0.005
LOWFEATURE_LR=0.0025
DENSE=0.001
MULT=0.5
OPTIMIZER_TYPE="default"
SEED=0

usage() {
  cat <<'EOF'
用法:
  bash scripts/run_lyra_colmap_fastgs.sh [选项]

默认行为:
  - 不读取 Lyra 自带 pose/intrinsics
  - 用 `convert.py` 从 rgb 视频抽帧并跑 COLMAP
  - 如果 `--source-path` 本身已经是 `images + sparse/0` 的 COLMAP / FastGS 根目录, 则自动跳过 `convert.py`
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

  5.1) 按固定帧步长抽帧, 并切到顺序匹配:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --video-frame-step 3 \
       --video-naming interleaved \
       --matcher sequential

  6) 显式指定 CUDA COLMAP 使用哪几张卡:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --phase prepare \
       --colmap-gpu-index 0,1

  7) 直接复用已准备好的 COLMAP 根目录:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --source-path /home/rais/FreeFix/data/my4_fullcolmap \
       --mask-dir /home/rais/FreeFix/data/my4_fullcolmap/masks \
       --phase all \
       --model-path output/my4_fullcolmap_fastgs \
       --overwrite

  8) 从 checkpoint 续训到 50000, 并在 40000 / 50000 导出 mp4:
     bash scripts/run_lyra_colmap_fastgs.sh \
       --source-path /home/rais/FreeFix/data/my4_fullcolmap \
       --phase all \
       --start-checkpoint output/my4_fullcolmap_fastgs/checkpoints/ckpt_30000.pth \
       --iterations 50000 \
       --video-iterations 40000,50000 \
       --video-output-fps 24 \
       --model-path output/my4_fullcolmap_final \
       --overwrite

选项:
  --phase <prepare|train|render|metrics|evaluate|all>
                                执行阶段, 默认 prepare
  --source-path <path>          Lyra 原始视频根目录, 或已准备好的 COLMAP / FastGS 根目录
  --fastgs-root <path>          COLMAP / FastGS 数据目录
  --model-path <path>           训练输出目录
  --mask-dir <path>             训练 mask 目录. 如不传, 仅自动识别已有且非空的 masks 目录
  --start-checkpoint <path>     从已有 checkpoint 继续训练
  --python-bin <path>           Python 可执行文件, 默认 python3
  --pixi-bin <path>             pixi 可执行文件, 默认 pixi
  --colmap-bin <path>           COLMAP 可执行文件
  --ffmpeg-bin <path>           ffmpeg 可执行文件
  --camera-model <name>         COLMAP 相机模型, 默认 SIMPLE_PINHOLE
  --video-fps <x>               抽帧帧率, 默认 24
  --video-frame-step <n>        每隔 n 帧抽 1 帧. > 0 时优先于 --video-fps
  --video-naming <grouped|interleaved>
                                抽帧命名布局. interleaved 会把同一时刻的多视角排在一起
  --final-image-naming <preserve|numeric>
                                抽帧后在 input/ 中的最终命名. 默认 numeric, 会写成 000001.jpg 这类连续编号
  --matcher <exhaustive|sequential>
                                COLMAP matching 策略, 默认 exhaustive
  --colmap-gpu-index <csv>      透传给 COLMAP 的 GPU index, 例如 0 或 0,1
  --no-gpu                      让 convert.py / COLMAP 走 CPU
  -r, --resolution <1|2|4|8|宽度> 训练分辨率, 默认 1
  --iterations <n>              训练迭代数, 默认 30000
  --iteration <n>               render.py 读取的迭代号, 默认 -1(最新)
  --densification_interval <n>  FastGS 增点间隔, 默认 100
  --opacity_reset_interval <n>  FastGS opacity 重置间隔, 默认 3000
  --densify_until_iter <n>      FastGS densify 结束迭代, 默认 15000
  --position_lr_max_steps <n>   xyz 学习率衰减步数, 默认 30000
  --loss_thresh <x>             FastGS 高误差像素阈值, 默认 0.1
  --grad_thresh <x>             clone 梯度阈值, 默认 0.0002
  --grad_abs_thresh <x>         split 梯度阈值, 默认 0.0012
  --highfeature_lr <x>          高阶 SH 学习率入口值, 默认 0.005
  --lowfeature_lr <x>           低阶 SH 学习率, 默认 0.0025
  --dense <x>                   clone / split 尺寸分界, 默认 0.001
  --mult <x>                    compact box 系数, 默认 0.5
  --optimizer_type <name>       优化器类型, 默认 default
  --seed <n>                    训练随机种子, 默认 0
  --eval                        显式开启 eval 切分
  --no-eval                     关闭 eval 切分
  --video-iterations <csv>      训练后需要 render + 导视频的迭代, 例如 40000,50000
  --video-output-fps <n>        导出 mp4 的帧率, 默认 24
  --video-sets <train|test|both>
                                导出哪些集合的视频, 默认 both
  --overwrite                   按阶段覆盖已有产物
  -h, --help                    显示帮助

说明:
  - 这条流程只会使用 `rgb/*.mp4`, 不会读取 Lyra 自带 pose/intrinsics.
  - 默认 `--video-fps 24`, 是为了尽量接近 Lyra 原视频的 121 帧长度.
  - 如果传了 `--video-frame-step > 0`, 会按解码后的帧序号抽样, 不再按时间轴 `fps=` 采样.
  - 如果传了 `--video-naming interleaved`, 会把输出文件名重排成“同一时刻的多视角连续出现”, 更适合做 sequential matcher 对照.
  - 默认 `--final-image-naming numeric`, 会把 input/ 与后续 COLMAP 输出都稳定成 `000001.jpg` 这类连续 6 位编号.
  - 对 synthetic / generated 数据, 当前默认 `SIMPLE_PINHOLE` 更稳.
  - 如果 `--source-path` 已经包含 `images/` 和 `sparse/0/`, `prepare` 阶段会退化为数据校验, 不再重复跑 `convert.py`.
  - 如果 `--mask-dir` 为空, 训练阶段只会尝试读取已有且非空的 `<fastgs-root>/masks` 或 `<source-path>/masks`.
  - `prepare` 阶段当前只抽 RGB 帧, 不会把 `rendering_4D_maps/merged_mask.mp4` 自动转成训练 mask.
  - mask 文件需要与训练图同名, 或至少同 stem(扩展名可不同).
  - 如果传了 `--video-iterations`, 脚本会先确保这些迭代在训练期被保存成 point cloud / checkpoint.
  - `--phase all` 下若传了 `--video-iterations`, 会在训练结束后逐个 render 指定迭代, 并额外导出 mp4.
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

normalize_iteration_csv() {
  local raw_csv="$1"
  local max_iteration="$2"

  "$PYTHON_BIN" - "$raw_csv" "$max_iteration" <<'PY'
import sys

raw_csv = sys.argv[1].strip()
max_iteration = int(sys.argv[2])

if not raw_csv:
    raise SystemExit(0)

seen = set()
values = []
for raw_part in raw_csv.split(","):
    part = raw_part.strip()
    if not part:
        continue

    value = int(part)
    if value < 1:
        raise SystemExit(f"invalid iteration in csv: {value}")
    if value > max_iteration:
        raise SystemExit(f"video iteration {value} exceeds training target {max_iteration}")

    if value not in seen:
        seen.add(value)
        values.append(value)

for value in sorted(values):
    print(value)
PY
}

resolve_default_colmap_bin() {
  # 这份脚本历史上偏向当前作者机器上的 CUDA COLMAP 安装前缀.
  # 但如果那条默认路径不存在, 更稳的策略是:
  # 1. 先尝试这台机器上已经验证可用的用户级安装前缀.
  # 2. 再回退到 PATH 里的 `colmap`.
  if [[ "$COLMAP_BIN" == "/workspace/colmap-cuda-install-3.12.6/bin/colmap" && ! -f "$COLMAP_BIN" ]]; then
    local user_colmap_env="$HOME/.local/opt/colmap-env/bin/colmap"
    if [[ -f "$user_colmap_env" ]]; then
      COLMAP_BIN="$user_colmap_env"
      log "默认 CUDA COLMAP 路径不存在, 自动回退到用户级 colmap-env: $COLMAP_BIN"
      return 0
    fi

    if command -v colmap >/dev/null 2>&1; then
      COLMAP_BIN="colmap"
      log "默认 CUDA COLMAP 路径不存在, 自动回退到 PATH 中的 colmap"
    fi
  fi
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
  safe_remove "$MODEL_PATH/videos"
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

is_prepared_dataset_root() {
  local path="$1"
  [[ -d "$path/images" && -d "$path/sparse/0" ]]
}

require_model_dir() {
  require_dir "$MODEL_PATH"
  require_dir "$MODEL_PATH/point_cloud"
}

directory_has_files() {
  local path="$1"

  [[ -d "$path" ]] || return 1

  while IFS= read -r _; do
    return 0
  done < <(find "$path" -maxdepth 1 -type f -print)

  return 1
}

resolve_default_mask_dir() {
  if [[ -n "$MASK_DIR" ]]; then
    return 0
  fi

  # 这里只接“现成且非空”的训练 mask 目录.
  # 空目录不应该把训练误导进 mask 模式.
  if directory_has_files "$FASTGS_ROOT/masks"; then
    MASK_DIR="$FASTGS_ROOT/masks"
    log "自动识别到训练 mask 目录: $MASK_DIR"
    return 0
  fi

  if directory_has_files "$SOURCE_PATH/masks"; then
    MASK_DIR="$SOURCE_PATH/masks"
    log "自动识别到训练 mask 目录: $MASK_DIR"
  fi
}

prepare_dataset() {
  if (( PREPARED_SOURCE_MODE )); then
    log "检测到 source-path 已经是可训练的 COLMAP / FastGS 根目录, 跳过 convert.py"
    log "Prepared dataset root: $FASTGS_ROOT"
    require_prepared_dataset
    return 0
  fi

  local convert_cmd=(
    "$PYTHON_BIN" convert.py
    --source_path "$FASTGS_ROOT"
    --video_path "$SOURCE_PATH"
    --video_fps "$VIDEO_FPS"
    --video_frame_step "$VIDEO_FRAME_STEP"
    --video_naming "$VIDEO_NAMING"
    --final_image_naming "$FINAL_IMAGE_NAMING"
    --camera "$CAMERA_MODEL"
    --colmap_executable "$COLMAP_BIN"
    --ffmpeg_executable "$FFMPEG_BIN"
    --matcher "$MATCHER"
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
  if (( VIDEO_FRAME_STEP > 0 )); then
    log "Video frame step: $VIDEO_FRAME_STEP"
  fi
  log "Video naming: $VIDEO_NAMING"
  log "Final image naming: $FINAL_IMAGE_NAMING"
  log "COLMAP matcher: $MATCHER"
  log "Use GPU in convert.py: $USE_GPU"
  if [[ -n "$COLMAP_GPU_INDEX" ]]; then
    log "COLMAP GPU index: $COLMAP_GPU_INDEX"
  fi

  run_cmd "${convert_cmd[@]}"
  require_prepared_dataset
}

train_model() {
  require_prepared_dataset
  resolve_default_mask_dir

  if [[ -n "$MASK_DIR" ]]; then
    require_dir "$MASK_DIR"
  fi

  if (( OVERWRITE )); then
    if [[ -n "$START_CHECKPOINT" ]]; then
      log "检测到 --overwrite + --start-checkpoint, 保留现有模型目录以便续训, 仅清理旧渲染/指标产物"
      clear_render_outputs
    else
      log "检测到 --overwrite, 准备清理旧训练输出"
      safe_remove "$MODEL_PATH"
    fi
  elif [[ -e "$MODEL_PATH" && -z "$START_CHECKPOINT" ]]; then
    fail "训练输出目录已存在: $MODEL_PATH, 如需覆盖请加 --overwrite"
  fi

  log "Training data root: $FASTGS_ROOT"
  log "Model path: $MODEL_PATH"
  if [[ -n "$MASK_DIR" ]]; then
    log "Mask dir: $MASK_DIR"
  fi
  log "Eval split: $EVAL"
  log "Resolution: $RESOLUTION"
  log "Iterations: $ITERATIONS"
  log "Schedule: densify_until=$DENSIFY_UNTIL_ITER position_lr_max_steps=$POSITION_LR_MAX_STEPS opacity_reset_interval=$OPACITY_RESET_INTERVAL"
  log "Seed: $SEED"
  if [[ -n "$START_CHECKPOINT" ]]; then
    log "Start checkpoint: $START_CHECKPOINT"
  fi

  local train_cmd=(
    "$PIXI_BIN" run python train.py
    -s "$FASTGS_ROOT"
    -i images
    -m "$MODEL_PATH"
    --iterations "$ITERATIONS"
    -r "$RESOLUTION"
    --densification_interval "$DENSIFICATION_INTERVAL"
    --opacity_reset_interval "$OPACITY_RESET_INTERVAL"
    --densify_until_iter "$DENSIFY_UNTIL_ITER"
    --position_lr_max_steps "$POSITION_LR_MAX_STEPS"
    --loss_thresh "$LOSS_THRESH"
    --grad_thresh "$GRAD_THRESH"
    --grad_abs_thresh "$GRAD_ABS_THRESH"
    --highfeature_lr "$HIGHFEATURE_LR"
    --lowfeature_lr "$LOWFEATURE_LR"
    --dense "$DENSE"
    --mult "$MULT"
    --optimizer_type "$OPTIMIZER_TYPE"
    --seed "$SEED"
  )
  local -a video_iterations=()

  if [[ -n "$MASK_DIR" ]]; then
    train_cmd+=(--mask_dir "$MASK_DIR")
  fi

  if (( EVAL )); then
    train_cmd+=(--eval)
  fi

  if [[ -n "$START_CHECKPOINT" ]]; then
    train_cmd+=(--start_checkpoint "$START_CHECKPOINT")
  fi

  if [[ -n "$VIDEO_ITERATIONS" ]]; then
    mapfile -t video_iterations < <(normalize_iteration_csv "$VIDEO_ITERATIONS" "$ITERATIONS")
    if (( ${#video_iterations[@]} > 0 )); then
      train_cmd+=(--save_iterations "${video_iterations[@]}")
      if [[ " ${video_iterations[*]} " == *" $ITERATIONS "* ]]; then
        train_cmd+=(--checkpoint_iterations "${video_iterations[@]}")
      else
        train_cmd+=(--checkpoint_iterations "${video_iterations[@]}" "$ITERATIONS")
      fi
    fi
  fi

  run_cmd "${train_cmd[@]}"
}

render_model_at_iteration() {
  local iteration_to_render="$1"
  local clear_existing="${2:-0}"
  local render_mult="$MULT"

  require_model_dir

  if (( ! MULT_WAS_SET )); then
    render_mult=$(read_saved_mult "$MODEL_PATH")
  fi

  if (( clear_existing )); then
    log "检测到 --overwrite, 准备清理旧渲染与指标产物"
    clear_render_outputs
  fi

  log "Render model path: $MODEL_PATH"
  log "Render iteration: $iteration_to_render"
  log "Render mult: $render_mult"

  local render_cmd=(
    "$PIXI_BIN" run python render.py
    -m "$MODEL_PATH"
    --iteration "$iteration_to_render"
    --mult "$render_mult"
  )

  run_cmd "${render_cmd[@]}"
}

render_model() {
  local clear_existing=0
  if (( OVERWRITE )); then
    clear_existing=1
  fi

  render_model_at_iteration "$ITERATION" "$clear_existing"
}

export_video_for_set() {
  local set_name="$1"
  local iteration_to_export="$2"
  local render_dir="$MODEL_PATH/$set_name/ours_${iteration_to_export}/renders"
  local video_dir="$MODEL_PATH/videos"
  local video_path="$video_dir/${set_name}_iter${iteration_to_export}.mp4"

  [[ -d "$render_dir" ]] || fail "缺少渲染目录: $render_dir"

  mkdir -p "$video_dir"

  run_cmd "$FFMPEG_BIN" -y \
    -framerate "$VIDEO_OUTPUT_FPS" \
    -i "$render_dir/%05d.png" \
    -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
    -c:v libx264 \
    -crf 18 \
    -pix_fmt yuv420p \
    "$video_path"
}

export_videos_for_iteration() {
  local iteration_to_export="$1"

  case "$VIDEO_SETS" in
    train)
      export_video_for_set "train" "$iteration_to_export"
      ;;
    test)
      export_video_for_set "test" "$iteration_to_export"
      ;;
    both)
      export_video_for_set "train" "$iteration_to_export"
      export_video_for_set "test" "$iteration_to_export"
      ;;
    *)
      fail "--video-sets 只支持 train / test / both"
      ;;
  esac
}

render_video_iterations() {
  local clear_existing=0
  local first_render=1
  local iteration_limit="$ITERATIONS"
  local -a video_iterations=()

  if [[ "$PHASE" == "render" || "$PHASE" == "evaluate" ]]; then
    iteration_limit="999999999"
  fi

  mapfile -t video_iterations < <(normalize_iteration_csv "$VIDEO_ITERATIONS" "$iteration_limit")
  (( ${#video_iterations[@]} > 0 )) || fail "--video-iterations 为空, 无法导出阶段视频"

  if (( OVERWRITE )); then
    clear_existing=1
  fi

  for iteration_to_render in "${video_iterations[@]}"; do
    if (( first_render )); then
      render_model_at_iteration "$iteration_to_render" "$clear_existing"
      first_render=0
    else
      render_model_at_iteration "$iteration_to_render" 0
    fi

    export_videos_for_iteration "$iteration_to_render"
  done
}

metrics_model() {
  require_model_dir

  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧指标结果"
    clear_metric_outputs
  fi

  [[ -d "$MODEL_PATH/test" ]] || fail "缺少 $MODEL_PATH/test. 请先执行 --phase render 或 --phase evaluate."

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
    --mask-dir)
      MASK_DIR="$2"
      shift 2
      ;;
    --start-checkpoint)
      START_CHECKPOINT="$2"
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
    --video-frame-step)
      VIDEO_FRAME_STEP="$2"
      shift 2
      ;;
    --video-naming)
      VIDEO_NAMING="$2"
      shift 2
      ;;
    --final-image-naming)
      FINAL_IMAGE_NAMING="$2"
      shift 2
      ;;
    --matcher)
      MATCHER="$2"
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
    --opacity_reset_interval)
      OPACITY_RESET_INTERVAL="$2"
      shift 2
      ;;
    --densify_until_iter)
      DENSIFY_UNTIL_ITER="$2"
      shift 2
      ;;
    --position_lr_max_steps)
      POSITION_LR_MAX_STEPS="$2"
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
    --seed)
      SEED="$2"
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
    --video-iterations)
      VIDEO_ITERATIONS="$2"
      shift 2
      ;;
    --video-output-fps)
      VIDEO_OUTPUT_FPS="$2"
      shift 2
      ;;
    --video-sets)
      VIDEO_SETS="$2"
      shift 2
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

[[ "$VIDEO_FRAME_STEP" =~ ^[0-9]+$ ]] || fail "--video-frame-step 必须是 >= 0 的整数"

"$PYTHON_BIN" - <<'PY' "$VIDEO_OUTPUT_FPS"
import sys

value = float(sys.argv[1])
if value <= 0:
    raise SystemExit(1)
PY

[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || fail "--iterations 必须是 >= 1 的整数"
[[ "$ITERATION" =~ ^-?[0-9]+$ ]] || fail "--iteration 必须是整数"
[[ "$DENSIFICATION_INTERVAL" =~ ^[1-9][0-9]*$ ]] || fail "--densification_interval 必须是 >= 1 的整数"
[[ "$OPACITY_RESET_INTERVAL" =~ ^[1-9][0-9]*$ ]] || fail "--opacity_reset_interval 必须是 >= 1 的整数"
[[ "$DENSIFY_UNTIL_ITER" =~ ^[1-9][0-9]*$ ]] || fail "--densify_until_iter 必须是 >= 1 的整数"
[[ "$POSITION_LR_MAX_STEPS" =~ ^[1-9][0-9]*$ ]] || fail "--position_lr_max_steps 必须是 >= 1 的整数"
[[ "$SEED" =~ ^[0-9]+$ ]] || fail "--seed 必须是 >= 0 的整数"

case "$CAMERA_MODEL" in
  SIMPLE_PINHOLE|PINHOLE|OPENCV)
    ;;
  *)
    fail "--camera-model 只支持 SIMPLE_PINHOLE / PINHOLE / OPENCV"
    ;;
esac

case "$VIDEO_NAMING" in
  grouped|interleaved)
    ;;
  *)
    fail "--video-naming 只支持 grouped / interleaved"
    ;;
esac

case "$FINAL_IMAGE_NAMING" in
  preserve|numeric)
    ;;
  *)
    fail "--final-image-naming 只支持 preserve / numeric"
    ;;
esac

case "$MATCHER" in
  exhaustive|sequential)
    ;;
  *)
    fail "--matcher 只支持 exhaustive / sequential"
    ;;
esac

resolve_default_colmap_bin

SOURCE_PATH=$(normalize_path "$SOURCE_PATH")

if [[ -n "$START_CHECKPOINT" ]]; then
  START_CHECKPOINT=$(normalize_path "$START_CHECKPOINT")
fi

if [[ -n "$MASK_DIR" ]]; then
  MASK_DIR=$(normalize_path "$MASK_DIR")
fi

if [[ -z "$FASTGS_ROOT" ]]; then
  if is_prepared_dataset_root "$SOURCE_PATH"; then
    FASTGS_ROOT="$SOURCE_PATH"
    PREPARED_SOURCE_MODE=1
  else
    FASTGS_ROOT=$(default_fastgs_root "$SOURCE_PATH")
  fi
else
  FASTGS_ROOT=$(normalize_path "$FASTGS_ROOT")
fi

if [[ -z "$MODEL_PATH" ]]; then
  MODEL_PATH=$(default_model_path "$SOURCE_PATH")
else
  MODEL_PATH=$(normalize_path "$MODEL_PATH")
fi

case "$VIDEO_SETS" in
  train|test|both)
    ;;
  *)
    fail "--video-sets 只支持 train / test / both"
    ;;
esac

if [[ -n "$VIDEO_ITERATIONS" ]]; then
  video_iteration_limit="$ITERATIONS"
  if [[ "$PHASE" == "render" || "$PHASE" == "evaluate" ]]; then
    video_iteration_limit="999999999"
  fi
  normalize_iteration_csv "$VIDEO_ITERATIONS" "$video_iteration_limit" >/dev/null
fi

if [[ "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  require_dir "$SOURCE_PATH"
  if (( ! PREPARED_SOURCE_MODE )); then
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
fi

if [[ "$PHASE" == "train" || "$PHASE" == "all" ]]; then
  if [[ -n "$START_CHECKPOINT" ]]; then
    require_file "$START_CHECKPOINT"
  fi
  if [[ -n "$MASK_DIR" ]]; then
    require_dir "$MASK_DIR"
  fi
fi

if [[ -n "$VIDEO_ITERATIONS" && ( "$PHASE" == "render" || "$PHASE" == "evaluate" || "$PHASE" == "all" ) ]]; then
  if [[ "$FFMPEG_BIN" == */* ]]; then
    require_file "$FFMPEG_BIN"
  else
    require_cmd "$FFMPEG_BIN"
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
    if [[ -n "$VIDEO_ITERATIONS" ]]; then
      render_video_iterations
    else
      render_model
    fi
    ;;
  metrics)
    metrics_model
    ;;
  evaluate)
    if [[ -n "$VIDEO_ITERATIONS" ]]; then
      render_video_iterations
    else
      render_model
    fi
    metrics_model
    ;;
  all)
    if (( EVAL == 0 )); then
      fail "--phase all 需要保留 --eval, 否则 metrics.py 没有 test 集可评估"
    fi
    prepare_dataset
    train_model
    if [[ -n "$VIDEO_ITERATIONS" ]]; then
      render_video_iterations
    else
      render_model
    fi
    metrics_model
    ;;
esac
