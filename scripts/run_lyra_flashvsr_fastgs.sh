#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Lyra generated root -> FlashVSR-Pro -> FastGS
#
# 这份脚本把三段流程串起来:
# 1. 先做 FlashVSR 视频超分
# 2. 再把 SR 结果组织成 Lyra 风格 root
# 3. 最后送入 direct 或 COLMAP 路线
# ============================================================

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

LYRA_ROOT="$REPO_ROOT/../lyra"
FLASHVSR_REPO="$REPO_ROOT/../FlashVSR-Pro"
SOURCE_PATH=""
SOURCE_VIDEO=""
PHASE="prepare"
PIPELINE="direct"

LYRA_PYTHON=""
LOCAL_PYTHON=""
PIXI_BIN="pixi"
PYTHON_BIN="python3"
COLMAP_BIN="/workspace/colmap-cuda-install-3.12.6/bin/colmap"
FFMPEG_BIN="ffmpeg"

FLASHVSR_OUTPUT_ROOT=""
PREPARED_ROOT=""
MODEL_PATH=""
FASTGS_ROOT=""

RUNNER="local"
DOCKER_IMAGE="flashvsr-pro:latest"
DOCKER_GPUS="all"
MODE="full"
SCALE="2.0"
DTYPE="bf16"
QUALITY="10"

VIEW_IDS=""
SCENE_STEM=""

KEEP_AUDIO=0
TILE_VAE=0
DISABLE_FALLBACK_TILING=0
FALLBACK_TILE_SIZE="512"
FALLBACK_OVERLAP="128"
DEBUG_FRAME_INDICES=""
DEBUG_EVERY="8"
DUMP_ALL_DEBUG_FRAMES=0
DRY_RUN=0

RESOLUTION=""
ITERATIONS=""
ITERATION=""
CAMERA_MODEL=""
VIDEO_FPS=""

EVAL_MODE=""
OVERWRITE=0
USE_GPU=1

DENSIFICATION_INTERVAL=""
LOSS_THRESH=""
GRAD_THRESH=""
GRAD_ABS_THRESH=""
HIGHFEATURE_LR=""
LOWFEATURE_LR=""
DENSE=""
MULT=""
OPTIMIZER_TYPE=""

usage() {
  cat <<'EOF'
用法:
  bash scripts/run_lyra_flashvsr_fastgs.sh [选项]

默认行为:
  - 先做 `FlashVSR-Pro` 超分
  - 再生成一个可被 FastGS 消费的 Lyra 风格 SR root
  - 默认走 `direct` 路线
  - 默认 `--phase prepare`

常用示例:
  1) 直接把历史 `00172` 数据做成 SR root:
     bash scripts/run_lyra_flashvsr_fastgs.sh

  2) 从单个长中文文件名反推出整套多视角场景:
     bash scripts/run_lyra_flashvsr_fastgs.sh \
       --source-video "/workspace/lyra/assets/demo/static/diffusion_output_generated_xhc/0/rgb/xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.mp4"

  3) 一路跑完 `FlashVSR -> direct FastGS 训练与评估`:
     bash scripts/run_lyra_flashvsr_fastgs.sh \
       --phase all \
       --pipeline direct \
       --overwrite

  4) 走 `FlashVSR -> COLMAP -> FastGS`:
     bash scripts/run_lyra_flashvsr_fastgs.sh \
       --phase all \
       --pipeline colmap \
       --camera-model SIMPLE_PINHOLE \
       --video-fps 4 \
       --overwrite

  5) 只验证长文件名路径解析和命令拼装:
     bash scripts/run_lyra_flashvsr_fastgs.sh \
       --source-video "/workspace/lyra/assets/demo/static/diffusion_output_generated_xhc/0/rgb/xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.mp4" \
       --phase superres \
       --view-ids 0 \
       --dry-run

