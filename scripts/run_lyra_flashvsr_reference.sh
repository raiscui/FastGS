#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Lyra generated root -> FlashVSR-Pro external SR reference
#
# 这份脚本不直接做 FastGS 训练.
# 它只是把已经收编到 FastGS 的 `scripts/run_flashvsr_reference.py`
# 包装成一个更短、更稳的入口.
# ============================================================

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

LYRA_ROOT="$REPO_ROOT/../lyra"
FLASHVSR_REPO="$REPO_ROOT/../FlashVSR-Pro"
SCRIPT_PYTHON=""
LOCAL_PYTHON=""

INPUT_ROOT=""
OUTPUT_ROOT=""
SOURCE_VIDEO=""

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
OVERWRITE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
用法:
  bash scripts/run_lyra_flashvsr_reference.sh [选项]

默认行为:
  - 调用当前仓库内的 `scripts/run_flashvsr_reference.py`
  - 默认走当前机器可用的 `local` runner
  - 默认使用 `FlashVSR-Pro full + 2x + bf16 + quality 10`
  - 如果存在 legacy `../lyra`, 默认输出仍沿用 `../lyra/outputs/flashvsr_reference`
  - 如果 legacy `../lyra` 不存在, 默认输出回落到 `data/flashvsr_reference`

输入根目录默认探测顺序:
  1. `../lyra/assets/demo/static/diffusion_output_generated`
  2. `../lyra/assets/demo/static/diffusion_output_generated_my`

常用示例:
  1) 直接按默认路径生成整批 SR reference:
     bash scripts/run_lyra_flashvsr_reference.sh

  2) 只跑单路单场景:
     bash scripts/run_lyra_flashvsr_reference.sh \
       --view-ids 5 \
       --scene-stem 00172

  3) 指定自己的 Lyra 生成目录:
     bash scripts/run_lyra_flashvsr_reference.sh \
       --input-root /workspace/lyra/assets/demo/static/diffusion_output_generated_my

  4) 直接传单个视频路径, 自动推导 root / scene_stem / view_ids:
     bash scripts/run_lyra_flashvsr_reference.sh \
       --source-video "/workspace/lyra/assets/demo/static/diffusion_output_generated_xhc/0/rgb/xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.mp4"

  5) 只做 dry-run, 看看实际会拼出什么命令:
     bash scripts/run_lyra_flashvsr_reference.sh \
       --view-ids 5 \
       --scene-stem 00172 \
       --dry-run \
       --output-root /tmp/flashvsr_reference_dryrun

  6) 改成 tiny 模式:
     bash scripts/run_lyra_flashvsr_reference.sh \
       --mode tiny \
       --scale 2.0

  7) 显式使用 docker runner:
     bash scripts/run_lyra_flashvsr_reference.sh \
       --runner docker \
       --docker-image flashvsr-pro:latest

选项:
  --lyra-root <path>             legacy Lyra 根目录, 仅用于推导默认输入/输出
  --flashvsr-repo <path>         FlashVSR-Pro 仓库根目录, 默认 ../FlashVSR-Pro
  --script-python <path>         执行本仓库 `run_flashvsr_reference.py` 的 Python
  --lyra-python <path>           兼容旧参数, 等价于 --script-python
  --local-python <path>          local runner 下执行 `infer.py` 的 Python, 默认与 --script-python 相同
  --input-root <path>            待超分的 Lyra generated root
  --source-video <path>          直接指定某个 rgb/*.mp4, 自动推导 root / scene_stem / view_ids
  --output-root <path>           SR reference 输出根目录, 默认 <lyra_root>/outputs/flashvsr_reference
  --runner <local|docker>        FlashVSR 运行方式, 默认 local
  --docker-image <name>          docker 镜像名, 默认 flashvsr-pro:latest
  --docker-gpus <value>          docker `--gpus` 参数, 默认 all
  --mode <full|tiny|tiny-long>   FlashVSR 模式, 默认 full
  --scale <x>                    超分倍率, 默认 2.0
  --dtype <fp32|fp16|bf16>       精度, 默认 bf16
  --quality <0-10>               输出质量, 默认 10
  --view-ids <csv>               只处理指定视角, 例如 5,0,1,2,3,4
  --scene-stem <name>            只处理指定场景 stem, 例如 00172
  --keep-audio                   透传给 FlashVSR-Pro 的 --keep-audio
  --tile-vae                     允许 fallback tiling 时再启用 VAE tiling
  --disable-fallback-tiling      禁用 OOM 后自动回退 tiled 推理
  --fallback-tile-size <n>       fallback tile size, 默认 512
  --fallback-overlap <n>         fallback overlap, 默认 128
  --debug-frame-indices <csv>    导出指定 debug 帧, 例如 0,8,16,24
  --debug-every <n>              未指定 debug 帧时, 每隔 N 帧导出一次, 默认 8
  --dump-all-debug-frames        导出所有 debug 帧
  --overwrite                    覆盖已有 SR 输出
  --dry-run                      只生成 manifest / summary, 不真的执行超分
  -h, --help                     显示帮助

说明:
  - `--source-video` 与 `--input-root` 二选一.
  - 如果传了 `--source-video`:
    - 脚本会自动推导 `input-root`
    - 脚本会自动推导 `scene-stem`
    - 如果没显式传 `--view-ids`, 会自动收集该 stem 在所有视角下都存在的 view ids
  - relative 的 `--input-root` / `--output-root` 会优先相对 `--lyra-root` 解析.
  - relative 的 `--flashvsr-repo` / `--lyra-root` / `--script-python` / `--local-python`
    会相对 FastGS 仓库根目录解析.
  - 如果没显式传 `--script-python`, 会优先使用 FastGS 自己的 pixi Python.
EOF
}

log() {
  printf '[lyra-flashvsr-reference] %s\n' "$*"
}

fail() {
  printf '[lyra-flashvsr-reference] ERROR: %s\n' "$*" >&2
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

normalize_binary_if_path() {
  local base="$1"
  local raw_value="$2"

  if [[ "$raw_value" == */* || "$raw_value" == .* || "$raw_value" == ~* ]]; then
    normalize_path "$base" "$raw_value"
    return 0
  fi

  command -v "$raw_value" >/dev/null 2>&1 || fail "缺少命令: $raw_value"
  command -v "$raw_value"
}

