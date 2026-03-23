#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# VerseCrafter -> FlashVSR-Pro -> CUDA COLMAP -> FastGS
#
# 这份脚本专门服务 VerseCrafter 的目录结构:
#   view_id/generated_videos/generated_video_0.mp4
#
# 它会做四件事:
# 1. 生成一个仅供 FlashVSR wrapper 使用的 bridge root
# 2. 把待超分视频按 GPU 分片,并发跑 FlashVSR
# 3. 组织 SR 后的 rgb root,再交给 CUDA COLMAP
# 4. 启动 FastGS 训练 / 渲染 / 指标
#
# 重要说明:
# - 这里不会把 VerseCrafter 自带相机参数当成训练输入使用
# - 真正参与重建的是 CUDA COLMAP 算出来的相机参数
# ============================================================

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

VERSE_ROOT=""
PHASE="prepare"

FLASHVSR_REPO="$REPO_ROOT/../FlashVSR-Pro"
REFERENCE_PYTHON=""
LOCAL_PYTHON=""
PIXI_BIN="pixi"
PYTHON_BIN="python3"
COLMAP_BIN="/workspace/colmap-cuda-install-3.12.6/bin/colmap"
FFMPEG_BIN="ffmpeg"
FFPROBE_BIN="ffprobe"

RUNNER="local"
DOCKER_IMAGE="flashvsr-pro:latest"

MODE="full"
SCALE="2.0"
DTYPE="bf16"
QUALITY="10"

VIEW_IDS=""
SCENE_STEM=""

SUPERRES_GPU_IDS="0,1"
COLMAP_GPU_INDEX=""
TRAIN_GPU_ID=""

BRIDGE_ROOT=""
FLASHVSR_OUTPUT_ROOT=""
PREPARED_ROOT=""
FASTGS_ROOT=""
MODEL_PATH=""

CAMERA_MODEL="SIMPLE_PINHOLE"
VIDEO_FPS=""
RESOLUTION="1"
ITERATIONS="30000"
ITERATION="-1"
EVAL_MODE="--eval"
OVERWRITE=0
KEEP_BRIDGE_ROOT=0

KEEP_AUDIO=0
TILE_VAE=0
DISABLE_FALLBACK_TILING=0
FALLBACK_TILE_SIZE="512"
FALLBACK_OVERLAP="128"
DEBUG_FRAME_INDICES=""
DEBUG_EVERY="8"
DUMP_ALL_DEBUG_FRAMES=0
DRY_RUN=0

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
  bash scripts/run_versecrafter_flashvsr_fastgs.sh [选项]

默认行为:
  - 输入是 VerseCrafter 风格目录:
    - `<root>/<view_id>/generated_videos/<scene>.mp4`
  - 脚本内部会先生成一个 bridge root, 只给 FlashVSR wrapper 用
  - 训练阶段强制走 `CUDA COLMAP -> FastGS`
  - 不复用 VerseCrafter 自带相机参数
  - 默认 `--phase prepare`
  - 默认会尽量把超分分摊到 `0,1` 两张卡

常用示例:
  1) 只做双卡超分 dry-run:
     bash scripts/run_versecrafter_flashvsr_fastgs.sh \
       --source-path /workspace/VerseCrafter/demo_data/my4 \
       --phase superres \
       --dry-run

  2) 从 VerseCrafter 一路跑到 FastGS:
     bash scripts/run_versecrafter_flashvsr_fastgs.sh \
       --source-path /workspace/VerseCrafter/demo_data/my4 \
       --phase all \
       --overwrite

  3) 显式指定双卡和 CUDA COLMAP GPU:
     bash scripts/run_versecrafter_flashvsr_fastgs.sh \
       --source-path /workspace/VerseCrafter/demo_data/my4 \
       --phase all \
       --superres-gpu-ids 0,1 \
       --colmap-gpu-index 0,1 \
       --train-gpu-id 0 \
       --overwrite

