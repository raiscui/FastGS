cd /home/rais/FastGS

DATA=/autodl-fs/data/fastgs/dm4_sr
MODEL=/autodl-fs/data/fastgs/output/dm4_sr_35000_guarded

mkdir -p "$MODEL"

for target in $(seq 1000 1000 35000); do
prev=$((target - 1000))

if [ -f "$MODEL/checkpoints/ckpt_${target}.pth" ]; then
    echo "skip existing ckpt_${target}.pth"
    continue
fi

ok=0
for seed in 0 1 2 3 4; do
    echo "== target=$target seed=$seed =="

    cmd=(
    pixi run python train.py
    -s "$DATA"
    -m "$MODEL"
    -i images
    -r 1
    --eval
    --iterations "$target"
    --densification_interval 500
    --opacity_reset_interval 3000
    --densify_until_iter 15000
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

    if [ "$prev" -gt 0 ]; then
    cmd+=(--start_checkpoint "$MODEL/checkpoints/ckpt_${prev}.pth")
    fi

    if CUDA_VISIBLE_DEVICES=0 "${cmd[@]}"; then
    ok=1
    break
    fi
done

if [ "$ok" -ne 1 ]; then
    echo "failed at target=$target after trying multiple seeds"
    exit 1
fi
done