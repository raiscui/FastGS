# 默认六文件续档说明

## 时间
- 2026-03-27 09:41:03 UTC

## 原因
- 默认主线文件超过 1000 行:
  - `task_plan.md`
  - `notes.md`
  - `WORKLOG.md`
- 按项目规则先做一次持续学习, 再执行续档与归档.

## 本轮提取出的可复用知识
- 视频型输入目录不能盲目全局递归找视频.
- `images + sparse/0` 应被识别为已准备好的可训练根目录.
- RGB / mask 如果都来自视频, 前处理应负责成对抽帧与稳定命名.
- mask 训练必须让 render 与 GT 共用同一份 mask, 不能只黑掉 GT.
- Pixi + CUDA 扩展构建问题经常是分层叠加, 不能只盯第一条报错.

## 已同步到长期文件
- `EXPERIENCE.md`
- `AGENTS.md`

## 本次归档文件
- `archive/default_history/task_plan_2026-03-27_094103.md`
- `archive/default_history/notes_2026-03-27_094103.md`
- `archive/default_history/WORKLOG_2026-03-27_094103.md`
- `archive/default_history/task_plan_2026-03-14_083052.md`
- `archive/default_history/notes_2026-03-14_163400.md`

## 后续活跃任务
- 支持 `/root/autodl-fs/my5` 这类多镜头视频目录, 走 `COLMAP -> FastGS` 流程.
- 首轮训练参数对齐 `cmd.md` 中 `my4_mask_guarded_v4` 的配置.
