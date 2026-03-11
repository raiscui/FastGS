# LATER_PLANS

## 2026-02-25
- (暂无) 如果后续发现需要补充的二期改进点,在此追加记录.

## 2026-02-25
- 预训练模型下载加速: 如果需要在国内稳定高速下载,建议把 HuggingFace 的 `Goodsleepeverday/fastgs` 权重同步发布到 ModelScope,并在 `README.md` 将链接切换到对应的 `https://modelscope.cn/models/<owner>/<model>`.

## 2026-02-26
- 参数/文档一致性:
  - `train.py` 里 `training_report(...)` 调用目前被注释,导致 `--test_iterations` 在训练过程中不生效(当前评估主要靠 `render.py` + `metrics.py`).
  - `README.md` 的部分参数默认值/描述可能与 `arguments/__init__.py` 不一致.
  - 如果需要降低使用门槛,建议择一落地:
    - 方案1: 恢复 `training_report(...)` 调用,让 `--test_iterations` 真正生效,并明确其开销与默认行为.
    - 方案2: 同步更新 `README.md`,明确训练期不做评估,并以 `train_base.sh`/`train_big.sh` 为准给出参数解释.

## [2026-03-11 06:25:10 UTC] 多机位图片目录的 `convert.py` 支持
- 当前 `convert.py` 默认 `--ImageReader.single_camera 1`,更适合单机位视频或单套图片.
- 对 `data/s01` 这种多机位目录,当前只能通过手动 COLMAP CLI 绕开.
- 后续可考虑新增一套显式多机位模式,至少覆盖:
  - `--ImageReader.single_camera_per_folder 1`
  - 可选的 `PINHOLE` / `SIMPLE_PINHOLE` 选择
  - 保留 `--colmap_executable` 的 GPU 版 COLMAP 接入方式

## [2026-03-11 08:09:36 UTC] `scripts/run_s01_fastgs.sh` 支持固定已知渲染内参
- 当前脚本已经支持 `--camera-model <SIMPLE_PINHOLE|PINHOLE>`.
- 如果后续用户能从 3ds Max 导出真实 FOV / focal / sensor 信息, 可以继续补一档更强的控制:
  - 新增 `--camera-params`
  - 或支持“固定焦距, 不在 BA 中自由漂移”的方案
- 这会比单纯在 `SIMPLE_PINHOLE` / `PINHOLE` 间切换更可控, 尤其适合 synthetic 数据.
