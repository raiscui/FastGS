#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

# ------------------------------------------------------------
# 这个脚本放在 `scripts/` 目录下单独运行。
# 为了稳定复用仓库里的 `scene.colmap_loader`, 需要把 repo root
# 主动补进 `sys.path`, 避免相对工作目录差异导致导入失败。
# ------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def load_read_extrinsics_binary():
    # ------------------------------------------------------------
    # 这里故意不走 `import scene.colmap_loader`。
    # 因为 `scene/__init__.py` 会继续导入训练期依赖, 例如 `plyfile`,
    # 这对纯分析脚本来说是额外负担, 也会污染复用性。
    # ------------------------------------------------------------
    module_path = REPO_ROOT / "scene" / "colmap_loader.py"
    spec = importlib.util.spec_from_file_location("colmap_loader_standalone", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"无法加载 COLMAP 读取模块: {module_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.read_extrinsics_binary


read_extrinsics_binary = load_read_extrinsics_binary()


# ------------------------------------------------------------
# 这类多机位视频数据的图像名里已经带了 view / frame 信息。
# 这里优先按 `001_7_xxx_000006` 这种真实命名来解析。
# 如果后续中间段名字再变, 也保留了 split 兜底逻辑。
# ------------------------------------------------------------
IMAGE_NAME_PATTERN = re.compile(
    r"^(?P<global>\d+)_(?P<view>\d+)_.*_(?P<frame>\d+)$"
)

EPS = 1e-8


@dataclass
class PoseFrame:
    image_id: int
    img_name: str
    view: int
    frame: int
    center: np.ndarray
    rotation_cw: np.ndarray
    right: np.ndarray
    up: np.ndarray
    forward: np.ndarray
    observed: int
    observed_ratio: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="分析 COLMAP 位姿连续性, 输出朝向与邻机位相对位姿诊断图."
    )
    parser.add_argument(
        "--images-bin",
        required=True,
        help="COLMAP sparse/0/images.bin 路径.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="图表与 JSON 摘要输出目录.",
    )
    parser.add_argument(
        "--focus-views",
        nargs="+",
        type=int,
        required=True,
        help="重点回查的机位编号, 例如 7 5 8.",
    )
    parser.add_argument(
        "--pose-report-data",
        help="上一轮 pose 报告的 JSON 摘要, 用来叠加 worst-view 标记.",
    )
    parser.add_argument(
        "--transition-summary-mode",
        choices=["all", "contiguous"],
        default="all",
        help=(
            "连续性 summary 统计口径: "
            "`all` 表示保留排序后相邻 surviving frame 的跳跃, "
            "`contiguous` 只统计 frame gap == 1 的真正邻帧."
        ),
    )
    return parser.parse_args()


def normalize(vector: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(vector))
    if norm < EPS:
        return np.zeros_like(vector)
    return vector / norm


def vector_angle_deg(lhs: np.ndarray, rhs: np.ndarray) -> float:
    lhs_norm = normalize(lhs)
    rhs_norm = normalize(rhs)
    cosine = float(np.clip(np.dot(lhs_norm, rhs_norm), -1.0, 1.0))
    return math.degrees(math.acos(cosine))


def rotation_angle_deg(lhs: np.ndarray, rhs: np.ndarray) -> float:
    # ------------------------------------------------------------
    # 这里用相对旋转矩阵的 trace 求角度。
    # 对 camera-to-world / world-to-camera 都等价,
    # 只要两边口径一致, 连续性判断就成立。
    # ------------------------------------------------------------
    relative = lhs @ rhs.T
    cosine = float(np.clip((np.trace(relative) - 1.0) * 0.5, -1.0, 1.0))
    return math.degrees(math.acos(cosine))


def should_use_transition(frame_gap: int, summary_mode: str) -> bool:
    return summary_mode == "all" or frame_gap == 1


def safe_mean(values: list[float]) -> float:
    return float(np.mean(values)) if values else math.nan


def safe_max(values: list[float]) -> float:
    return float(np.max(values)) if values else math.nan


