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