default_input_root() {
  local candidate_default="$LYRA_ROOT/assets/demo/static/diffusion_output_generated"
  local candidate_my="$LYRA_ROOT/assets/demo/static/diffusion_output_generated_my"

  if [[ -d "$candidate_default" ]]; then
    printf '%s\n' "$candidate_default"
    return 0
  fi

  if [[ -d "$candidate_my" ]]; then
    printf '%s\n' "$candidate_my"
    return 0
  fi

  fail "未传 --input-root, 且没有找到 legacy Lyra 默认目录. 请显式传 --input-root 或 --source-video."
}

default_output_root() {
  if [[ -d "$LYRA_ROOT" ]]; then
    printf '%s\n' "$LYRA_ROOT/outputs/flashvsr_reference"
    return 0
  fi

  printf '%s\n' "$REPO_ROOT/data/flashvsr_reference"
}

default_script_python() {
  local pixi_python="$REPO_ROOT/.pixi/envs/default/bin/python"

  if [[ -x "$pixi_python" ]]; then
    printf '%s\n' "$pixi_python"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "找不到可用的 python3. 请先安装 Python, 或显式传 --script-python."
  command -v python3
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

find_torch_lib_dir() {
  local python_bin="$1"
  local env_root=""
  local python_tag=""
  local candidate=""

  env_root=$(cd -- "$(dirname -- "$python_bin")/.." && pwd)
  python_tag=$("$python_bin" - <<'PY'
import sys
print(f"python{sys.version_info.major}.{sys.version_info.minor}")
PY
)

  candidate="$env_root/lib/$python_tag/site-packages/torch/lib"
  if [[ -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in "$env_root"/lib/python*/site-packages/torch/lib; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

build_pythonpath() {
  local combined="$FLASHVSR_REPO:$REPO_ROOT"

  if [[ -n "${PYTHONPATH:-}" ]]; then
    combined="$combined:$PYTHONPATH"
  fi

  printf '%s\n' "$combined"
}

build_ld_library_path() {
  local python_bin="$1"
  local torch_lib="$2"
  local env_root=""
  local combined=""

  env_root=$(cd -- "$(dirname -- "$python_bin")/.." && pwd)
  combined="$torch_lib:$env_root/lib"

  if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    combined="$combined:$LD_LIBRARY_PATH"
  fi

  printf '%s\n' "$combined"
}

validate_local_flashvsr_python() {
  local python_bin="$1"
  local env_pythonpath="$2"
  local env_ld_library_path="$3"

  env PYTHONPATH="$env_pythonpath" LD_LIBRARY_PATH="$env_ld_library_path" "$python_bin" - <<'PY'
import importlib.util

required_modules = [
    "torch",
    "einops",
    "imageio",
    "PIL",
    "diffsynth",
]
missing_modules = [name for name in required_modules if importlib.util.find_spec(name) is None]
if missing_modules:
    raise SystemExit(
        "missing python modules for FlashVSR local runner: " + ", ".join(missing_modules)
    )
PY
}

run_cmd() {
  log "执行: $*"
  "$@"
}

while (( $# > 0 )); do
  case "$1" in
    --lyra-root)
      LYRA_ROOT="$2"
      shift 2
      ;;
    --flashvsr-repo)
      FLASHVSR_REPO="$2"
      shift 2
      ;;
    --script-python|--lyra-python)
      SCRIPT_PYTHON="$2"
      shift 2
      ;;
    --local-python)
      LOCAL_PYTHON="$2"
      shift 2
      ;;
    --input-root)
      INPUT_ROOT="$2"
      shift 2
      ;;
    --source-video)
      SOURCE_VIDEO="$2"
      shift 2
      ;;
    --output-root)
      OUTPUT_ROOT="$2"
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
    --view-ids)
      VIEW_IDS="$2"
      shift 2
      ;;
    --scene-stem)
      SCENE_STEM="$2"
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