def parse_view_frame(img_name: str) -> tuple[int, int]:
    stem = Path(img_name).stem
    match = IMAGE_NAME_PATTERN.match(stem)
    if match:
        return int(match.group("view")), int(match.group("frame"))

    # ------------------------------------------------------------
    # 兜底口径:
    # 第二段视为 view, 最后一段视为 frame。
    # 如果命名未来有轻微调整, 这一层还能继续工作。
    # ------------------------------------------------------------
    parts = stem.split("_")
    if len(parts) >= 3 and parts[1].isdigit() and parts[-1].isdigit():
        return int(parts[1]), int(parts[-1])

    raise ValueError(f"无法从图像名解析 view/frame: {img_name}")


def load_pose_frames(images_bin: Path) -> dict[int, list[PoseFrame]]:
    images = read_extrinsics_binary(images_bin)
    frames_by_view: dict[int, list[PoseFrame]] = {}

    for image_id in sorted(images.keys()):
        image = images[image_id]
        view, frame = parse_view_frame(image.name)

        # ------------------------------------------------------------
        # COLMAP 的 qvec/tvec 默认是 world-to-camera 外参。
        # 这里统一转成 camera-to-world, 方便直接读相机朝向。
        # 相机中心仍按 C = -R^T * t 计算。
        # ------------------------------------------------------------
        rotation_wc = image.qvec2rotmat()
        rotation_cw = rotation_wc.T
        center = -rotation_cw @ image.tvec

        # ------------------------------------------------------------
        # COLMAP 相机坐标常用约定:
        # +X 向右, +Y 向下, +Z 向前。
        # 为了更符合人读图习惯, 这里把 up 取成 `-Y`。
        # ------------------------------------------------------------
        right = normalize(rotation_cw[:, 0])
        up = normalize(-rotation_cw[:, 1])
        forward = normalize(rotation_cw[:, 2])

        observed = int(np.count_nonzero(image.point3D_ids >= 0))
        observed_ratio = observed / max(len(image.point3D_ids), 1)

        frame_record = PoseFrame(
            image_id=image_id,
            img_name=image.name,
            view=view,
            frame=frame,
            center=center,
            rotation_cw=rotation_cw,
            right=right,
            up=up,
            forward=forward,
            observed=observed,
            observed_ratio=observed_ratio,
        )
        frames_by_view.setdefault(view, []).append(frame_record)

    for view in frames_by_view:
        frames_by_view[view].sort(key=lambda item: item.frame)
    return frames_by_view