选项:
  --phase <superres|prepare|train|render|metrics|evaluate|all>
                                执行阶段, 默认 prepare
  --source-path <path>          VerseCrafter 输出根目录
  --scene-stem <name>           目标视频 stem, 例如 generated_video_0
  --view-ids <csv>              指定视角, 例如 0,1,2,3
  --lyra-root <path>            兼容旧参数, 已不再用于脚本内部依赖
  --flashvsr-repo <path>        FlashVSR-Pro 仓库根目录
  --script-python <path>        运行本仓库 FlashVSR reference 子脚本的 Python
  --lyra-python <path>          兼容旧参数, 等价于 --script-python
  --local-python <path>         local runner 的 Python
  --pixi-bin <path>             pixi 可执行文件
  --python-bin <path>           Python 可执行文件
  --colmap-bin <path>           CUDA COLMAP 可执行文件
  --ffmpeg-bin <path>           ffmpeg 可执行文件
  --ffprobe-bin <path>          ffprobe 可执行文件
  --runner <local|docker>       FlashVSR 运行方式, 默认 local
  --docker-image <name>         docker 镜像名
  --mode <full|tiny|tiny-long>  FlashVSR 模式, 默认 full
  --scale <x>                   FlashVSR 超分倍率, 默认 2.0
  --dtype <fp32|fp16|bf16>      FlashVSR 精度, 默认 bf16
  --quality <0-10>              FlashVSR 输出质量, 默认 10
  --superres-gpu-ids <csv>      超分阶段分片使用的 GPU, 默认 0,1
  --colmap-gpu-index <csv>      透传给 CUDA COLMAP 的 GPU index, 默认跟随 superres-gpu-ids
  --train-gpu-id <id>           FastGS 训练/渲染使用的单卡, 默认取 superres-gpu-ids 第一张
  --bridge-root <path>          FlashVSR bridge root 输出目录
  --flashvsr-output-root <path> FlashVSR 汇总输出根目录
  --prepared-root <path>        供 CUDA COLMAP 读取的 SR rgb root
  --fastgs-root <path>          CUDA COLMAP / FastGS 数据目录
  --model-path <path>           FastGS 模型输出目录
  --camera-model <name>         COLMAP 相机模型, 默认 SIMPLE_PINHOLE
  --video-fps <x>               COLMAP 抽帧 fps, 默认自动跟原视频 fps 对齐
  -r, --resolution <v>          FastGS 训练分辨率, 默认 1
  --iterations <n>              FastGS 训练迭代数, 默认 30000
  --iteration <n>               render.py 读取的迭代号
  --eval                        显式开启 eval
  --no-eval                     显式关闭 eval
  --keep-bridge-root            保留中间 bridge root
  --overwrite                   覆盖受控输出目录
  --dry-run                     只对超分阶段做 dry-run
  --keep-audio                  透传给 FlashVSR
  --tile-vae                    透传给 FlashVSR fallback
  --disable-fallback-tiling     透传给 FlashVSR fallback
  --fallback-tile-size <n>      FlashVSR fallback tile size
  --fallback-overlap <n>        FlashVSR fallback overlap
  --debug-frame-indices <csv>   FlashVSR debug 帧索引
  --debug-every <n>             FlashVSR 每隔 N 帧导出 debug
  --dump-all-debug-frames       FlashVSR 导出全部 debug 帧
  --densification_interval <n>  FastGS 增点间隔
  --loss_thresh <x>             FastGS loss 阈值
  --grad_thresh <x>             FastGS clone 梯度阈值
  --grad_abs_thresh <x>         FastGS split 梯度阈值
  --highfeature_lr <x>          FastGS 高阶 SH 学习率
  --lowfeature_lr <x>           FastGS 低阶 SH 学习率
  --dense <x>                   FastGS clone / split 尺寸分界
  --mult <x>                    FastGS compact box 系数
  --optimizer_type <name>       FastGS 优化器类型
  -h, --help                    显示帮助

说明:
  - 这条脚本不会把 VerseCrafter 的 `custom_camera_trajectory.npz` 喂给训练.
  - bridge root 里的 `pose/intrinsics` 是占位文件, 只用于满足 FlashVSR wrapper 的输入约束.
  - 真正用于 3D 重建的是:
    - `CUDA COLMAP feature_extractor / exhaustive_matcher / mapper`
  - 真正用于 FastGS 训练的是:
    - `convert.py` 产出的 `images + sparse/0`
EOF
}

log() {
  printf '[versecrafter-flashvsr-fastgs] %s\n' "$*"
}

fail() {
  printf '[versecrafter-flashvsr-fastgs] ERROR: %s\n' "$*" >&2
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
  else
    command -v "$raw_value" >/dev/null 2>&1 || fail "缺少命令: $raw_value"
    command -v "$raw_value"
  fi
}