[[ "$QUALITY" =~ ^([0-9]|10)$ ]] || fail "--quality 必须是 0 到 10 的整数"
[[ "$FALLBACK_TILE_SIZE" =~ ^[1-9][0-9]*$ ]] || fail "--fallback-tile-size 必须是 >= 1 的整数"
[[ "$FALLBACK_OVERLAP" =~ ^[0-9]+$ ]] || fail "--fallback-overlap 必须是 >= 0 的整数"
[[ "$DEBUG_EVERY" =~ ^[1-9][0-9]*$ ]] || fail "--debug-every 必须是 >= 1 的整数"

python3 - <<'PY' "$SCALE"
import sys
value = float(sys.argv[1])
if value <= 0:
    raise SystemExit(1)
PY

LYRA_ROOT=$(normalize_path "$REPO_ROOT" "$LYRA_ROOT")
FLASHVSR_REPO=$(normalize_path "$REPO_ROOT" "$FLASHVSR_REPO")

if [[ -n "$SOURCE_VIDEO" && -n "$INPUT_ROOT" ]]; then
  fail "--source-video 与 --input-root 不能同时使用"
fi

if [[ -z "$SCRIPT_PYTHON" ]]; then
  SCRIPT_PYTHON=$(default_script_python)
fi
if [[ -z "$LOCAL_PYTHON" ]]; then
  LOCAL_PYTHON="$SCRIPT_PYTHON"
fi

SCRIPT_PYTHON=$(normalize_binary_if_path "$REPO_ROOT" "$SCRIPT_PYTHON")
LOCAL_PYTHON=$(normalize_binary_if_path "$REPO_ROOT" "$LOCAL_PYTHON")

if [[ -n "$SOURCE_VIDEO" ]]; then
  SOURCE_VIDEO=$(normalize_path "$REPO_ROOT" "$SOURCE_VIDEO")
  require_file "$SOURCE_VIDEO"

  # 直接从单个视频路径反推 Lyra root / view_id / scene_stem.
  # 这样带空格、中文和逗号的长文件名也不需要手敲两遍 scene stem.
  mapfile -t source_video_context < <(derive_source_video_context "$SOURCE_VIDEO")
  derived_input_root="${source_video_context[0]}"
  derived_view_id="${source_video_context[1]}"
  derived_scene_stem="${source_video_context[2]}"

  INPUT_ROOT="$derived_input_root"

  if [[ -n "$SCENE_STEM" && "$SCENE_STEM" != "$derived_scene_stem" ]]; then
    fail "--scene-stem 与 --source-video 推导出的 scene stem 不一致: $SCENE_STEM vs $derived_scene_stem"
  fi
  SCENE_STEM="$derived_scene_stem"
elif [[ -z "$INPUT_ROOT" ]]; then
  INPUT_ROOT=$(default_input_root)
else
  if [[ -d "$LYRA_ROOT" ]]; then
    INPUT_ROOT=$(normalize_path "$LYRA_ROOT" "$INPUT_ROOT")
  else
    INPUT_ROOT=$(normalize_path "$REPO_ROOT" "$INPUT_ROOT")
  fi
fi

if [[ -d "$LYRA_ROOT" ]]; then
  INPUT_ROOT=$(normalize_path "$LYRA_ROOT" "$INPUT_ROOT")
else
  INPUT_ROOT=$(normalize_path "$REPO_ROOT" "$INPUT_ROOT")
fi

if [[ -n "$SCENE_STEM" ]]; then
  # 如果 scene stem 已知, 这里顺手把 view ids 归一化成“真实存在完整素材的那些视角”.
  # 这样后续日志里能看到最终实际使用的是哪一组视角.
  VIEW_IDS=$(discover_scene_view_ids "$INPUT_ROOT" "$SCENE_STEM" "$VIEW_IDS")