def build_view_metrics(
    frames_by_view: dict[int, list[PoseFrame]],
    transition_summary_mode: str = "all",
) -> tuple[list[dict[str, float]], dict[int, list[dict[str, float]]]]:
    view_summary: list[dict[str, float]] = []
    frame_details: dict[int, list[dict[str, float]]] = {}

    for view in sorted(frames_by_view.keys()):
        frames = frames_by_view[view]
        detail_rows: list[dict[str, float]] = []

        translation_steps = []
        rotation_steps = []
        forward_steps = []
        up_steps = []
        right_steps = []
        contiguous_transition_count = 0

        for index, frame in enumerate(frames):
            translation_step = math.nan
            rotation_step = math.nan
            forward_step = math.nan
            up_step = math.nan
            right_step = math.nan
            frame_gap = None
            is_contiguous_transition = False

            if index > 0:
                previous = frames[index - 1]
                frame_gap = frame.frame - previous.frame
                is_contiguous_transition = frame_gap == 1
                translation_step = float(
                    np.linalg.norm(frame.center - previous.center)
                )
                rotation_step = rotation_angle_deg(
                    frame.rotation_cw, previous.rotation_cw
                )
                forward_step = vector_angle_deg(frame.forward, previous.forward)
                up_step = vector_angle_deg(frame.up, previous.up)
                right_step = vector_angle_deg(frame.right, previous.right)

                if is_contiguous_transition:
                    contiguous_transition_count += 1

                # ------------------------------------------------------------
                # 筛帧实验里 surviving frame 之间可能出现 gap.
                # summary 口径可切成:
                # - all: 继续把跳跃也算进连续性
                # - contiguous: 只统计真正 frame_gap == 1 的邻帧
                # ------------------------------------------------------------
                if should_use_transition(frame_gap, transition_summary_mode):
                    translation_steps.append(translation_step)
                    rotation_steps.append(rotation_step)
                    forward_steps.append(forward_step)
                    up_steps.append(up_step)
                    right_steps.append(right_step)

            detail_rows.append(
                {
                    "image_id": frame.image_id,
                    "img_name": frame.img_name,
                    "view": frame.view,
                    "frame": frame.frame,
                    "center_x": float(frame.center[0]),
                    "center_y": float(frame.center[1]),
                    "center_z": float(frame.center[2]),
                    "forward_x": float(frame.forward[0]),
                    "forward_y": float(frame.forward[1]),
                    "forward_z": float(frame.forward[2]),
                    "up_x": float(frame.up[0]),
                    "up_y": float(frame.up[1]),
                    "up_z": float(frame.up[2]),
                    "observed": frame.observed,
                    "observed_ratio": frame.observed_ratio,
                    "frame_gap": frame_gap,
                    "is_contiguous_transition": is_contiguous_transition,
                    "translation_step": translation_step,
                    "rotation_step_deg": rotation_step,
                    "forward_step_deg": forward_step,
                    "up_step_deg": up_step,
                    "right_step_deg": right_step,
                }
            )

        frame_details[view] = detail_rows
        view_summary.append(
            {
                "view": view,
                "count": len(frames),
                "transition_summary_mode": transition_summary_mode,
                "transition_count": len(translation_steps),
                "contiguous_transition_count": contiguous_transition_count,
                "obs_mean": float(np.mean([item.observed for item in frames])),
                "obs_min": int(min(item.observed for item in frames)),
                "ratio_mean": float(np.mean([item.observed_ratio for item in frames])),
                "step_mean": safe_mean(translation_steps),
                "step_max": safe_max(translation_steps),
                "rotation_mean": safe_mean(rotation_steps),
                "rotation_max": safe_max(rotation_steps),
                "forward_mean": safe_mean(forward_steps),
                "forward_max": safe_max(forward_steps),
                "up_mean": safe_mean(up_steps),
                "up_max": safe_max(up_steps),
                "right_mean": safe_mean(right_steps),
                "right_max": safe_max(right_steps),
            }
        )

    return view_summary, frame_details


def make_pair_key(view_a: int, view_b: int) -> str:
    return f"{min(view_a, view_b)}-{max(view_a, view_b)}"


