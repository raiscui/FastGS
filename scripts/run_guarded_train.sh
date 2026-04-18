#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run_guarded_train.sh \
    --data /path/to/fastgs_root \
    --model /path/to/output_model \
    [--gpu 0] \
    [--images images] \
    [--iterations 35000] \
    [--segment-steps 1000]

This runs FastGS training in guarded segments. Each segment saves a checkpoint,
and failures are retried with the next seed before giving up.

Stable defaults in this helper match the settings that have been repeatedly
validated in this repository for long multi-view runs:
  --densification_interval 500
  --opacity_reset_interval 3000
  --densify_until_iter 15000
  --densify_prune_min_opacity 0.005
  --final_prune_min_opacity 0.1
  --final_prune_interval 3000
  --final_prune_from_iter 15000
  --final_prune_until_iter 30000
  --position_lr_max_steps 35000
  --loss_thresh 0.1
  --grad_thresh 0.0002
  --grad_abs_thresh 0.0012
  --highfeature_lr 0.005
  --lowfeature_lr 0.0025
  --dense 0.001
  --mult 0.5

Extra train.py arguments may be appended after `--`.
For example, stronger transparent-Gaussian cleanup can be requested with:
  bash scripts/run_guarded_train.sh ... -- \
    --densify_prune_min_opacity 0.01 \
    --final_prune_min_opacity 0.15 \
    --final_prune_interval 1000 \
    --final_prune_until_iter 35000
EOF
}

DATA=""
MODEL=""
GPU="${CUDA_VISIBLE_DEVICES:-0}"
IMAGES="images"
ITERATIONS=35000
SEGMENT_STEPS=1000
START_SEED=0
END_SEED=4
RESOLUTION=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)
      DATA="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --gpu)
      GPU="$2"
      shift 2
      ;;
    --images)
      IMAGES="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --segment-steps)
      SEGMENT_STEPS="$2"
      shift 2
      ;;
    --start-seed)
      START_SEED="$2"
      shift 2
      ;;
    --end-seed)
      END_SEED="$2"
      shift 2
      ;;
    -r|--resolution)
      RESOLUTION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DATA" || -z "$MODEL" ]]; then
  echo "--data and --model are required." >&2
  usage >&2
  exit 1
fi

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "--iterations must be a positive integer." >&2
  exit 1
fi

if ! [[ "$SEGMENT_STEPS" =~ ^[1-9][0-9]*$ ]]; then
  echo "--segment-steps must be a positive integer." >&2
  exit 1
fi

if (( ITERATIONS % SEGMENT_STEPS != 0 )); then
  echo "--iterations must be divisible by --segment-steps." >&2
  exit 1
fi

EXTRA_ARGS=("$@")

mkdir -p "$MODEL"

cd "$REPO_ROOT"

for target in $(seq "$SEGMENT_STEPS" "$SEGMENT_STEPS" "$ITERATIONS"); do
  prev=$((target - SEGMENT_STEPS))

  if [[ -f "$MODEL/checkpoints/ckpt_${target}.pth" ]]; then
    echo "skip existing ckpt_${target}.pth"
    continue
  fi

  ok=0
  for seed in $(seq "$START_SEED" "$END_SEED"); do
    echo "== target=$target seed=$seed gpu=$GPU =="

    cmd=(
      pixi run python train.py
      -s "$DATA"
      -m "$MODEL"
      -i "$IMAGES"
      -r "$RESOLUTION"
      --eval
      --iterations "$target"
      --densification_interval 500
      --opacity_reset_interval 3000
      --densify_until_iter 15000
      --densify_prune_min_opacity 0.005
      --final_prune_min_opacity 0.1
      --final_prune_interval 3000
      --final_prune_from_iter 15000
      --final_prune_until_iter 30000
      --position_lr_max_steps 35000
      --loss_thresh 0.1
      --grad_thresh 0.0002
      --grad_abs_thresh 0.0012
      --highfeature_lr 0.005
      --lowfeature_lr 0.0025
      --dense 0.001
      --mult 0.5
      --optimizer_type default
      --save_iterations "$target"
      --checkpoint_iterations "$target"
      --seed "$seed"
    )

    if (( prev > 0 )); then
      cmd+=(--start_checkpoint "$MODEL/checkpoints/ckpt_${prev}.pth")
    fi

    if ((${#EXTRA_ARGS[@]} > 0)); then
      cmd+=("${EXTRA_ARGS[@]}")
    fi

    if CUDA_VISIBLE_DEVICES="$GPU" "${cmd[@]}"; then
      ok=1
      break
    fi
  done

  if (( ok != 1 )); then
    echo "failed at target=$target after trying seeds ${START_SEED}-${END_SEED}" >&2
    exit 1
  fi
done