default_reference_python() {
  local pixi_python="$REPO_ROOT/.pixi/envs/default/bin/python"

  if [[ -x "$pixi_python" ]]; then
    printf '%s\n' "$pixi_python"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "找不到可用的 python3. 请先安装 Python, 或显式传 --script-python."
  command -v python3
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

resolve_scene_stem() {
  local source_root="$1"
  local raw_scene_stem="$2"
  local raw_view_ids="$3"

  python3 - "$source_root" "$raw_scene_stem" "$raw_view_ids" <<'PY'
from pathlib import Path
import sys

source_root = Path(sys.argv[1])
raw_scene_stem = sys.argv[2]
requested_view_ids = [item.strip() for item in sys.argv[3].split(",") if item.strip()]
video_suffixes = {".mp4", ".mov", ".avi", ".mkv", ".webm"}

if raw_scene_stem:
    print(raw_scene_stem)
    raise SystemExit(0)

candidate_view_dirs = sorted(path for path in source_root.iterdir() if path.is_dir() and path.name.isdigit())
if requested_view_ids:
    candidate_view_dirs = [path for path in candidate_view_dirs if path.name in requested_view_ids]

common_stems = None
for view_dir in candidate_view_dirs:
    generated_dir = view_dir / "generated_videos"
    stems = {
        path.stem for path in generated_dir.iterdir()
        if path.is_file() and path.suffix.lower() in video_suffixes
    } if generated_dir.is_dir() else set()
    common_stems = stems if common_stems is None else common_stems & stems

if not common_stems:
    raise SystemExit(f"could not infer a common VerseCrafter scene stem under {source_root}")

if len(common_stems) != 1:
    stem_summary = ", ".join(sorted(common_stems))
    raise SystemExit(
        "multiple common scene stems were found. Please pass --scene-stem explicitly: "
        f"{stem_summary}"
    )

print(next(iter(common_stems)))
PY
}

discover_view_ids() {
  local source_root="$1"
  local scene_stem="$2"
  local raw_view_ids="$3"

  python3 - "$source_root" "$scene_stem" "$raw_view_ids" <<'PY'
from pathlib import Path
import sys

source_root = Path(sys.argv[1])
scene_stem = sys.argv[2]
requested_view_ids = [item.strip() for item in sys.argv[3].split(",") if item.strip()]
video_suffixes = {".mp4", ".mov", ".avi", ".mkv", ".webm"}

available_view_ids = []
for view_dir in sorted(path for path in source_root.iterdir() if path.is_dir() and path.name.isdigit()):
    generated_dir = view_dir / "generated_videos"
    if not generated_dir.is_dir():
        continue

    matches = [
        path for path in generated_dir.iterdir()
        if path.is_file() and path.stem == scene_stem and path.suffix.lower() in video_suffixes
    ]
    if matches:
        available_view_ids.append(view_dir.name)

if requested_view_ids:
    missing = [view_id for view_id in requested_view_ids if view_id not in available_view_ids]
    if missing:
        raise SystemExit(
            f"requested view ids do not contain `{scene_stem}` under generated_videos: {', '.join(missing)}"
        )
    print(",".join(requested_view_ids))
    raise SystemExit(0)

if not available_view_ids:
    raise SystemExit(f"no VerseCrafter generated videos named `{scene_stem}` were found under {source_root}")

print(",".join(available_view_ids))
PY
}

resolve_ffprobe_bin() {
  local ffmpeg_bin="$1"
  local ffprobe_bin="$2"

  if [[ -n "$ffprobe_bin" ]]; then
    printf '%s\n' "$ffprobe_bin"
    return 0
  fi

  if [[ "$ffmpeg_bin" == */* ]]; then
    local sibling
    sibling="$(cd -- "$(dirname -- "$ffmpeg_bin")" && pwd)/ffprobe"
    if [[ -x "$sibling" ]]; then
      printf '%s\n' "$sibling"
      return 0
    fi
  fi

  printf 'ffprobe\n'
}

infer_video_fps() {
  local source_root="$1"
  local scene_stem="$2"
  local first_view_id="$3"
  local ffprobe_bin="$4"

  python3 - "$source_root" "$scene_stem" "$first_view_id" "$ffprobe_bin" <<'PY'
from fractions import Fraction
from pathlib import Path
import json
import subprocess
import sys

source_root = Path(sys.argv[1])
scene_stem = sys.argv[2]
first_view_id = sys.argv[3]
ffprobe_bin = sys.argv[4]
video_path = source_root / first_view_id / "generated_videos" / f"{scene_stem}.mp4"

payload = subprocess.check_output(
    [
        ffprobe_bin,
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=avg_frame_rate,r_frame_rate",
        "-of",
        "json",
        str(video_path),
    ],
    text=True,
)
stream = json.loads(payload)["streams"][0]
raw_rate = stream.get("avg_frame_rate") or stream.get("r_frame_rate") or ""

if not raw_rate or raw_rate == "0/0":
    raise SystemExit(f"failed to infer fps from {video_path}")

fps = float(Fraction(raw_rate))
if fps <= 0:
    raise SystemExit(f"invalid fps {fps} from {video_path}")

if abs(round(fps) - fps) < 1e-6:
    print(int(round(fps)))
else:
    print(f"{fps:.6f}".rstrip("0").rstrip("."))
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

default_bridge_root() {
  local source_root="$1"
  local scene_stem="$2"
  local source_tag=""
  local scene_tag=""

  source_tag=$(sanitize_tag "$(basename -- "$source_root")")
  scene_tag=$(sanitize_tag "$scene_stem")
  printf '%s\n' "$REPO_ROOT/data/${source_tag}_${scene_tag}_versecrafter_bridge"
}

default_flashvsr_output_root() {
  local source_root="$1"
  local scene_stem="$2"
  local source_tag=""
  local scene_tag=""

  source_tag=$(sanitize_tag "$(basename -- "$source_root")")
  scene_tag=$(sanitize_tag "$scene_stem")
  printf '%s\n' "$REPO_ROOT/data/${source_tag}_${scene_tag}_flashvsr_reference"
}

default_prepared_root() {
  local source_root="$1"
  local scene_stem="$2"
  local run_tag="$3"
  local source_tag=""
  local scene_tag=""

  source_tag=$(sanitize_tag "$(basename -- "$source_root")")
  scene_tag=$(sanitize_tag "$scene_stem")
  printf '%s\n' "$REPO_ROOT/data/${source_tag}_${scene_tag}_${run_tag}_sr_rgb_root"
}

default_fastgs_root() {
  local source_root="$1"
  local scene_stem="$2"
  local source_tag=""
  local scene_tag=""

  source_tag=$(sanitize_tag "$(basename -- "$source_root")")
  scene_tag=$(sanitize_tag "$scene_stem")
  printf '%s\n' "$REPO_ROOT/data/${source_tag}_${scene_tag}_colmap_fastgs"
}

default_model_path() {
  local source_root="$1"
  local scene_stem="$2"
  local source_tag=""
  local scene_tag=""

  source_tag=$(sanitize_tag "$(basename -- "$source_root")")
  scene_tag=$(sanitize_tag "$scene_stem")
  printf '%s\n' "$REPO_ROOT/output/${source_tag}_${scene_tag}_colmap_fastgs"
}

build_bridge_root() {
  local source_root="$1"
  local bridge_root="$2"
  local scene_stem="$3"
  local view_ids_csv="$4"
  local ffprobe_bin="$5"

  if (( OVERWRITE )); then
    safe_remove "$bridge_root"
  elif [[ -e "$bridge_root" ]]; then
    fail "bridge root 已存在: $bridge_root, 如需重建请加 --overwrite"
  fi

  python3 - "$source_root" "$bridge_root" "$scene_stem" "$view_ids_csv" "$ffprobe_bin" <<'PY'
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys

import numpy as np

source_root = Path(sys.argv[1])
bridge_root = Path(sys.argv[2])
scene_stem = sys.argv[3]
view_ids = [item.strip() for item in sys.argv[4].split(",") if item.strip()]
ffprobe_bin = sys.argv[5]

if bridge_root.exists():
    shutil.rmtree(bridge_root)
bridge_root.mkdir(parents=True)

for view_id in view_ids:
    video_path = source_root / view_id / "generated_videos" / f"{scene_stem}.mp4"
    if not video_path.is_file():
        raise SystemExit(f"VerseCrafter video is missing: {video_path}")

    payload = subprocess.check_output(
        [
            ffprobe_bin,
            "-v",
            "error",
            "-count_frames",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,nb_read_frames,nb_frames",
            "-of",
            "json",
            str(video_path),
        ],
        text=True,
    )
    stream = json.loads(payload)["streams"][0]
    width = int(stream["width"])
    height = int(stream["height"])
    raw_frame_count = stream.get("nb_read_frames") or stream.get("nb_frames") or "0"
    frame_count = int(raw_frame_count)
    if frame_count <= 0:
        raise SystemExit(f"failed to infer frame count from {video_path}")

    # 这里只生成占位 pose/intrinsics.
    # 它们只用于通过 FlashVSR wrapper 的目录完整性检查.
    # 真正参与重建和训练的是后续 CUDA COLMAP.
    pose_data = np.repeat(np.eye(4, dtype=np.float32)[None, :, :], frame_count, axis=0)
    intrinsics = np.repeat(
        np.array([[float(width), float(height), width / 2.0, height / 2.0]], dtype=np.float32),
        frame_count,
        axis=0,
    )
    inds = np.arange(frame_count, dtype=np.int32)

    rgb_dir = bridge_root / view_id / "rgb"
    pose_dir = bridge_root / view_id / "pose"
    intrinsics_dir = bridge_root / view_id / "intrinsics"

    rgb_dir.mkdir(parents=True, exist_ok=True)
    pose_dir.mkdir(parents=True, exist_ok=True)
    intrinsics_dir.mkdir(parents=True, exist_ok=True)

    target_video = rgb_dir / f"{scene_stem}.mp4"
    if target_video.exists() or target_video.is_symlink():
        target_video.unlink()
    os.symlink(video_path.resolve(), target_video)

    np.savez(pose_dir / f"{scene_stem}.npz", data=pose_data, inds=inds)
    np.savez(intrinsics_dir / f"{scene_stem}.npz", data=intrinsics, inds=inds)

print(bridge_root)
PY
}

split_view_ids_for_gpus() {
  local view_ids_csv="$1"
  local gpu_ids_csv="$2"

  python3 - "$view_ids_csv" "$gpu_ids_csv" <<'PY'
import sys

view_ids = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
gpu_ids = [item.strip() for item in sys.argv[2].split(",") if item.strip()]

if not gpu_ids:
    raise SystemExit("superres gpu list must not be empty")

groups = {gpu_id: [] for gpu_id in gpu_ids}
for index, view_id in enumerate(view_ids):
    gpu_id = gpu_ids[index % len(gpu_ids)]
    groups[gpu_id].append(view_id)

for gpu_id in gpu_ids:
    members = groups[gpu_id]
    if members:
        print(f"{gpu_id}:{','.join(members)}")
PY
}

probe_local_superres_gpu() {
  local gpu_id="$1"

  env CUDA_VISIBLE_DEVICES="$gpu_id" "$LOCAL_PYTHON" - "$gpu_id" <<'PY'
import sys
import torch

gpu_id = sys.argv[1]
available = torch.cuda.is_available()
device_count = torch.cuda.device_count()

if not available or device_count < 1:
    print(
        f"gpu={gpu_id} torch.cuda.is_available()={available} device_count={device_count}",
        file=sys.stderr,
    )
    raise SystemExit(1)

print(torch.cuda.get_device_name(0))
PY
}

validate_local_superres_gpus() {
  local gpu_ids_csv="$1"
  local gpu_id=""
  local gpu_name=""

  IFS=',' read -r -a gpu_id_list <<< "$gpu_ids_csv"
  for gpu_id in "${gpu_id_list[@]}"; do
    gpu_id="${gpu_id// /}"
    [[ -n "$gpu_id" ]] || continue

    if ! gpu_name=$(probe_local_superres_gpu "$gpu_id"); then
      fail "FlashVSR local runner 当前无法使用 GPU $gpu_id. 已验证: CUDA_VISIBLE_DEVICES=$gpu_id 下 $LOCAL_PYTHON 无法得到可用 CUDA 设备. 请先修好这张卡, 或改用 --superres-gpu-ids 指向当前可用 GPU."
    fi

    log "FlashVSR GPU 预检通过: gpu=$gpu_id name=$gpu_name"
  done
}

run_superres_shards() {
  local run_tag="$1"
  local shard_root_base="$2"

  if [[ -e "$FLASHVSR_OUTPUT_ROOT" && "$PHASE" =~ ^(superres|prepare|all)$ ]] && (( ! OVERWRITE )); then
    fail "FlashVSR 输出目录已存在: $FLASHVSR_OUTPUT_ROOT, 如需重建请加 --overwrite"
  fi

  if (( OVERWRITE )); then
    safe_remove "$FLASHVSR_OUTPUT_ROOT"
    safe_remove "$shard_root_base"
  fi

  mkdir -p -- "$shard_root_base"

  local shard_specs=()
  mapfile -t shard_specs < <(split_view_ids_for_gpus "$VIEW_IDS" "$SUPERRES_GPU_IDS")
  [[ ${#shard_specs[@]} -gt 0 ]] || fail "没有可用于超分的视角分片"

  local pids=()
  local labels=()

  for shard_spec in "${shard_specs[@]}"; do
    local gpu_id="${shard_spec%%:*}"
    local shard_view_ids="${shard_spec#*:}"
    local shard_output_root="$shard_root_base/gpu_${gpu_id}"

    local cmd=(
      bash "$REPO_ROOT/scripts/run_lyra_flashvsr_reference.sh"
      --flashvsr-repo "$FLASHVSR_REPO"
      --script-python "$REFERENCE_PYTHON"
      --output-root "$shard_output_root"
      --runner "$RUNNER"
      --mode "$MODE"
      --scale "$SCALE"
      --dtype "$DTYPE"
      --quality "$QUALITY"
      --view-ids "$shard_view_ids"
      --scene-stem "$SCENE_STEM"
      --input-root "$BRIDGE_ROOT"
      --fallback-tile-size "$FALLBACK_TILE_SIZE"
      --fallback-overlap "$FALLBACK_OVERLAP"
      --debug-every "$DEBUG_EVERY"
    )

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
    if (( DRY_RUN )); then
      cmd+=(--dry-run)
    fi
    if [[ -n "$DEBUG_FRAME_INDICES" ]]; then
      cmd+=(--debug-frame-indices "$DEBUG_FRAME_INDICES")
    fi

    if [[ "$RUNNER" == "local" ]]; then
      cmd+=(--local-python "$LOCAL_PYTHON")
      log "启动超分分片: gpu=$gpu_id views=$shard_view_ids output=$shard_output_root"
      env CUDA_VISIBLE_DEVICES="$gpu_id" "${cmd[@]}" &
    else
      cmd+=(--docker-image "$DOCKER_IMAGE" --docker-gpus "device=${gpu_id}")
      log "启动超分分片: docker-gpu=$gpu_id views=$shard_view_ids output=$shard_output_root"
      "${cmd[@]}" &
    fi

    pids+=("$!")
    labels+=("gpu=$gpu_id views=$shard_view_ids")
  done

  local index=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      fail "FlashVSR 分片失败: ${labels[$index]}"
    fi
    index=$((index + 1))
  done

  python3 - "$FLASHVSR_OUTPUT_ROOT" "$run_tag" "$shard_root_base" <<'PY'
from pathlib import Path
import json
import shutil
import sys

final_root = Path(sys.argv[1])
run_tag = sys.argv[2]
shard_root_base = Path(sys.argv[3])

final_root.mkdir(parents=True, exist_ok=True)
merged_summaries = []

for shard_root in sorted(path for path in shard_root_base.iterdir() if path.is_dir()):
    shard_run_root = shard_root / run_tag
    if shard_run_root.is_dir():
        for view_dir in sorted(path for path in shard_run_root.iterdir() if path.is_dir()):
            target_dir = final_root / run_tag / view_dir.name
            target_dir.parent.mkdir(parents=True, exist_ok=True)
            if target_dir.exists():
                raise SystemExit(f"duplicate FlashVSR view output while merging shards: {target_dir}")
            shutil.move(str(view_dir), str(target_dir))

    shard_summary_path = shard_root / "flashvsr_reference_summary.json"
    if shard_summary_path.is_file():
        merged_summaries.extend(json.loads(shard_summary_path.read_text(encoding='utf-8')))

final_summary_path = final_root / "flashvsr_reference_summary.json"
final_summary_path.write_text(
    json.dumps(merged_summaries, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
print(final_summary_path)
PY

  safe_remove "$shard_root_base"
}

build_prepared_root() {
  local run_tag="$1"

  if (( OVERWRITE )); then
    safe_remove "$PREPARED_ROOT"
  elif [[ -e "$PREPARED_ROOT" ]]; then
    fail "prepared root 已存在: $PREPARED_ROOT, 如需重建请加 --overwrite"
  fi

  python3 - "$FLASHVSR_OUTPUT_ROOT" "$PREPARED_ROOT" "$run_tag" "$SCENE_STEM" "$VIEW_IDS" <<'PY'
from pathlib import Path
import os
import shutil
import sys

flashvsr_output_root = Path(sys.argv[1])
prepared_root = Path(sys.argv[2])
run_tag = sys.argv[3]
scene_stem = sys.argv[4]
view_ids = [item.strip() for item in sys.argv[5].split(",") if item.strip()]

if prepared_root.exists():
    shutil.rmtree(prepared_root)
prepared_root.mkdir(parents=True)

for view_id in view_ids:
    source_video = flashvsr_output_root / run_tag / view_id / "rgb" / f"{scene_stem}.mp4"
    if not source_video.is_file():
        raise SystemExit(f"missing SR video for prepared root: {source_video}")

    target_rgb_dir = prepared_root / view_id / "rgb"
    target_rgb_dir.mkdir(parents=True, exist_ok=True)
    target_video = target_rgb_dir / f"{scene_stem}.mp4"
    if target_video.exists() or target_video.is_symlink():
        target_video.unlink()
    os.symlink(source_video.resolve(), target_video)

print(prepared_root)
PY
}

ensure_prepared_root_from_existing_superres() {
  local run_tag="$1"

  if [[ -d "$PREPARED_ROOT" ]]; then
    return 0
  fi

  [[ -d "$FLASHVSR_OUTPUT_ROOT/$run_tag" ]] || fail "缺少已有 SR 输出: $FLASHVSR_OUTPUT_ROOT/$run_tag"
  build_prepared_root "$run_tag"
}

has_fastgs_dataset() {
  [[ -d "$FASTGS_ROOT/images" && -d "$FASTGS_ROOT/sparse/0" ]]
}

run_colmap_phase() {
  local phase_name="$1"
  local visible_devices="$2"

  local cmd=(
    bash "$REPO_ROOT/scripts/run_lyra_colmap_fastgs.sh"
    --phase "$phase_name"
    --source-path "$PREPARED_ROOT"
    --fastgs-root "$FASTGS_ROOT"
    --model-path "$MODEL_PATH"
    --python-bin "$PYTHON_BIN"
    --pixi-bin "$PIXI_BIN"
    --colmap-bin "$COLMAP_BIN"
    --ffmpeg-bin "$FFMPEG_BIN"
    --camera-model "$CAMERA_MODEL"
    --video-fps "$VIDEO_FPS"
    -r "$RESOLUTION"
    --iterations "$ITERATIONS"
    --iteration "$ITERATION"
  )

  if [[ -n "$COLMAP_GPU_INDEX" ]]; then
    cmd+=(--colmap-gpu-index "$COLMAP_GPU_INDEX")
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

  # `prepare` 阶段里的多卡选择已经通过 `--colmap-gpu-index` 显式传给 COLMAP.
  # 这里不再额外强塞 `CUDA_VISIBLE_DEVICES`, 以免非 0/1 编号时发生重映射歧义.
  if [[ "$phase_name" == "prepare" ]]; then
    log "执行 COLMAP / FastGS 阶段: phase=$phase_name colmap_gpu_index=$COLMAP_GPU_INDEX"
    "${cmd[@]}"
    return 0
  fi

  log "执行 COLMAP / FastGS 阶段: phase=$phase_name visible_devices=$visible_devices"
  env CUDA_VISIBLE_DEVICES="$visible_devices" "${cmd[@]}"
}

while (( $# > 0 )); do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --source-path)
      VERSE_ROOT="$2"
      shift 2
      ;;
    --scene-stem)
      SCENE_STEM="$2"
      shift 2
      ;;
    --view-ids)
      VIEW_IDS="$2"
      shift 2
      ;;
    --lyra-root)
      # 兼容旧命令行.
      # VerseCrafter wrapper 现在已经不再依赖 `../lyra`.
      shift 2
      ;;
    --flashvsr-repo)
      FLASHVSR_REPO="$2"
      shift 2
      ;;
    --script-python|--lyra-python)
      REFERENCE_PYTHON="$2"
      shift 2
      ;;
    --local-python)
      LOCAL_PYTHON="$2"
      shift 2
      ;;
    --pixi-bin)
      PIXI_BIN="$2"
      shift 2
      ;;
    --python-bin)
      PYTHON_BIN="$2"
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
    --ffprobe-bin)
      FFPROBE_BIN="$2"
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
    --superres-gpu-ids)
      SUPERRES_GPU_IDS="$2"
      shift 2
      ;;
    --colmap-gpu-index)
      COLMAP_GPU_INDEX="$2"
      shift 2
      ;;
    --train-gpu-id)
      TRAIN_GPU_ID="$2"
      shift 2
      ;;
    --bridge-root)
      BRIDGE_ROOT="$2"
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
    --fastgs-root)
      FASTGS_ROOT="$2"
      shift 2
      ;;
    --model-path)
      MODEL_PATH="$2"
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
    --eval)
      EVAL_MODE="--eval"
      shift
      ;;
    --no-eval)
      EVAL_MODE="--no-eval"
      shift
      ;;
    --keep-bridge-root)
      KEEP_BRIDGE_ROOT=1
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

case "$CAMERA_MODEL" in
  SIMPLE_PINHOLE|PINHOLE|OPENCV)
    ;;
  *)
    fail "--camera-model 只支持 SIMPLE_PINHOLE / PINHOLE / OPENCV"
    ;;
esac

if (( DRY_RUN )) && [[ "$PHASE" != "superres" ]]; then
  fail "--dry-run 当前只支持与 --phase superres 搭配使用"
fi

[[ "$QUALITY" =~ ^([0-9]|10)$ ]] || fail "--quality 必须是 0 到 10 的整数"
[[ "$FALLBACK_TILE_SIZE" =~ ^[1-9][0-9]*$ ]] || fail "--fallback-tile-size 必须是 >= 1 的整数"
[[ "$FALLBACK_OVERLAP" =~ ^[0-9]+$ ]] || fail "--fallback-overlap 必须是 >= 0 的整数"
[[ "$DEBUG_EVERY" =~ ^[1-9][0-9]*$ ]] || fail "--debug-every 必须是 >= 1 的整数"
[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || fail "--iterations 必须是 >= 1 的整数"
[[ "$ITERATION" =~ ^-?[0-9]+$ ]] || fail "--iteration 必须是整数"

python3 - <<'PY' "$SCALE" "$RESOLUTION"
import sys

scale = float(sys.argv[1])
if scale <= 0:
    raise SystemExit(1)

resolution = sys.argv[2]
int(resolution)
PY

require_cmd python3
require_cmd "$PYTHON_BIN"
require_cmd "$PIXI_BIN"

FLASHVSR_REPO=$(normalize_path "$REPO_ROOT" "$FLASHVSR_REPO")
COLMAP_BIN=$(normalize_binary_if_path "$REPO_ROOT" "$COLMAP_BIN")
FFMPEG_BIN=$(normalize_binary_if_path "$REPO_ROOT" "$FFMPEG_BIN")
FFPROBE_BIN=$(resolve_ffprobe_bin "$FFMPEG_BIN" "$FFPROBE_BIN")
if [[ "$FFPROBE_BIN" == */* ]]; then
  FFPROBE_BIN=$(normalize_path "$REPO_ROOT" "$FFPROBE_BIN")
fi

if [[ -z "$REFERENCE_PYTHON" ]]; then
  REFERENCE_PYTHON=$(default_reference_python)
fi
if [[ -z "$LOCAL_PYTHON" ]]; then
  LOCAL_PYTHON="$REFERENCE_PYTHON"
fi

REFERENCE_PYTHON=$(normalize_binary_if_path "$REPO_ROOT" "$REFERENCE_PYTHON")
LOCAL_PYTHON=$(normalize_binary_if_path "$REPO_ROOT" "$LOCAL_PYTHON")

if [[ -z "$VERSE_ROOT" ]]; then
  fail "必须传 --source-path 指向 VerseCrafter 输出根目录"
fi
VERSE_ROOT=$(normalize_path "$REPO_ROOT" "$VERSE_ROOT")

require_dir "$VERSE_ROOT"
require_dir "$FLASHVSR_REPO"
require_file "$REFERENCE_PYTHON"
if [[ "$RUNNER" == "local" && "$LOCAL_PYTHON" == */* ]]; then
  require_file "$LOCAL_PYTHON"
fi

if [[ "$COLMAP_BIN" == */* ]]; then
  require_file "$COLMAP_BIN"
else
  require_cmd "$COLMAP_BIN"
fi
if [[ "$FFMPEG_BIN" == */* ]]; then
  require_file "$FFMPEG_BIN"
else
  require_cmd "$FFMPEG_BIN"
fi
if [[ "$FFPROBE_BIN" == */* ]]; then
  require_file "$FFPROBE_BIN"
else
  require_cmd "$FFPROBE_BIN"
fi

SCENE_STEM=$(resolve_scene_stem "$VERSE_ROOT" "$SCENE_STEM" "$VIEW_IDS")
VIEW_IDS=$(discover_view_ids "$VERSE_ROOT" "$SCENE_STEM" "$VIEW_IDS")
RUN_TAG=$(build_run_tag "$MODE" "$SCALE")

if [[ -z "$COLMAP_GPU_INDEX" ]]; then
  COLMAP_GPU_INDEX="$SUPERRES_GPU_IDS"
fi

if [[ -z "$TRAIN_GPU_ID" ]]; then
  TRAIN_GPU_ID=$(python3 - <<'PY' "$SUPERRES_GPU_IDS"
import sys
gpu_ids = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
print(gpu_ids[0] if gpu_ids else "0")
PY
)
fi

if [[ -z "$VIDEO_FPS" ]]; then
  FIRST_VIEW_ID=$(python3 - <<'PY' "$VIEW_IDS"
import sys
view_ids = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
print(view_ids[0])
PY
)
  VIDEO_FPS=$(infer_video_fps "$VERSE_ROOT" "$SCENE_STEM" "$FIRST_VIEW_ID" "$FFPROBE_BIN")
fi

if [[ -z "$BRIDGE_ROOT" ]]; then
  BRIDGE_ROOT=$(default_bridge_root "$VERSE_ROOT" "$SCENE_STEM")
else
  BRIDGE_ROOT=$(normalize_path "$REPO_ROOT" "$BRIDGE_ROOT")
fi

if [[ -z "$FLASHVSR_OUTPUT_ROOT" ]]; then
  FLASHVSR_OUTPUT_ROOT=$(default_flashvsr_output_root "$VERSE_ROOT" "$SCENE_STEM")
else
  FLASHVSR_OUTPUT_ROOT=$(normalize_path "$REPO_ROOT" "$FLASHVSR_OUTPUT_ROOT")
fi

if [[ -z "$PREPARED_ROOT" ]]; then
  PREPARED_ROOT=$(default_prepared_root "$VERSE_ROOT" "$SCENE_STEM" "$RUN_TAG")
else
  PREPARED_ROOT=$(normalize_path "$REPO_ROOT" "$PREPARED_ROOT")
fi

if [[ -z "$FASTGS_ROOT" ]]; then
  FASTGS_ROOT=$(default_fastgs_root "$VERSE_ROOT" "$SCENE_STEM")
else
  FASTGS_ROOT=$(normalize_path "$REPO_ROOT" "$FASTGS_ROOT")
fi

if [[ -z "$MODEL_PATH" ]]; then
  MODEL_PATH=$(default_model_path "$VERSE_ROOT" "$SCENE_STEM")
else
  MODEL_PATH=$(normalize_path "$REPO_ROOT" "$MODEL_PATH")
fi

SHARD_ROOT_BASE="$REPO_ROOT/data/$(sanitize_tag "$(basename -- "$VERSE_ROOT")")_$(sanitize_tag "$SCENE_STEM")_flashvsr_shards"

log "Phase: $PHASE"
log "VerseCrafter root: $VERSE_ROOT"
log "Scene stem: $SCENE_STEM"
log "View ids: $VIEW_IDS"
log "Superres GPU ids: $SUPERRES_GPU_IDS"
log "COLMAP GPU index: $COLMAP_GPU_INDEX"
log "Train GPU id: $TRAIN_GPU_ID"
log "Bridge root: $BRIDGE_ROOT"
log "FlashVSR output root: $FLASHVSR_OUTPUT_ROOT"
log "Prepared root: $PREPARED_ROOT"
log "FastGS root: $FASTGS_ROOT"
log "Model path: $MODEL_PATH"
log "Video fps: $VIDEO_FPS"

if [[ "$PHASE" == "superres" || "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  if [[ "$RUNNER" == "local" && "$DRY_RUN" -eq 0 ]]; then
    validate_local_superres_gpus "$SUPERRES_GPU_IDS"
  fi

  build_bridge_root "$VERSE_ROOT" "$BRIDGE_ROOT" "$SCENE_STEM" "$VIEW_IDS" "$FFPROBE_BIN"
  run_superres_shards "$RUN_TAG" "$SHARD_ROOT_BASE"
fi

if [[ "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  build_prepared_root "$RUN_TAG"
fi

case "$PHASE" in
  superres)
    ;;
  prepare)
    run_colmap_phase "prepare" "$COLMAP_GPU_INDEX"
    ;;
  train)
    if ! has_fastgs_dataset; then
      ensure_prepared_root_from_existing_superres "$RUN_TAG"
    fi
    run_colmap_phase "train" "$TRAIN_GPU_ID"
    ;;
  render)
    run_colmap_phase "render" "$TRAIN_GPU_ID"
    ;;
  metrics)
    run_colmap_phase "metrics" "$TRAIN_GPU_ID"
    ;;
  evaluate)
    run_colmap_phase "render" "$TRAIN_GPU_ID"
    run_colmap_phase "metrics" "$TRAIN_GPU_ID"
    ;;
  all)
    run_colmap_phase "prepare" "$COLMAP_GPU_INDEX"
    run_colmap_phase "train" "$TRAIN_GPU_ID"
    run_colmap_phase "render" "$TRAIN_GPU_ID"
    run_colmap_phase "metrics" "$TRAIN_GPU_ID"
    ;;
esac

if (( ! KEEP_BRIDGE_ROOT )) && [[ "$PHASE" == "superres" || "$PHASE" == "prepare" || "$PHASE" == "all" ]]; then
  safe_remove "$BRIDGE_ROOT"
fi