def build_pair_metrics(
    frames_by_view: dict[int, list[PoseFrame]],
    transition_summary_mode: str = "all",
) -> tuple[list[dict[str, float]], dict[str, list[dict[str, float]]]]:
    pair_summary: list[dict[str, float]] = []
    pair_details: dict[str, list[dict[str, float]]] = {}
    sorted_views = sorted(frames_by_view.keys())

    for left, right in zip(sorted_views[:-1], sorted_views[1:]):
        left_frames = {item.frame: item for item in frames_by_view[left]}
        right_frames = {item.frame: item for item in frames_by_view[right]}
        shared_frames = sorted(set(left_frames.keys()) & set(right_frames.keys()))
        if len(shared_frames) < 2:
            continue

        rows: list[dict[str, float]] = []
        rel_distances = []
        rel_rotations = []
        rel_forwards = []
        delta_rel_distances = []
        delta_rel_rotations = []
        delta_rel_forwards = []
        baseline_dir_changes = []
        contiguous_delta_count = 0

        previous_distance = None
        previous_rotation = None
        previous_forward = None
        previous_baseline_dir = None
        previous_frame_id = None

        for frame_id in shared_frames:
            left_pose = left_frames[frame_id]
            right_pose = right_frames[frame_id]

            relative_center = right_pose.center - left_pose.center
            relative_distance = float(np.linalg.norm(relative_center))
            relative_rotation = rotation_angle_deg(
                right_pose.rotation_cw, left_pose.rotation_cw
            )
            relative_forward = vector_angle_deg(
                right_pose.forward, left_pose.forward
            )
            baseline_dir = normalize(relative_center)

            delta_relative_distance = math.nan
            delta_relative_rotation = math.nan
            delta_relative_forward = math.nan
            baseline_dir_change = math.nan
            frame_gap = None
            is_contiguous_transition = False

            if previous_distance is not None:
                frame_gap = frame_id - previous_frame_id
                is_contiguous_transition = frame_gap == 1
                delta_relative_distance = abs(relative_distance - previous_distance)
                delta_relative_rotation = abs(relative_rotation - previous_rotation)
                delta_relative_forward = abs(relative_forward - previous_forward)
                baseline_dir_change = vector_angle_deg(
                    baseline_dir, previous_baseline_dir
                )

                if is_contiguous_transition:
                    contiguous_delta_count += 1

                if should_use_transition(frame_gap, transition_summary_mode):
                    delta_rel_distances.append(delta_relative_distance)
                    delta_rel_rotations.append(delta_relative_rotation)
                    delta_rel_forwards.append(delta_relative_forward)
                    baseline_dir_changes.append(baseline_dir_change)

            rel_distances.append(relative_distance)
            rel_rotations.append(relative_rotation)
            rel_forwards.append(relative_forward)
            rows.append(
                {
                    "pair": make_pair_key(left, right),
                    "view_left": left,
                    "view_right": right,
                    "frame": frame_id,
                    "frame_gap": frame_gap,
                    "is_contiguous_transition": is_contiguous_transition,
                    "relative_distance": relative_distance,
                    "relative_rotation_deg": relative_rotation,
                    "relative_forward_deg": relative_forward,
                    "delta_relative_distance": delta_relative_distance,
                    "delta_relative_rotation_deg": delta_relative_rotation,
                    "delta_relative_forward_deg": delta_relative_forward,
                    "baseline_dir_change_deg": baseline_dir_change,
                }
            )

            previous_distance = relative_distance
            previous_rotation = relative_rotation
            previous_forward = relative_forward
            previous_baseline_dir = baseline_dir
            previous_frame_id = frame_id

        pair_key = make_pair_key(left, right)
        pair_details[pair_key] = rows
        pair_summary.append(
            {
                "pair": pair_key,
                "view_left": left,
                "view_right": right,
                "shared_count": len(shared_frames),
                "delta_transition_summary_mode": transition_summary_mode,
                "delta_transition_count": len(delta_rel_distances),
                "contiguous_delta_transition_count": contiguous_delta_count,
                "relative_distance_mean": float(np.mean(rel_distances)),
                "relative_distance_max": float(np.max(rel_distances)),
                "relative_rotation_mean": float(np.mean(rel_rotations)),
                "relative_rotation_max": float(np.max(rel_rotations)),
                "relative_forward_mean": float(np.mean(rel_forwards)),
                "relative_forward_max": float(np.max(rel_forwards)),
                "delta_relative_distance_mean": safe_mean(delta_rel_distances),
                "delta_relative_distance_max": safe_max(delta_rel_distances),
                "delta_relative_rotation_mean": safe_mean(delta_rel_rotations),
                "delta_relative_rotation_max": safe_max(delta_rel_rotations),
                "delta_relative_forward_mean": safe_mean(delta_rel_forwards),
                "delta_relative_forward_max": safe_max(delta_rel_forwards),
                "baseline_dir_change_mean": safe_mean(baseline_dir_changes),
                "baseline_dir_change_max": safe_max(baseline_dir_changes),
            }
        )

    return pair_summary, pair_details


