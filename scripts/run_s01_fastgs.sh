#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

# ============================================================
# s01 -> COLMAP -> FastGS 一键脚本
#
# 这份脚本默认面向当前仓库内的 `data/s01`.
# 它会完成:
# 1. 多机位图片整理为 COLMAP 可读目录
# 2. COLMAP 稀疏重建
# 3. 整理成 FastGS 可训练目录
# 4. 启动 FastGS 训练
#
# 关键修正:
# - 不能用“目录软链接”当 COLMAP 输入
# - 必须使用“真实目录 + 文件级软链接/复制”
# ============================================================

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

SCENE_ROOT="$REPO_ROOT/data/s01"
COLMAP_ROOT="$REPO_ROOT/data/s01_colmap"
FASTGS_ROOT="$REPO_ROOT/data/s01_fastgs"
COLMAP_BIN="/workspace/colmap-cuda-install-3.12.6/bin/colmap"
PIXI_BIN="pixi"
MODEL_PATH="output/s01"
CAMERA_MODEL="SIMPLE_PINHOLE"

PHASE="all"
RESOLUTION=2
ITERATIONS=30000
FRAME_STEP=1
FRAME_LIMIT=0
EVAL=0
OVERWRITE=0

# 这组参数直接对齐 `train.py` / `docs/fastgs-train-scripts.md`.
# 默认值刻意与当前代码默认值保持一致,这样脚本既可直接调参,也不会偷偷改变仓库默认行为.
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
  bash scripts/run_s01_fastgs.sh [选项]

默认行为:
  - 从 `data/s01` 准备 COLMAP 数据
  - 生成 `data/s01_fastgs`
  - 启动 FastGS 训练到 `output/s01`

常用示例:
  1) 直接全流程:
     bash scripts/run_s01_fastgs.sh

  2) 只做前处理:
     bash scripts/run_s01_fastgs.sh --phase prepare

  3) 小样本 smoke test:
     bash scripts/run_s01_fastgs.sh \
       --overwrite \
       --frame-limit 1 \
       --iterations 10 \
       --model-path output/s01_script_smoke

  4) 带 test 切分训练:
     bash scripts/run_s01_fastgs.sh --eval

  5) 如需改回双焦距模型:
     bash scripts/run_s01_fastgs.sh --camera-model PINHOLE

  6) 覆盖 FastGS 高级训练参数:
     bash scripts/run_s01_fastgs.sh \
       -r 1 \
       --densification_interval 500 \
       --grad_abs_thresh 0.0008 \
       --dense 0.01 \
       --mult 0.7

选项:
  --phase <all|prepare|train>     执行阶段,默认 all
  --scene-root <path>             原始多机位目录,默认 data/s01
  --colmap-root <path>            COLMAP 工作目录,默认 data/s01_colmap
  --fastgs-root <path>            FastGS 数据目录,默认 data/s01_fastgs
  --colmap-bin <path>             COLMAP 可执行文件
  --pixi-bin <path>               pixi 可执行文件,默认 pixi
  --model-path <path>             训练输出目录,默认 output/s01
  --camera-model <SIMPLE_PINHOLE|PINHOLE>
                                   COLMAP 相机模型,默认 SIMPLE_PINHOLE
  -r, --resolution <1|2|4|8|宽度> 训练分辨率,默认 2
  --iterations <n>                训练迭代数,默认 30000
  --frame-step <n>                每隔多少帧取 1 张,默认 1
  --frame-limit <n>               每个相机最多取多少张,0 表示全取
  --densification_interval <n>    FastGS 增点间隔,默认 100
  --loss_thresh <x>               FastGS 高误差像素阈值,默认 0.1
  --grad_thresh <x>               clone 梯度阈值,默认 0.0002
  --grad_abs_thresh <x>           split 梯度阈值,默认 0.0012
  --highfeature_lr <x>            高阶 SH 学习率入口值,默认 0.005
  --lowfeature_lr <x>             低阶 SH 学习率,默认 0.0025
  --dense <x>                     clone / split 尺寸分界,默认 0.001
  --mult <x>                      compact box 系数,默认 0.5
  --optimizer_type <name>         优化器类型,默认 default
  --eval                          训练时启用 test 切分
  --overwrite                     删除脚本生成的旧结果后重跑
  -h, --help                      显示帮助
EOF
}

log() {
  printf '[s01-fastgs] %s\n' "$*"
}