fi

if [[ -z "$OUTPUT_ROOT" ]]; then
  OUTPUT_ROOT=$(default_output_root)
else
  if [[ -d "$LYRA_ROOT" ]]; then
    OUTPUT_ROOT=$(normalize_path "$LYRA_ROOT" "$OUTPUT_ROOT")
  else
    OUTPUT_ROOT=$(normalize_path "$REPO_ROOT" "$OUTPUT_ROOT")
  fi
fi

REFERENCE_SCRIPT="$REPO_ROOT/scripts/run_flashvsr_reference.py"

require_cmd python3
require_dir "$FLASHVSR_REPO"
require_file "$REFERENCE_SCRIPT"
require_dir "$INPUT_ROOT"
require_file "$SCRIPT_PYTHON"

if [[ "$RUNNER" == "local" && "$LOCAL_PYTHON" == */* ]]; then
  require_file "$LOCAL_PYTHON"
fi

if [[ "$RUNNER" == "docker" ]]; then
  require_cmd docker
fi

cmd=(
  "$SCRIPT_PYTHON"
  "$REFERENCE_SCRIPT"
  --input-root "$INPUT_ROOT"
  --output-root "$OUTPUT_ROOT"
  --flashvsr-repo "$FLASHVSR_REPO"
  --runner "$RUNNER"
  --mode "$MODE"
  --scale "$SCALE"
  --dtype "$DTYPE"
  --quality "$QUALITY"
  --fallback-tile-size "$FALLBACK_TILE_SIZE"
  --fallback-overlap "$FALLBACK_OVERLAP"
  --debug-every "$DEBUG_EVERY"
)

if [[ "$RUNNER" == "local" ]]; then
  cmd+=(--local-python "$LOCAL_PYTHON")
else
  cmd+=(--docker-image "$DOCKER_IMAGE" --docker-gpus "$DOCKER_GPUS")
fi

if [[ -n "$VIEW_IDS" ]]; then
  cmd+=(--view-ids "$VIEW_IDS")
fi
if [[ -n "$SCENE_STEM" ]]; then
  cmd+=(--scene-stem "$SCENE_STEM")
fi
if [[ -n "$DEBUG_FRAME_INDICES" ]]; then
  cmd+=(--debug-frame-indices "$DEBUG_FRAME_INDICES")
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

env_pythonpath=$(build_pythonpath)
env_cmd=(env "PYTHONPATH=$env_pythonpath")

if [[ "$RUNNER" == "local" ]]; then
  torch_lib_dir=$(find_torch_lib_dir "$LOCAL_PYTHON") || fail "未能从 $LOCAL_PYTHON 推断 torch/lib 路径"
  env_ld_library_path=$(build_ld_library_path "$LOCAL_PYTHON" "$torch_lib_dir")
  env_cmd+=("LD_LIBRARY_PATH=$env_ld_library_path")

  # 这里先做一次依赖预检.
  # 避免真正跑到 `infer.py` 时, 才因为缺少 `einops` / `diffsynth` 等依赖报模糊错误.
  if (( DRY_RUN == 0 )); then
    validate_local_flashvsr_python "$LOCAL_PYTHON" "$env_pythonpath" "$env_ld_library_path" || fail "当前 local Python 缺少 FlashVSR 依赖. 请传 --local-python 指向已安装 FlashVSR requirements 的解释器, 或改用 --runner docker."
  fi
fi

log "FlashVSR repo: $FLASHVSR_REPO"
if [[ -d "$LYRA_ROOT" ]]; then
  log "Legacy Lyra root: $LYRA_ROOT"
fi
log "Reference script Python: $SCRIPT_PYTHON"
if [[ "$RUNNER" == "local" ]]; then
  log "FlashVSR local Python: $LOCAL_PYTHON"
fi
if [[ -n "$SOURCE_VIDEO" ]]; then
  log "Source video: $SOURCE_VIDEO"
  log "Source video view id: $derived_view_id"
fi
log "Input root: $INPUT_ROOT"
log "Output root: $OUTPUT_ROOT"
log "Runner: $RUNNER"
log "Mode: $MODE"
log "Scale: $SCALE"
log "Dtype: $DTYPE"
log "Quality: $QUALITY"
if [[ -n "$VIEW_IDS" ]]; then
  log "View ids: $VIEW_IDS"
fi
if [[ -n "$SCENE_STEM" ]]; then
  log "Scene stem: $SCENE_STEM"
fi
if (( DRY_RUN )); then
  log "Dry run: 1"
fi

run_cmd "${env_cmd[@]}" "${cmd[@]}"