def load_worst_view_annotations(
    pose_report_data_path: Path | None,
    frame_details: dict[int, list[dict[str, float]]],
) -> list[dict[str, float]]:
    if pose_report_data_path is None:
        return []

    payload = json.loads(pose_report_data_path.read_text(encoding="utf-8"))
    detail_lookup = {
        (view, row["frame"]): row
        for view, rows in frame_details.items()
        for row in rows
    }
    annotations = []

    for worst_item in payload.get("worst_map", []):
        view = int(worst_item["view"])
        frame = int(worst_item["frame"])
        detail = detail_lookup.get((view, frame))
        if detail is None:
            continue

        annotations.append(
            {
                "render_name": worst_item["render_name"],
                "img_name": worst_item["img_name"],
                "view": view,
                "frame": frame,
                "psnr": worst_item["psnr"],
                "ssim": worst_item["ssim"],
                "lpips": worst_item["lpips"],
                "observed": worst_item["observed"],
                "ratio": worst_item["ratio"],
                "translation_step": detail["translation_step"],
                "rotation_step_deg": detail["rotation_step_deg"],
                "forward_step_deg": detail["forward_step_deg"],
                "up_step_deg": detail["up_step_deg"],
            }
        )

    return annotations


def plot_global_orientation_scatter(
    view_summary: list[dict[str, float]],
    focus_views: list[int],
    output_path: Path,
) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(14, 6), layout="constrained")
    x1 = [row["rotation_mean"] for row in view_summary]
    y1 = [row["forward_mean"] for row in view_summary]
    colors = [row["obs_mean"] for row in view_summary]
    scatter = axes[0].scatter(x1, y1, c=colors, cmap="viridis", s=130, edgecolors="black")

    for row in view_summary:
        label = f"v{row['view']}"
        color = "crimson" if row["view"] in focus_views else "black"
        axes[0].annotate(label, (row["rotation_mean"], row["forward_mean"]), color=color, fontsize=10)

    axes[0].set_title("Mean Orientation Step by View")
    axes[0].set_xlabel("mean relative rotation (deg)")
    axes[0].set_ylabel("mean forward change (deg)")
    fig.colorbar(scatter, ax=axes[0], label="mean observed 3D points")

    x2 = [row["rotation_max"] for row in view_summary]
    y2 = [row["forward_max"] for row in view_summary]
    axes[1].scatter(x2, y2, c=colors, cmap="viridis", s=130, edgecolors="black")
    for row in view_summary:
        label = f"v{row['view']}"
        color = "crimson" if row["view"] in focus_views else "black"
        axes[1].annotate(label, (row["rotation_max"], row["forward_max"]), color=color, fontsize=10)

    axes[1].set_title("Max Orientation Step by View")
    axes[1].set_xlabel("max relative rotation (deg)")
    axes[1].set_ylabel("max forward change (deg)")
    fig.savefig(output_path, dpi=220, bbox_inches="tight")
    plt.close(fig)


def plot_focus_view_diagnostics(
    frame_details: dict[int, list[dict[str, float]]],
    focus_views: list[int],
    annotations: list[dict[str, float]],
    output_path: Path,
) -> None:
    fig, axes = plt.subplots(
        len(focus_views),
        3,
        figsize=(16, 4.6 * len(focus_views)),
        sharex=False,
        layout="constrained",
    )
    if len(focus_views) == 1:
        axes = np.expand_dims(axes, axis=0)

    per_view_annotations: dict[int, list[dict[str, float]]] = {}
    for item in annotations:
        per_view_annotations.setdefault(item["view"], []).append(item)

    for row_index, view in enumerate(focus_views):
        rows = frame_details[view]
        frames = [item["frame"] for item in rows]
        observed_ratio = [item["observed_ratio"] for item in rows]
        translation_step = [item["translation_step"] for item in rows]
        rotation_step = [item["rotation_step_deg"] for item in rows]
        forward_step = [item["forward_step_deg"] for item in rows]
        up_step = [item["up_step_deg"] for item in rows]

        axes[row_index, 0].plot(frames, observed_ratio, color="tab:green", marker="o", ms=3)
        axes[row_index, 0].set_title(f"view {view}: observed ratio")
        axes[row_index, 0].set_ylabel("ratio")
        axes[row_index, 0].set_xlabel("frame")
        axes[row_index, 0].grid(alpha=0.25)

        axes[row_index, 1].plot(frames, translation_step, color="tab:blue", marker="o", ms=3, label="translation")
        axes[row_index, 1].plot(frames, rotation_step, color="tab:red", marker="o", ms=3, label="rotation")
        axes[row_index, 1].set_title(f"view {view}: translation / rotation step")
        axes[row_index, 1].set_ylabel("step")
        axes[row_index, 1].set_xlabel("frame")
        axes[row_index, 1].legend(loc="upper right")
        axes[row_index, 1].grid(alpha=0.25)

        axes[row_index, 2].plot(frames, forward_step, color="tab:orange", marker="o", ms=3, label="forward")
        axes[row_index, 2].plot(frames, up_step, color="tab:purple", marker="o", ms=3, label="up")
        axes[row_index, 2].set_title(f"view {view}: forward / up change")
        axes[row_index, 2].set_ylabel("deg")
        axes[row_index, 2].set_xlabel("frame")
        axes[row_index, 2].legend(loc="upper right")
        axes[row_index, 2].grid(alpha=0.25)

        for annotation in per_view_annotations.get(view, []):
            frame = annotation["frame"]
            label = f"{annotation['render_name']} (f{frame})"
            for axis in axes[row_index]:
                axis.axvline(frame, color="crimson", linestyle="--", alpha=0.45)
            axes[row_index, 1].annotate(
                label,
                (frame, annotation["rotation_step_deg"]),
                textcoords="offset points",
                xytext=(5, 8),
                fontsize=8,
                color="crimson",
            )

    fig.savefig(output_path, dpi=220, bbox_inches="tight")
    plt.close(fig)