fail() {
  printf '[s01-fastgs] ERROR: %s\n' "$*" >&2
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

db_scalar() {
  local db_path="$1"
  local sql="$2"

  python3 - "$db_path" "$sql" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
sql = sys.argv[2]

conn = sqlite3.connect(db_path)
try:
    value = conn.execute(sql).fetchone()[0]
finally:
    conn.close()

print(value)
PY
}

prepare_camera_links() {
  local images_root="$COLMAP_ROOT/images"
  local linked_total=0
  local camera_count=0
  declare -A basename_seen=()

  mkdir -p "$images_root"

  for camera_dir in "$SCENE_ROOT"/C*pick; do
    [[ -d "$camera_dir" ]] || continue

    local camera_name
    camera_name=$(basename "$camera_dir")

    local target_dir="$images_root/$camera_name"
    mkdir -p "$target_dir"

    mapfile -t camera_images < <(
      find "$camera_dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) | sort
    )

    (( ${#camera_images[@]} > 0 )) || fail "相机目录没有图片: $camera_dir"

    local linked_for_camera=0
    local index=0

    while (( index < ${#camera_images[@]} )); do
      local image_path="${camera_images[$index]}"
      local image_name
      image_name=$(basename "$image_path")

      if [[ -n "${basename_seen[$image_name]+x}" ]]; then
        fail "检测到重名图片,无法扁平化给 FastGS: $image_name"
      fi

      ln -sfn "$image_path" "$target_dir/$image_name"
      basename_seen["$image_name"]=1

      (( linked_for_camera += 1 ))
      (( linked_total += 1 ))

      if (( FRAME_LIMIT > 0 && linked_for_camera >= FRAME_LIMIT )); then
        break
      fi

      (( index += FRAME_STEP ))
    done

    (( linked_for_camera > 0 )) || fail "相机目录经过采样后没有可用图片: $camera_dir"
    (( camera_count += 1 ))
    log "已链接相机 $camera_name: $linked_for_camera 张"
  done

  (( camera_count > 0 )) || fail "在 $SCENE_ROOT 下没有找到任何 `C*pick` 相机目录"
  log "总计已准备 $camera_count 个相机, 共 $linked_total 张图"
}

choose_sparse_model_dir() {
  mapfile -t model_dirs < <(find "$COLMAP_ROOT/sparse" -mindepth 1 -maxdepth 1 -type d | sort)
  (( ${#model_dirs[@]} > 0 )) || fail "COLMAP 没有生成任何 sparse 子模型目录"

  if (( ${#model_dirs[@]} == 1 )); then
    printf '%s\n' "${model_dirs[0]}"
    return 0
  fi

  local best_dir="${model_dirs[0]}"
  local best_images=-1

  for model_dir in "${model_dirs[@]}"; do
    local registered_images
    registered_images=$("$COLMAP_BIN" model_analyzer --path "$model_dir" 2>/dev/null | \
      awk -F': ' '/Registered images/ {print $2; exit}')
    registered_images=${registered_images:-0}

    log "检测到子模型 $model_dir, Registered images=$registered_images"

    if (( registered_images > best_images )); then
      best_images=$registered_images
      best_dir="$model_dir"
    fi
  done

  printf '%s\n' "$best_dir"
}

prepare_dataset() {
  require_dir "$SCENE_ROOT"
  require_file "$COLMAP_BIN"
  require_cmd python3

  if (( OVERWRITE )); then
    log "检测到 --overwrite, 准备清理旧的中间结果"
    safe_remove "$COLMAP_ROOT"
    safe_remove "$FASTGS_ROOT"
  else
    [[ ! -e "$COLMAP_ROOT" ]] || fail "已存在 $COLMAP_ROOT, 如需重跑请加 --overwrite"
    [[ ! -e "$FASTGS_ROOT" ]] || fail "已存在 $FASTGS_ROOT, 如需重跑请加 --overwrite"
  fi

  mkdir -p "$COLMAP_ROOT"
  prepare_camera_links

  log "COLMAP 相机模型: $CAMERA_MODEL"

  run_cmd "$COLMAP_BIN" feature_extractor \
    --database_path "$COLMAP_ROOT/database.db" \
    --image_path "$COLMAP_ROOT/images" \
    --ImageReader.single_camera_per_folder 1 \
    --ImageReader.camera_model "$CAMERA_MODEL" \
    --SiftExtraction.use_gpu 1

  local image_count
  image_count=$(db_scalar "$COLMAP_ROOT/database.db" "select count(*) from images;")
  local camera_count
  camera_count=$(db_scalar "$COLMAP_ROOT/database.db" "select count(*) from cameras;")

  log "feature_extractor 完成: cameras=$camera_count, images=$image_count"
  (( image_count > 0 )) || fail "COLMAP 数据库中没有图片. 当前脚本预期应已避开目录软链接问题, 请检查日志"

  run_cmd "$COLMAP_BIN" exhaustive_matcher \
    --database_path "$COLMAP_ROOT/database.db" \
    --SiftMatching.use_gpu 1

  local geometry_count
  geometry_count=$(db_scalar "$COLMAP_ROOT/database.db" "select count(*) from two_view_geometries;")
  log "exhaustive_matcher 完成: two_view_geometries=$geometry_count"
  (( geometry_count > 0 )) || fail "没有任何 two_view_geometries. 这说明图像之间没有成功建立几何验证匹配"

  mkdir -p "$COLMAP_ROOT/sparse"

  run_cmd "$COLMAP_BIN" mapper \
    --database_path "$COLMAP_ROOT/database.db" \
    --image_path "$COLMAP_ROOT/images" \
    --output_path "$COLMAP_ROOT/sparse" \
    --Mapper.ba_global_function_tolerance 0.000001

  local sparse_model_dir
  sparse_model_dir=$(choose_sparse_model_dir)
  log "选定 sparse 模型目录: $sparse_model_dir"

  run_cmd "$COLMAP_BIN" image_undistorter \
    --image_path "$COLMAP_ROOT/images" \
    --input_path "$sparse_model_dir" \
    --output_path "$COLMAP_ROOT/undistorted" \
    --output_type COLMAP

  mkdir -p "$FASTGS_ROOT/images"
  mkdir -p "$FASTGS_ROOT/sparse/0"

  find "$COLMAP_ROOT/undistorted/images" -type f \( -iname '*.jpg' -o -iname '*.png' \) \
    -exec cp -f {} "$FASTGS_ROOT/images/" \;

  cp -f "$COLMAP_ROOT"/undistorted/sparse/* "$FASTGS_ROOT/sparse/0/"

  local fastgs_image_count
  fastgs_image_count=$(find "$FASTGS_ROOT/images" -maxdepth 1 -type f | wc -l)
  log "FastGS 数据目录已就绪: images=$fastgs_image_count, sparse=$FASTGS_ROOT/sparse/0"
}

train_model() {
  require_cmd "$PIXI_BIN"
  require_dir "$FASTGS_ROOT"
  require_dir "$FASTGS_ROOT/images"
  require_dir "$FASTGS_ROOT/sparse/0"

  local model_abs="$MODEL_PATH"

  if (( OVERWRITE )); then
    safe_remove "$model_abs"
  elif [[ -e "$model_abs" ]]; then
    fail "训练输出目录已存在: $model_abs, 如需覆盖请加 --overwrite"
  fi

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

while (( $# > 0 )); do
  case "$1" in
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --scene-root)
      SCENE_ROOT="$2"
      shift 2
      ;;
    --colmap-root)
      COLMAP_ROOT="$2"
      shift 2
      ;;
    --fastgs-root)
      FASTGS_ROOT="$2"
      shift 2
      ;;
    --colmap-bin)
      COLMAP_BIN="$2"
      shift 2
      ;;
    --pixi-bin)
      PIXI_BIN="$2"
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
    -r|--resolution)
      RESOLUTION="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --frame-step)
      FRAME_STEP="$2"
      shift 2
      ;;
    --frame-limit)
      FRAME_LIMIT="$2"
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
  all|prepare|train)
    ;;
  *)
    fail "--phase 只支持 all / prepare / train"
    ;;
esac

[[ "$FRAME_STEP" =~ ^[1-9][0-9]*$ ]] || fail "--frame-step 必须是 >= 1 的整数"
[[ "$FRAME_LIMIT" =~ ^[0-9]+$ ]] || fail "--frame-limit 必须是 >= 0 的整数"
[[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]] || fail "--iterations 必须是 >= 1 的整数"
[[ "$DENSIFICATION_INTERVAL" =~ ^[1-9][0-9]*$ ]] || fail "--densification_interval 必须是 >= 1 的整数"
case "$CAMERA_MODEL" in
  SIMPLE_PINHOLE|PINHOLE)
    ;;
  *)
    fail "--camera-model 只支持 SIMPLE_PINHOLE / PINHOLE"
    ;;
esac
case "$OPTIMIZER_TYPE" in
  default|sparse_adam)
    ;;
  *)
    fail "--optimizer_type 只支持 default / sparse_adam"
    ;;
esac

SCENE_ROOT=$(normalize_path "$SCENE_ROOT")
COLMAP_ROOT=$(normalize_path "$COLMAP_ROOT")
FASTGS_ROOT=$(normalize_path "$FASTGS_ROOT")
COLMAP_BIN=$(normalize_path "$COLMAP_BIN")
MODEL_PATH=$(normalize_path "$MODEL_PATH")

cd "$REPO_ROOT"

log "仓库根目录: $REPO_ROOT"
log "执行阶段: $PHASE"
log "原始数据目录: $SCENE_ROOT"
log "COLMAP 工作目录: $COLMAP_ROOT"
log "FastGS 数据目录: $FASTGS_ROOT"
log "COLMAP 可执行文件: $COLMAP_BIN"
log "COLMAP 相机模型: $CAMERA_MODEL"
log "训练输出目录: $MODEL_PATH"
log "训练分辨率: $RESOLUTION"
log "训练迭代数: $ITERATIONS"
log "高级训练参数: densification_interval=$DENSIFICATION_INTERVAL loss_thresh=$LOSS_THRESH grad_thresh=$GRAD_THRESH grad_abs_thresh=$GRAD_ABS_THRESH"
log "高级训练参数: highfeature_lr=$HIGHFEATURE_LR lowfeature_lr=$LOWFEATURE_LR dense=$DENSE mult=$MULT optimizer_type=$OPTIMIZER_TYPE"
log "采样参数: frame_step=$FRAME_STEP, frame_limit=$FRAME_LIMIT"

case "$PHASE" in
  prepare)
    prepare_dataset
    ;;
  train)
    train_model
    ;;
  all)
    prepare_dataset
    train_model
    ;;
esac

log "全部完成"