选项:
  --phase <superres|prepare|train|render|metrics|evaluate|all>
                                执行阶段, 默认 prepare
  --pipeline <direct|colmap>    FastGS 后续路线, 默认 direct
  --source-path <path>          Lyra generated root
  --source-video <path>         直接指定某个 rgb/*.mp4, 自动推导 root / scene_stem / view_ids
  --lyra-root <path>            Lyra 仓库根目录, 默认 ../lyra
  --flashvsr-repo <path>        FlashVSR-Pro 仓库根目录, 默认 ../FlashVSR-Pro
  --lyra-python <path>          执行 Lyra wrapper 的 Python
  --local-python <path>         local runner 下执行 `infer.py` 的 Python
  --flashvsr-output-root <path> FlashVSR 输出根目录
  --prepared-root <path>        供 FastGS 消费的 Lyra 风格 SR root
  --model-path <path>           FastGS 模型输出目录
  --fastgs-root <path>          COLMAP 路线的数据目录
  --view-ids <csv>              指定视角, 例如 5,0,1,2,3,4
  --scene-stem <name>           指定场景 stem
  --runner <local|docker>       FlashVSR 运行方式, 默认 local
  --docker-image <name>         docker 镜像名
  --docker-gpus <value>         docker `--gpus` 参数
  --mode <full|tiny|tiny-long>  FlashVSR 模式, 默认 full
  --scale <x>                   超分倍率, 默认 2.0
  --dtype <fp32|fp16|bf16>      FlashVSR 精度, 默认 bf16
  --quality <0-10>              FlashVSR 输出质量, 默认 10
  --keep-audio                  透传给 FlashVSR-Pro
  --tile-vae                    允许 fallback tiling 时启用 VAE tiling
  --disable-fallback-tiling     禁用 OOM 自动 tiled fallback
  --fallback-tile-size <n>      FlashVSR fallback tile size
  --fallback-overlap <n>        FlashVSR fallback overlap
  --debug-frame-indices <csv>   FlashVSR 导出指定 debug 帧
  --debug-every <n>             FlashVSR 每隔 N 帧导出 debug
  --dump-all-debug-frames       FlashVSR 导出全部 debug 帧
  -r, --resolution <v>          FastGS 训练分辨率
  --iterations <n>              FastGS 训练迭代数
  --iteration <n>               render.py 读取的迭代号
  --camera-model <name>         COLMAP 相机模型
  --video-fps <x>               COLMAP 抽帧帧率
  --eval                        显式开启 eval
  --no-eval                     显式关闭 eval
  --no-gpu                      让 COLMAP 走 CPU
  --densification_interval <n>  FastGS 增点间隔
  --loss_thresh <x>             FastGS loss 阈值
  --grad_thresh <x>             FastGS clone 梯度阈值
  --grad_abs_thresh <x>         FastGS split 梯度阈值
  --highfeature_lr <x>          FastGS 高阶 SH 学习率
  --lowfeature_lr <x>           FastGS 低阶 SH 学习率
  --dense <x>                   FastGS clone / split 尺寸分界
  --mult <x>                    FastGS compact box 系数
  --optimizer_type <name>       FastGS 优化器类型
  --overwrite                   按阶段覆盖已有产物
  --dry-run                     只对 FlashVSR 阶段做 dry-run
  -h, --help                    显示帮助

说明:
  - `--source-video` 与 `--source-path` 二选一.
  - `--phase prepare` 的含义是:
    - direct: 做完超分并生成可训练 SR root
    - colmap: 做完超分、生成 SR root, 再继续跑 COLMAP prepare
  - `--phase all` 才会真的启动训练.
  - 长中文文件名只要整体用引号包起来即可.
EOF
}

log() {
  printf '[lyra-flashvsr-fastgs] %s\n' "$*"
}

fail() {
  printf '[lyra-flashvsr-fastgs] ERROR: %s\n' "$*" >&2
  exit 1
}

normalize_path() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys

base = Path(sys.argv[1])
raw_path = Path(sys.argv[2]).expanduser()

if not raw_path.is_absolute():
    raw_path = base / raw_path

print(raw_path.resolve(strict=False))
PY
}

default_source_path() {
  local candidate_default="$LYRA_ROOT/assets/demo/static/diffusion_output_generated"
  local candidate_my="$LYRA_ROOT/assets/demo/static/diffusion_output_generated_my"

  if [[ -d "$candidate_default" ]]; then
    printf '%s\n' "$candidate_default"
    return 0
  fi

  printf '%s\n' "$candidate_my"
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
    "$REPO_ROOT"/data/*)
      rm -rf -- "$target"
      ;;
    *)
      fail "拒绝删除非受控路径: $target"
      ;;
  esac
}

derive_source_video_context() {
  local video_path="$1"

  python3 - "$video_path" <<'PY'
from pathlib import Path
import sys

video_path = Path(sys.argv[1]).expanduser().resolve(strict=False)
supported_suffixes = {".mp4", ".mov", ".avi", ".mkv", ".webm"}

if video_path.suffix.lower() not in supported_suffixes:
    raise SystemExit(f"unsupported source video suffix: {video_path}")

rgb_dir = video_path.parent
view_dir = rgb_dir.parent
root_dir = view_dir.parent

if rgb_dir.name != "rgb":
    raise SystemExit(
        "source video must be under `<lyra_root>/<view_id>/rgb/<scene>.mp4`, "
        f"got: {video_path}"
    )

if not (view_dir / "pose").is_dir() or not (view_dir / "intrinsics").is_dir():
    raise SystemExit(
        "source video parent view directory must contain `pose/` and `intrinsics/`, "
        f"got: {view_dir}"
    )

print(root_dir)
print(view_dir.name)
print(video_path.stem)
PY
}

resolve_scene_stem() {
  local input_root="$1"
  local raw_scene_stem="$2"
  local raw_view_ids="$3"

  python3 - "$input_root" "$raw_scene_stem" "$raw_view_ids" <<'PY'
from pathlib import Path
import sys

input_root = Path(sys.argv[1])
raw_scene_stem = sys.argv[2]
raw_view_ids = [item.strip() for item in sys.argv[3].split(",") if item.strip()]
video_suffixes = {".mp4", ".mov", ".avi", ".mkv", ".webm"}

if raw_scene_stem:
    print(raw_scene_stem)
    raise SystemExit(0)

candidate_view_dirs = sorted(path for path in input_root.iterdir() if path.is_dir())
if raw_view_ids:
    candidate_view_dirs = [path for path in candidate_view_dirs if path.name in raw_view_ids]

common_stems = None
for view_dir in candidate_view_dirs:
    pose_stems = {path.stem for path in (view_dir / "pose").glob("*.npz")}
    intrinsics_stems = {path.stem for path in (view_dir / "intrinsics").glob("*.npz")}
    rgb_dir = view_dir / "rgb"
    rgb_stems = {path.stem for path in rgb_dir.iterdir() if path.is_file() and path.suffix.lower() in video_suffixes} if rgb_dir.is_dir() else set()
    view_common = pose_stems & intrinsics_stems & rgb_stems
    common_stems = view_common if common_stems is None else common_stems & view_common

if not common_stems:
    raise SystemExit(f"could not infer a common scene stem under {input_root}")

if len(common_stems) != 1:
    stem_summary = ", ".join(sorted(common_stems))
    raise SystemExit(
        "multiple common scene stems were found. Please pass --scene-stem explicitly: "
        f"{stem_summary}"
    )

print(next(iter(common_stems)))
PY
}

discover_scene_view_ids() {
  local input_root="$1"
  local scene_stem="$2"
  local raw_view_ids="$3"

  python3 - "$input_root" "$scene_stem" "$raw_view_ids" <<'PY'
from pathlib import Path
import sys

input_root = Path(sys.argv[1])
scene_stem = sys.argv[2]
raw_view_ids = sys.argv[3]

requested_view_ids = [item.strip() for item in raw_view_ids.split(",") if item.strip()]
candidate_view_dirs = sorted(path for path in input_root.iterdir() if path.is_dir())
available_view_ids = []

for view_dir in candidate_view_dirs:
    pose_path = view_dir / "pose" / f"{scene_stem}.npz"
    intrinsics_path = view_dir / "intrinsics" / f"{scene_stem}.npz"
    rgb_candidates = []
    rgb_dir = view_dir / "rgb"
    if rgb_dir.is_dir():
        rgb_candidates = [
            path for path in rgb_dir.iterdir()
            if path.is_file() and path.stem == scene_stem and path.suffix.lower() in {".mp4", ".mov", ".avi", ".mkv", ".webm"}
        ]

    if pose_path.is_file() and intrinsics_path.is_file() and rgb_candidates:
        available_view_ids.append(view_dir.name)

if requested_view_ids:
    missing_view_ids = [view_id for view_id in requested_view_ids if view_id not in available_view_ids]
    if missing_view_ids:
        missing_summary = ", ".join(missing_view_ids)
        raise SystemExit(
            f"requested view ids do not contain a complete pose/intrinsics/rgb set for scene `{scene_stem}`: {missing_summary}"
        )
    print(",".join(requested_view_ids))
    raise SystemExit(0)

if not available_view_ids:
    raise SystemExit(
        f"no complete pose/intrinsics/rgb view set was found for scene `{scene_stem}` under {input_root}"
    )

print(",".join(available_view_ids))
PY
}

build_run_tag() {
  local mode="$1"
  local scale="$2"

  python3 - "$mode" "$scale" <<'PY'
import sys

mode = sys.argv[1]
scale = float(sys.argv[2])
if scale.is_integer():
    scale_tag = f"{int(scale)}x"
else:
    scale_tag = f"{str(scale).replace('.', 'p')}x"
print(f"{mode}_scale{scale_tag}")
PY
}

sanitize_tag() {
  local raw_value="$1"

  python3 - "$raw_value" <<'PY'
import hashlib
import re
import sys
import unicodedata

raw_value = sys.argv[1]
ascii_value = unicodedata.normalize("NFKD", raw_value).encode("ascii", "ignore").decode("ascii")
safe_value = re.sub(r"[^A-Za-z0-9_-]+", "_", ascii_value).strip("_")

if not safe_value:
    safe_value = "scene"

if safe_value != raw_value or len(safe_value) > 48:
    safe_value = safe_value[:48].rstrip("_")
    hash_tag = hashlib.sha1(raw_value.encode("utf-8")).hexdigest()[:8]
    print(f"{safe_value}_{hash_tag}")
else:
    print(safe_value)
PY
}

default_flashvsr_output_root() {
  local source_path="$1"
  local source_name=""
  local safe_source_name=""

  source_name=$(basename -- "$source_path")
  if [[ "$source_name" == "diffusion_output_generated" ]]; then
    printf '%s\n' "$LYRA_ROOT/outputs/flashvsr_reference"
    return 0
  fi

  safe_source_name=$(sanitize_tag "$source_name")
  printf '%s\n' "$LYRA_ROOT/outputs/flashvsr_reference_${safe_source_name}"
}

default_prepared_root() {
  local source_path="$1"
  local scene_stem="$2"
  local run_tag="$3"
  local source_name=""
  local source_tag=""
  local scene_tag=""

  source_name=$(basename -- "$source_path")
  source_tag=$(sanitize_tag "$source_name")
  scene_tag=$(sanitize_tag "$scene_stem")
  printf '%s\n' "$REPO_ROOT/data/${source_tag}_${scene_tag}_${run_tag}_lyra_sr_root"
}

prepare_sr_root() {
  local run_tag="$1"
  local scene_stem="$2"
  local source_path="$3"
  local prepared_root="$4"
  local flashvsr_output_root="$5"
  local view_ids_csv="$6"

  if (( OVERWRITE )); then
    safe_remove "$prepared_root"
  fi

  mkdir -p -- "$prepared_root"

  python3 - "$source_path" "$prepared_root" "$flashvsr_output_root" "$run_tag" "$scene_stem" "$view_ids_csv" <<'PY'
from pathlib import Path
import os
import sys

source_path = Path(sys.argv[1])
prepared_root = Path(sys.argv[2])
flashvsr_output_root = Path(sys.argv[3])
run_tag = sys.argv[4]
scene_stem = sys.argv[5]
view_ids = [item.strip() for item in sys.argv[6].split(",") if item.strip()]

if not view_ids:
    raise SystemExit("prepare_sr_root received an empty view id list")

for view_id in view_ids:
    source_view_dir = source_path / view_id
    pose_path = source_view_dir / "pose" / f"{scene_stem}.npz"
    intrinsics_path = source_view_dir / "intrinsics" / f"{scene_stem}.npz"
    sr_video_path = flashvsr_output_root / run_tag / view_id / "rgb" / f"{scene_stem}.mp4"

    for required_path in (pose_path, intrinsics_path, sr_video_path):
        if not required_path.exists():
            raise SystemExit(f"required file is missing while preparing SR root: {required_path}")

    target_pose_dir = prepared_root / view_id / "pose"
    target_intrinsics_dir = prepared_root / view_id / "intrinsics"
    target_rgb_dir = prepared_root / view_id / "rgb"

    target_pose_dir.mkdir(parents=True, exist_ok=True)
    target_intrinsics_dir.mkdir(parents=True, exist_ok=True)
    target_rgb_dir.mkdir(parents=True, exist_ok=True)

    target_pose_path = target_pose_dir / f"{scene_stem}.npz"
    target_intrinsics_path = target_intrinsics_dir / f"{scene_stem}.npz"
    target_rgb_path = target_rgb_dir / f"{scene_stem}.mp4"

    for target_path in (target_pose_path, target_intrinsics_path, target_rgb_path):
        if target_path.exists() or target_path.is_symlink():
            target_path.unlink()

    os.symlink(pose_path, target_pose_path)
    os.symlink(intrinsics_path, target_intrinsics_path)
    os.symlink(sr_video_path, target_rgb_path)

print(prepared_root)
PY
}

run_cmd() {
  log "执行: $*"
  "$@"
}

while (( $# > 0 )); do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --pipeline)
      PIPELINE="$2"
      shift 2
      ;;
    --source-path)
      SOURCE_PATH="$2"
      shift 2
      ;;
    --source-video)
      SOURCE_VIDEO="$2"
      shift 2
      ;;
    --lyra-root)
      LYRA_ROOT="$2"
      shift 2
      ;;
    --flashvsr-repo)
      FLASHVSR_REPO="$2"
      shift 2
      ;;
    --lyra-python)
      LYRA_PYTHON="$2"
      shift 2
      ;;
    --local-python)
      LOCAL_PYTHON="$2"
      shift 2
      ;;
    --flashvsr-output-root)
      FLASHVSR_OUTPUT_ROOT="$2"
      shift 2
      ;;
    --prepared-root)
      PREPARED_ROOT="$2"
      shift 2
      ;;
    --model-path)
      MODEL_PATH="$2"
      shift 2
      ;;
    --fastgs-root)
      FASTGS_ROOT="$2"
      shift 2
      ;;
    --view-ids)
      VIEW_IDS="$2"
      shift 2
      ;;
    --scene-stem)
      SCENE_STEM="$2"
      shift 2
      ;;
    --runner)
      RUNNER="$2"
      shift 2
      ;;
    --docker-image)
      DOCKER_IMAGE="$2"
      shift 2
      ;;
    --docker-gpus)
      DOCKER_GPUS="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --scale)
      SCALE="$2"
      shift 2
      ;;
    --dtype)
      DTYPE="$2"
      shift 2
      ;;
    --quality)
      QUALITY="$2"
      shift 2
      ;;
    --keep-audio)
      KEEP_AUDIO=1
      shift
      ;;
    --tile-vae)
      TILE_VAE=1
      shift
      ;;
    --disable-fallback-tiling)
      DISABLE_FALLBACK_TILING=1
      shift
      ;;
    --fallback-tile-size)
      FALLBACK_TILE_SIZE="$2"
      shift 2
      ;;
    --fallback-overlap)
      FALLBACK_OVERLAP="$2"
      shift 2
      ;;
    --debug-frame-indices)
      DEBUG_FRAME_INDICES="$2"
      shift 2
      ;;
    --debug-every)
      DEBUG_EVERY="$2"
      shift 2
      ;;
    --dump-all-debug-frames)
      DUMP_ALL_DEBUG_FRAMES=1
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
    --camera-model)
      CAMERA_MODEL="$2"
      shift 2
      ;;
    --video-fps)
      VIDEO_FPS="$2"
      shift 2
      ;;
    --eval)
      EVAL_MODE="--eval"
      shift
      ;;
    --no-eval)
      EVAL_MODE="--no-eval"
      shift
      ;;
    --no-gpu)
      USE_GPU=0
      shift
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
      shift 2
      ;;
    --optimizer_type)
      OPTIMIZER_TYPE="$2"
      shift 2
      ;;
    --overwrite)
      OVERWRITE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
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
  superres|prepare|train|render|metrics|evaluate|all)
    ;;
  *)
    fail "--phase 只支持 superres / prepare / train / render / metrics / evaluate / all"
    ;;
esac

case "$PIPELINE" in
  direct|colmap)
    ;;
  *)
    fail "--pipeline 只支持 direct / colmap"
    ;;
esac

case "$RUNNER" in
  local|docker)
    ;;
  *)
    fail "--runner 只支持 local / docker"
    ;;
esac

case "$MODE" in
  full|tiny|tiny-long)
    ;;
  *)
    fail "--mode 只支持 full / tiny / tiny-long"
    ;;
esac

case "$DTYPE" in
  fp32|fp16|bf16)
    ;;
  *)
    fail "--dtype 只支持 fp32 / fp16 / bf16"
    ;;
esac

if [[ -n "$SOURCE_VIDEO" && -n "$SOURCE_PATH" ]]; then
  fail "--source-video 与 --source-path 不能同时使用"
fi

if (( DRY_RUN )) && [[ "$PHASE" != "superres" ]]; then
  fail "--dry-run 当前只支持与 --phase superres 搭配使用"
fi

[[ "$QUALITY" =~ ^([0-9]|10)$ ]] || fail "--quality 必须是 0 到 10 的整数"
if [[ -n "$FALLBACK_TILE_SIZE" ]]; then
  [[ "$FALLBACK_TILE_SIZE" =~ ^[1-9][0-9]*$ ]] || fail "--fallback-tile-size 必须是 >= 1 的整数"
fi
if [[ -n "$FALLBACK_OVERLAP" ]]; then
  [[ "$FALLBACK_OVERLAP" =~ ^[0-9]+$ ]] || fail "--fallback-overlap 必须是 >= 0 的整数"
fi
if [[ -n "$DEBUG_EVERY" ]]; then
  [[ "$DEBUG_EVERY" =~ ^[1-9][0-9]*$ ]] || fail "--debug-every 必须是 >= 1 的整数"
fi

python3 - <<'PY' "$SCALE"
import sys
value = float(sys.argv[1])
if value <= 0:
    raise SystemExit(1)
PY

LYRA_ROOT=$(normalize_path "$REPO_ROOT" "$LYRA_ROOT")
FLASHVSR_REPO=$(normalize_path "$REPO_ROOT" "$FLASHVSR_REPO")

if [[ -z "$LYRA_PYTHON" ]]; then
  LYRA_PYTHON="$LYRA_ROOT/.pixi/envs/default/bin/python3"
fi
if [[ -z "$LOCAL_PYTHON" ]]; then
  LOCAL_PYTHON="$LYRA_PYTHON"
fi

LYRA_PYTHON=$(normalize_path "$REPO_ROOT" "$LYRA_PYTHON")
LOCAL_PYTHON=$(normalize_path "$REPO_ROOT" "$LOCAL_PYTHON")

require_cmd python3
require_dir "$LYRA_ROOT"
require_dir "$FLASHVSR_REPO"
require_file "$LYRA_PYTHON"
if [[ "$RUNNER" == "local" ]]; then
  require_file "$LOCAL_PYTHON"
fi

if [[ -n "$SOURCE_VIDEO" ]]; then
  SOURCE_VIDEO=$(normalize_path "$REPO_ROOT" "$SOURCE_VIDEO")
  require_file "$SOURCE_VIDEO"
  mapfile -t source_video_context < <(derive_source_video_context "$SOURCE_VIDEO")
  SOURCE_PATH="${source_video_context[0]}"
  derived_view_id="${source_video_context[1]}"
  derived_scene_stem="${source_video_context[2]}"

  if [[ -n "$SCENE_STEM" && "$SCENE_STEM" != "$derived_scene_stem" ]]; then
    fail "--scene-stem 与 --source-video 推导出的 scene stem 不一致: $SCENE_STEM vs $derived_scene_stem"
  fi
  SCENE_STEM="$derived_scene_stem"
elif [[ -z "$SOURCE_PATH" ]]; then
  SOURCE_PATH=$(default_source_path)
fi

SOURCE_PATH=$(normalize_path "$LYRA_ROOT" "$SOURCE_PATH")
require_dir "$SOURCE_PATH"

if [[ -z "$SCENE_STEM" ]]; then
  SCENE_STEM=$(resolve_scene_stem "$SOURCE_PATH" "$SCENE_STEM" "$VIEW_IDS")
fi

VIEW_IDS=$(discover_scene_view_ids "$SOURCE_PATH" "$SCENE_STEM" "$VIEW_IDS")
RUN_TAG=$(build_run_tag "$MODE" "$SCALE")

if [[ -z "$FLASHVSR_OUTPUT_ROOT" ]]; then
  FLASHVSR_OUTPUT_ROOT=$(default_flashvsr_output_root "$SOURCE_PATH")
else
  FLASHVSR_OUTPUT_ROOT=$(normalize_path "$LYRA_ROOT" "$FLASHVSR_OUTPUT_ROOT")
fi

if [[ -z "$PREPARED_ROOT" ]]; then
  PREPARED_ROOT=$(default_prepared_root "$SOURCE_PATH" "$SCENE_STEM" "$RUN_TAG")
else
  PREPARED_ROOT=$(normalize_path "$REPO_ROOT" "$PREPARED_ROOT")
fi

if [[ -n "$MODEL_PATH" ]]; then
  MODEL_PATH=$(normalize_path "$REPO_ROOT" "$MODEL_PATH")
fi
if [[ -n "$FASTGS_ROOT" ]]; then
  FASTGS_ROOT=$(normalize_path "$REPO_ROOT" "$FASTGS_ROOT")
fi

run_superres() {
  local cmd=(
    bash "$REPO_ROOT/scripts/run_lyra_flashvsr_reference.sh"
    --lyra-root "$LYRA_ROOT"
    --flashvsr-repo "$FLASHVSR_REPO"
    --lyra-python "$LYRA_PYTHON"
    --runner "$RUNNER"
    --mode "$MODE"
    --scale "$SCALE"
    --dtype "$DTYPE"
    --quality "$QUALITY"
    --output-root "$FLASHVSR_OUTPUT_ROOT"
    --view-ids "$VIEW_IDS"
    --scene-stem "$SCENE_STEM"
  )

  if [[ "$RUNNER" == "local" ]]; then
    cmd+=(--local-python "$LOCAL_PYTHON")
  else
    cmd+=(--docker-image "$DOCKER_IMAGE" --docker-gpus "$DOCKER_GPUS")
  fi

  if [[ -n "$SOURCE_VIDEO" ]]; then
    cmd+=(--source-video "$SOURCE_VIDEO")
  else
    cmd+=(--input-root "$SOURCE_PATH")
  fi

  if [[ -n "$DEBUG_FRAME_INDICES" ]]; then
    cmd+=(--debug-frame-indices "$DEBUG_FRAME_INDICES")
  fi
  if [[ -n "$DEBUG_EVERY" ]]; then
    cmd+=(--debug-every "$DEBUG_EVERY")
  fi
  if [[ -n "$FALLBACK_TILE_SIZE" ]]; then
    cmd+=(--fallback-tile-size "$FALLBACK_TILE_SIZE")
  fi
  if [[ -n "$FALLBACK_OVERLAP" ]]; then
    cmd+=(--fallback-overlap "$FALLBACK_OVERLAP")
  fi
  if (( KEEP_AUDIO )); then
    cmd+=(--keep-audio)
  fi
  if (( TILE_VAE )); then
    cmd+=(--tile-vae)
  fi
  if (( DISABLE_FALLBACK_TILING )); then
    cmd+=(--disable-fallback-tiling)
  fi
  if (( DUMP_ALL_DEBUG_FRAMES )); then
    cmd+=(--dump-all-debug-frames)
  fi
  if (( OVERWRITE )); then
    cmd+=(--overwrite)
  fi
  if (( DRY_RUN )); then
    cmd+=(--dry-run)
  fi

  run_cmd "${cmd[@]}"
}

run_pipeline_cmd() {
  local pipeline_phase="$1"
  local cmd=()

  if [[ "$PIPELINE" == "direct" ]]; then
    cmd=(
      bash "$REPO_ROOT/scripts/run_lyra_fastgs.sh"
      --phase "$pipeline_phase"
      --source-path "$PREPARED_ROOT"
    )
  else
    cmd=(
      bash "$REPO_ROOT/scripts/run_lyra_colmap_fastgs.sh"
      --phase "$pipeline_phase"
      --source-path "$PREPARED_ROOT"
    )
  fi

  if [[ -n "$MODEL_PATH" ]]; then
    cmd+=(--model-path "$MODEL_PATH")
  fi
  if [[ -n "$FASTGS_ROOT" && "$PIPELINE" == "colmap" ]]; then
    cmd+=(--fastgs-root "$FASTGS_ROOT")
  fi
  if [[ -n "$RESOLUTION" ]]; then
    cmd+=(-r "$RESOLUTION")
  fi
  if [[ -n "$ITERATIONS" ]]; then
    cmd+=(--iterations "$ITERATIONS")
  fi
  if [[ -n "$ITERATION" ]]; then
    cmd+=(--iteration "$ITERATION")
  fi
  if [[ -n "$EVAL_MODE" ]]; then
    cmd+=("$EVAL_MODE")
  fi
  if (( OVERWRITE )); then
    cmd+=(--overwrite)
  fi
  if [[ -n "$DENSIFICATION_INTERVAL" ]]; then
    cmd+=(--densification_interval "$DENSIFICATION_INTERVAL")
  fi
  if [[ -n "$LOSS_THRESH" ]]; then
    cmd+=(--loss_thresh "$LOSS_THRESH")
  fi
  if [[ -n "$GRAD_THRESH" ]]; then
    cmd+=(--grad_thresh "$GRAD_THRESH")
  fi
  if [[ -n "$GRAD_ABS_THRESH" ]]; then
    cmd+=(--grad_abs_thresh "$GRAD_ABS_THRESH")
  fi
  if [[ -n "$HIGHFEATURE_LR" ]]; then
    cmd+=(--highfeature_lr "$HIGHFEATURE_LR")
  fi
  if [[ -n "$LOWFEATURE_LR" ]]; then
    cmd+=(--lowfeature_lr "$LOWFEATURE_LR")
  fi
  if [[ -n "$DENSE" ]]; then
    cmd+=(--dense "$DENSE")
  fi
  if [[ -n "$MULT" ]]; then
    cmd+=(--mult "$MULT")
  fi
  if [[ -n "$OPTIMIZER_TYPE" ]]; then
    cmd+=(--optimizer_type "$OPTIMIZER_TYPE")
  fi

  if [[ "$PIPELINE" == "colmap" ]]; then
    cmd+=(--python-bin "$PYTHON_BIN" --pixi-bin "$PIXI_BIN" --colmap-bin "$COLMAP_BIN" --ffmpeg-bin "$FFMPEG_BIN")
    if [[ -n "$CAMERA_MODEL" ]]; then
      cmd+=(--camera-model "$CAMERA_MODEL")
    fi
    if [[ -n "$VIDEO_FPS" ]]; then
      cmd+=(--video-fps "$VIDEO_FPS")
    fi
    if (( USE_GPU == 0 )); then
      cmd+=(--no-gpu)
    fi
  else
    cmd+=(--pixi-bin "$PIXI_BIN")
  fi

  run_cmd "${cmd[@]}"
}

log "Pipeline: $PIPELINE"
log "Phase: $PHASE"
log "Source path: $SOURCE_PATH"
if [[ -n "$SOURCE_VIDEO" ]]; then
  log "Source video: $SOURCE_VIDEO"
fi
log "Scene stem: $SCENE_STEM"
log "View ids: $VIEW_IDS"
log "FlashVSR output root: $FLASHVSR_OUTPUT_ROOT"
log "Prepared root: $PREPARED_ROOT"

case "$PHASE" in
  superres)
    run_superres
    ;;
  prepare)
    run_superres
    prepare_sr_root "$RUN_TAG" "$SCENE_STEM" "$SOURCE_PATH" "$PREPARED_ROOT" "$FLASHVSR_OUTPUT_ROOT" "$VIEW_IDS"
    if [[ "$PIPELINE" == "colmap" ]]; then
      run_pipeline_cmd "prepare"
    fi
    ;;
  train)
    if [[ "$PIPELINE" == "direct" ]]; then
      prepare_sr_root "$RUN_TAG" "$SCENE_STEM" "$SOURCE_PATH" "$PREPARED_ROOT" "$FLASHVSR_OUTPUT_ROOT" "$VIEW_IDS"
    fi
    run_pipeline_cmd "train"
    ;;
  render|metrics|evaluate)
    run_pipeline_cmd "$PHASE"
    ;;
  all)
    run_superres
    prepare_sr_root "$RUN_TAG" "$SCENE_STEM" "$SOURCE_PATH" "$PREPARED_ROOT" "$FLASHVSR_OUTPUT_ROOT" "$VIEW_IDS"
    run_pipeline_cmd "all"
    ;;
esac