def plot_neighbor_pair_diagnostics(
    pair_details: dict[str, list[dict[str, float]]],
    focus_views: list[int],
    output_path: Path,
) -> None:
    target_pairs = []
    for view in focus_views:
        for neighbor in (view - 1, view + 1):
            pair_key = make_pair_key(view, neighbor)
            if pair_key in pair_details and pair_key not in target_pairs:
                target_pairs.append(pair_key)

    fig, axes = plt.subplots(
        len(target_pairs),
        3,
        figsize=(16, 4.4 * len(target_pairs)),
        sharex=False,
        layout="constrained",
    )
    if len(target_pairs) == 1:
        axes = np.expand_dims(axes, axis=0)

    for row_index, pair_key in enumerate(target_pairs):
        rows = pair_details[pair_key]
        frames = [item["frame"] for item in rows]
        rel_distance = [item["relative_distance"] for item in rows]
        rel_rotation = [item["relative_rotation_deg"] for item in rows]
        rel_forward = [item["relative_forward_deg"] for item in rows]
        delta_rel_rotation = [item["delta_relative_rotation_deg"] for item in rows]
        delta_rel_distance = [item["delta_relative_distance"] for item in rows]
        baseline_dir_change = [item["baseline_dir_change_deg"] for item in rows]

        axes[row_index, 0].plot(frames, rel_distance, color="tab:blue", marker="o", ms=3)
        axes[row_index, 0].plot(frames, delta_rel_distance, color="tab:cyan", marker="o", ms=3)
        axes[row_index, 0].set_title(f"pair {pair_key}: relative distance")
        axes[row_index, 0].set_ylabel("distance")
        axes[row_index, 0].set_xlabel("frame")
        axes[row_index, 0].legend(["relative", "delta"], loc="upper right")
        axes[row_index, 0].grid(alpha=0.25)

        axes[row_index, 1].plot(frames, rel_rotation, color="tab:red", marker="o", ms=3)
        axes[row_index, 1].plot(frames, delta_rel_rotation, color="tab:pink", marker="o", ms=3)
        axes[row_index, 1].set_title(f"pair {pair_key}: relative rotation")
        axes[row_index, 1].set_ylabel("deg")
        axes[row_index, 1].set_xlabel("frame")
        axes[row_index, 1].legend(["relative", "delta"], loc="upper right")
        axes[row_index, 1].grid(alpha=0.25)

        axes[row_index, 2].plot(frames, rel_forward, color="tab:orange", marker="o", ms=3)
        axes[row_index, 2].plot(frames, baseline_dir_change, color="tab:green", marker="o", ms=3)
        axes[row_index, 2].set_title(f"pair {pair_key}: forward / baseline direction")
        axes[row_index, 2].set_ylabel("deg")
        axes[row_index, 2].set_xlabel("frame")
        axes[row_index, 2].legend(["relative forward", "baseline dir change"], loc="upper right")
        axes[row_index, 2].grid(alpha=0.25)

    fig.savefig(output_path, dpi=220, bbox_inches="tight")
    plt.close(fig)


