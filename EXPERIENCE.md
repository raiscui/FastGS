# FastGS 项目经验

## 数据入口与前处理

- 对视频型输入目录, 先按有业务语义的子目录名做发现, 再考虑递归兜底.
  - 目前已经验证过更可靠的优先级是:
    - 根目录直接视频
    - `rgb/`
    - `generated_videos/`
  - 不要一上来全局递归 `*.mp4`, 否则很容易把 `depth`、`mask`、`background`、`debug` 之类的视频一起送进 COLMAP.

- 只要输入根目录已经有 `images/` 和 `sparse/0/`, wrapper 就应该把它视为“已准备好的 COLMAP / FastGS 根目录”.
  - 这类目录不该再退回到 `convert.py` 的视频预处理模式.
  - 最稳的入口策略是:
    - 先识别
    - 再校验
    - 直接进入训练 / 渲染 / 评估

- 多视频抽帧时, 输出帧名必须带稳定前缀.
  - 前缀应来自源视频的相对路径语义, 例如视角目录和业务子目录.
  - 这样后续做:
    - 多机位混合排错
    - RGB / mask 对帧
    - 同名视频去冲突
    都会简单很多.

## Mask 使用口径

- FastGS 里的 mask 不能只作用在 GT 图像上.
  - 如果只做 `gt *= mask`, 但 render 图和 photometric loss 没同步套同一份 mask, 训练会把“忽略区域”误学成“应该变黑”.
  - 正确口径是:
    - render 和 GT 同时套 mask
    - metric map 也走同一份 mask

- 外部 `mask_dir` 一旦启用, 必须要求完整覆盖.
  - 缺失同名 mask 时直接报错.
  - 不要静默跳过, 否则很容易在脏数据上继续训练.

- 如果 mask 来源本身也是视频, 最稳的做法不是先手工导静态图, 而是让前处理阶段把 RGB / mask 一起抽帧, 并保证两边使用同一套帧名前缀与采样率.

## 训练与续训

- `30000` 之后继续跑, 不等于继续做强 densify.
  - 默认训练日程里:
    - `densify_until_iter = 15000`
    - `30000` 之后更像低频收尾
  - 如果要让 resume 后的后半程真正有意义, 至少要一起考虑:
    - `position_lr_max_steps`
    - `opacity_reset_interval`
    - 是否仍希望保留某段 densify 窗口

- 遇到随机 CUDA 非法访问时, “1000 步分段 + checkpoint + 换 seed 重试”在这台机器上已经被真实验证为可用的交付策略.
  - 特别是跨过 `densify_until_iter=15000` 之后, 稳定性通常会明显好一些.

- 对 `my5` 这类 `12` 视角生成视频目录, 已验证的一套稳定训练口径是:
  - 前处理:
    - `--video-fps 5.333333333333`
    - 让总图量从 `972` 压到 `324`
    - 训练默认无 mask, 不把 `rendering_4D_maps/merged_mask.mp4` 接到训练 mask 语义
  - 训练:
    - `-r 1`
    - `--densification_interval 500`
    - `--opacity_reset_interval 3000`
    - `--densify_until_iter 15000`
    - `--position_lr_max_steps 35000`
    - `--loss_thresh 0.1`
    - `--grad_thresh 0.0002`
    - `--grad_abs_thresh 0.0012`
    - `--highfeature_lr 0.005`
    - `--lowfeature_lr 0.0025`
    - `--dense 0.001`
    - `--mult 0.5`
    - `--optimizer_type default`
    - `--eval`
  - 交付:
    - 最终 `35000` 轮视频可直接复用:
      - `bash scripts/run_lyra_colmap_fastgs.sh --phase render --model-path output/<model> --video-iterations 35000 --video-sets both`
    - 最终 `ply` 直接取:
      - `output/<model>/point_cloud/iteration_35000/point_cloud.ply`

## 构建环境

- `pixi` 环境里“PyTorch 能跑”不等于“本地 CUDA 扩展能编”.
  - 真正稳定的本地扩展构建环境至少要同时具备:
    - `cuda-cudart-dev`
    - `cuda-nvcc`
    - `conda-gcc-specs`
    - `ninja`
    - 正常执行位的 `.pixi` 工具链文件

- `cuda_runtime.h` 缺失只是这类构建故障的第一层表象.
  - 把第一层修掉之后, 还可能继续暴露:
    - `crt/host_config.h`
    - `conda.specs`
    - 工具链执行位
    - 源码头文件缺失
  - 这类问题要按“现象 -> 假设 -> 验证 -> 结论”一层层收敛, 不要只盯第一条报错.

## 续训状态契约

- 任何只在训练中临时生成、但不进入 checkpoint 的字段, 都必须在对象生命周期里有稳定默认值.
  - 这类字段至少要做到两件事:
    - `__init__` 里定义
    - `training_setup()` 或等价训练入口里显式重置
- 否则首轮训练可能正常, 但 resume 到后段某个冷门分支时会因为属性缺失崩掉.
  - `tmp_radii` 就是一个已验证过的真实例子.
