## [2026-03-28 16:44:54 UTC] [Session ID: 019d339f-290f-7032-8726-3095f62295ac] 任务名称: 复用 `my5/my6` 口径完成 `my7` 与 `my8` 的 `35000` 训练和视频/ply 导出

### 任务内容
- 按 `/root/autodl-fs/my5` 与 `/root/autodl-fs/my6` 的稳定处理口径, 完成 `/root/autodl-fs/my7` 与 `/root/autodl-fs/my8` 的全流程处理.
- 覆盖内容包括:
  - `COLMAP -> FastGS prepare`
  - guarded `35000` 分段训练
  - `3DGS ply` 导出
  - `train/test` 视频渲染与 mp4 封装

### 完成过程
- 先复核了 `my7` / `my8` 与 `my5/my6` 的输入结构一致性, 并用单视角抽帧验证确认 `5.333333333333 fps -> 27` 帧可复用.
- 修复了 [scripts/run_lyra_colmap_fastgs.sh](/root/autodl-tmp/home/rais/FastGS/scripts/run_lyra_colmap_fastgs.sh) 的默认 `COLMAP` 路径回退逻辑, 让当前机器可从 `$HOME/.local/opt/colmap-env/bin/colmap` 正常启动.
- 对 `my7` 与 `my8` 都采用了同一套 guarded 自动接力策略:
  - `prepare` 完成后自动校验 `images=324` 与 `sparse/0`
  - 按 `1000` 步一段续训到 `35000`
  - 最后自动 render + ffmpeg 封装视频
- 最终拿到了两套完整产物:
  - `my7`: [ckpt_35000.pth](/root/autodl-tmp/home/rais/FastGS/output/my7_nomask_v1/checkpoints/ckpt_35000.pth), [point_cloud.ply](/root/autodl-tmp/home/rais/FastGS/output/my7_nomask_v1/point_cloud/iteration_35000/point_cloud.ply), [train_iter35000.mp4](/root/autodl-tmp/home/rais/FastGS/output/my7_nomask_v1/videos/train_iter35000.mp4), [test_iter35000.mp4](/root/autodl-tmp/home/rais/FastGS/output/my7_nomask_v1/videos/test_iter35000.mp4)
  - `my8`: [ckpt_35000.pth](/root/autodl-tmp/home/rais/FastGS/output/my8_nomask_v1/checkpoints/ckpt_35000.pth), [point_cloud.ply](/root/autodl-tmp/home/rais/FastGS/output/my8_nomask_v1/point_cloud/iteration_35000/point_cloud.ply), [train_iter35000.mp4](/root/autodl-tmp/home/rais/FastGS/output/my8_nomask_v1/videos/train_iter35000.mp4), [test_iter35000.mp4](/root/autodl-tmp/home/rais/FastGS/output/my8_nomask_v1/videos/test_iter35000.mp4)

### 总结感悟
- 对这类长任务, `prepare` 和训练之间提前挂好自动接力脚本很值, 可以显著减少“人等任务结束再手工接下一段”的空窗.
- `my8` 的 `exhaustive_matcher` 明显比 `my7` 更慢, 但只要 block 编号持续推进, 就应该优先判断为“正常但偏慢”, 不要过早中断.
- 当前这套 `nomask + 5.333333333333 fps + guarded 35000` 的流程, 已在 `my5`、`my6`、`my7`、`my8` 四套同类数据上连续验证通过.