def plot_focus_forward_quiver(
    frames_by_view: dict[int, list[PoseFrame]],
    focus_views: list[int],
    output_path: Path,
) -> None:
    fig, axes = plt.subplots(1, len(focus_views), figsize=(5.3 * len(focus_views), 5.2), layout="constrained")
    if len(focus_views) == 1:
        axes = [axes]

    for axis, view in zip(axes, focus_views):
        frames = frames_by_view[view]
        xs = [item.center[0] for item in frames]
        zs = [item.center[2] for item in frames]
        u = [item.forward[0] for item in frames]
        v = [item.forward[2] for item in frames]

        axis.plot(xs, zs, color="tab:blue", linewidth=1.5, alpha=0.7)
        axis.scatter(xs, zs, s=25, c=np.linspace(0, 1, len(xs)), cmap="plasma")
        axis.quiver(xs, zs, u, v, angles="xy", scale_units="xy", scale=3.2, color="crimson", alpha=0.75)
        axis.scatter(xs[0], zs[0], color="green", s=80, marker="o", label="start")
        axis.scatter(xs[-1], zs[-1], color="black", s=80, marker="x", label="end")
        axis.set_title(f"view {view}: center + forward (x/z)")
        axis.set_xlabel("x")
        axis.set_ylabel("z")
        axis.legend(loc="best")
        axis.grid(alpha=0.25)
        axis.axis("equal")

    fig.savefig(output_path, dpi=220, bbox_inches="tight")
    plt.close(fig)


def write_json(path: Path, payload: dict) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    images_bin = Path(args.images_bin)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    frames_by_view = load_pose_frames(images_bin)
    focus_views = list(dict.fromkeys(args.focus_views))
    missing_focus_views = sorted(set(focus_views) - set(frames_by_view.keys()))
    if missing_focus_views:
        raise ValueError(f"以下 focus view 不存在于 COLMAP 模型中: {missing_focus_views}")

    view_summary, frame_details = build_view_metrics(
        frames_by_view,
        transition_summary_mode=args.transition_summary_mode,
    )
    pair_summary, pair_details = build_pair_metrics(
        frames_by_view,
        transition_summary_mode=args.transition_summary_mode,
    )
    annotations = load_worst_view_annotations(
        Path(args.pose_report_data) if args.pose_report_data else None,
        frame_details,
    )

    output_payload = {
        "images_bin": str(images_bin),
        "focus_views": focus_views,
        "transition_summary_mode": args.transition_summary_mode,
        "view_summary": view_summary,
        "frame_details": frame_details,
        "pair_summary": pair_summary,
        "pair_details": pair_details,
        "worst_view_annotations": annotations,
    }
    write_json(output_dir / "pose_continuity_data.json", output_payload)

    plot_global_orientation_scatter(
        view_summary=view_summary,
        focus_views=focus_views,
        output_path=output_dir / "orientation_global_scatter.png",
    )
    plot_focus_view_diagnostics(
        frame_details=frame_details,
        focus_views=focus_views,
        annotations=annotations,
        output_path=output_dir / "focus_view_orientation_diagnostics.png",
    )
    plot_neighbor_pair_diagnostics(
        pair_details=pair_details,
        focus_views=focus_views,
        output_path=output_dir / "neighbor_relative_pose_diagnostics.png",
    )
    plot_focus_forward_quiver(
        frames_by_view=frames_by_view,
        focus_views=focus_views,
        output_path=output_dir / "focus_view_forward_quiver.png",
    )


if __name__ == "__main__":
    main()
