  bash /workspace/FastGS/scripts/run_versecrafter_flashvsr_fastgs.sh \
    --source-path /workspace/VerseCrafter/demo_data/my4 \
    --scene-stem generated_video_0 \
    --phase all \
    --mode full \
    --scale 2.0 \
    --dtype bf16 \
    --quality 10 \
    --video-fps 8 \
    --superres-gpu-ids 0,1 \
    --colmap-gpu-index 0,1 \
    --train-gpu-id 0 \
    --camera-model SIMPLE_PINHOLE \
    -r 1 \
    --iterations 50000 \
    --overwrite

  如果你后面把第 2 张卡修好了, 只要把这 3 个参数改回:

  - --superres-gpu-ids 0,1
  - --colmap-gpu-index 0,1
  - --train-gpu-id 0



  bash /workspace/FastGS/scripts/run_lyra_flashvsr_fastgs.sh \
    --source-video "/workspace/lyra/assets/demo/static/diffusion_output_generated_xhc/0/rgb/xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.mp4" \
    --phase all \
    --pipeline colmap \
    --camera-model SIMPLE_PINHOLE \
    --video-fps 12 \
    --flashvsr-output-root /workspace/lyra/outputs/flashvsr_reference_xhc \
    --prepared-root /workspace/FastGS/data/xhc_flashvsr_sr_root \
    --fastgs-root /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 \
    --model-path /workspace/FastGS/output/xhc_flashvsr_colmap_fps12 \
    --overwrite


  bash /workspace/FastGS/scripts/run_lyra_flashvsr_fastgs.sh \
    --source-path /workspace/lyra/assets/demo/static/diffusion_output_generated_xhc \
    --scene-stem "xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上" \
    --phase all \
    --pipeline colmap \
    --camera-model SIMPLE_PINHOLE \
    --video-fps 6 \
    --flashvsr-output-root /workspace/lyra/outputs/flashvsr_reference_xhc \
    --prepared-root /workspace/FastGS/data/xhc_flashvsr_sr_root \
    --fastgs-root /workspace/FastGS/data/xhc_flashvsr_colmap_fps12 \
    --model-path /workspace/FastGS/output/xhc_flashvsr_colmap_fps12 \
    --overwrite

  bash /workspace/FastGS/scripts/run_lyra_flashvsr_fastgs.sh \
    --source-path /workspace/lyra/assets/demo/static/diffusion_output_generated_xhc_bai \
    --scene-stem "xhc-bai_97e474c6" \
    --phase all \
    --pipeline colmap \
    --camera-model SIMPLE_PINHOLE \
    --video-fps 12 \
    --flashvsr-output-root /workspace/lyra/outputs/flashvsr_reference_xhc_bai \
    --prepared-root /workspace/FastGS/data/xhc_bai_flashvsr_sr_root \
    --fastgs-root /workspace/FastGS/data/xhc_bai_flashvsr_colmap_fps12 \
    --model-path /workspace/FastGS/output/xhc_bai_flashvsr_colmap_fps12 \
    --overwrite


bash /workspace/FastGS/scripts/run_lyra_flashvsr_fastgs.sh \
    --source-video "/workspace/lyra/assets/demo/static/diffusion_output_generated_xhc/0/rgb/xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.mp4" \
    --phase superres \
    --scale 4.0 \
    --mode full \
    --dtype bf16 \
    --quality 10 \
    --fallback-tile-size 1024 \
    --fallback-overlap 256 \
    --flashvsr-output-root /workspace/lyra/outputs/flashvsr_reference_xhc_4x \
    --overwrite